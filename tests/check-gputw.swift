import Foundation

@MainActor
final class MemoryCookies: BrowserCookieStore {
    var values: [HTTPCookie] = []
    var received: [HTTPCookie] = []
    var beforeRead: (() -> Void)?
    func cookies() async -> [HTTPCookie] { beforeRead?(); return values }
    func setCookie(_ cookie: HTTPCookie) async { received.append(cookie) }
}

final class CloudFixture: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, headers, data) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct GPUTWChecks {
    @MainActor static func main() async throws {
        let origin = URL(string: "https://8080-instance-a.gputw.ai")!
        let queueURL = origin.appendingPathComponent("queue")
        precondition(GPUTWAddress.serviceOrigin(URL(string: origin.absoluteString + "/handoff?token=secret#fragment")!) == origin)
        for address in ["https://gputw.ai/dashboard", "https://8080-a.gputw.ai.evil.test", "https://nested.8080-a.gputw.ai", "http://8080-a.gputw.ai", "https://8080-a.gputw.ai:8443", "https://user:secret@8080-a.gputw.ai", "https://99999-a.gputw.ai", "https://8080-.gputw.ai"] {
            precondition(GPUTWAddress.serviceOrigin(URL(string: address)!) == nil, address)
        }
        print("PASS: only HTTPS GPUtw instance origins; handoff secrets removed")

        func cookie(_ name: String, domain: String = "8080-instance-a.gputw.ai", path: String = "/", expires: Date? = nil) -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "fixture", .domain: domain, .path: path, .secure: "TRUE"]
            if let expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)!
        }
        let store = MemoryCookies()
        store.values = [cookie("instance"), cookie("parent", domain: ".gputw.ai"), cookie("account-host-only", domain: "gputw.ai"),
                        cookie("other-instance", domain: "8080-instance-b.gputw.ai"), cookie("unrelated", domain: ".example.com"),
                        cookie("expired", expires: .distantPast), cookie("path-specific", path: "/queue"), cookie("path-prefix", path: "/que")]
        precondition(Set(GPUTWAddress.cookies(store.values, for: queueURL).map(\.name)) == Set(["instance", "parent", "path-specific"]))
        precondition(GPUTWAddress.cookies(store.values, for: URL(string: "http://8080-instance-a.gputw.ai/queue")!).isEmpty)
        precondition(Set(GPUTWAddress.cookies(store.values, for: origin.appendingPathComponent("view")).map(\.name)) == Set(["instance", "parent"]))
        print("PASS: cookie domain, path, expiry and HTTPS isolation")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudFixture.self]
        let client = ComfyHTTPClient(cookieStore: store, configuration: configuration)
        var calls = 0
        CloudFixture.handler = { request in
            calls += 1
            precondition(request.url == queueURL)
            let header = request.value(forHTTPHeaderField: "Cookie")!
            precondition(header.contains("instance=fixture") && header.contains("parent=fixture") && header.contains("path-specific=fixture"))
            precondition(!header.contains("account-host-only") && !header.contains("other-instance") && !header.contains("expired") && !header.contains("unrelated"))
            precondition(!request.httpShouldHandleCookies)
            return (200, ["Content-Type": "application/json", "Set-Cookie": "renewed=abc; Path=/; Secure; HttpOnly"], Data(#"{"queue_running":[],"queue_pending":[]}"#.utf8))
        }
        try await client.verifyComfyUI(at: origin)
        precondition(calls == 1 && store.received.last?.name == "renewed")
        print("PASS: authenticated ComfyUI queue verification and instance cookie renewal")

        for path in ["history?max_items=200", "comfyqueuebar/queue-progress", "view?filename=result.mp4&type=output", "interrupt", "prompt"] {
            var request = URLRequest(url: URL(string: origin.absoluteString + "/" + path)!)
            if path == "interrupt" || path == "prompt" {
                request.httpMethod = "POST"
                request.httpBody = Data(#"{"prompt_id":"test"}"#.utf8)
            }
            CloudFixture.handler = { received in
                precondition(received.url == request.url && received.httpMethod == request.httpMethod)
                precondition(received.value(forHTTPHeaderField: "Cookie") == "instance=fixture; parent=fixture")
                return (200, ["Content-Type": "application/json", "Set-Cookie": "account=bad; Domain=.gputw.ai; Path=/; Secure"], Data("{}".utf8))
            }
            _ = try await client.data(for: request)
        }
        precondition(store.received.count == 1, "Service responses must not overwrite parent account cookies")
        print("PASS: history, progress, media and action requests share scoped auth")

        let mediaURL = origin.appendingPathComponent("view")
        CloudFixture.handler = { request in
            precondition(request.url == mediaURL)
            precondition(request.value(forHTTPHeaderField: "Cookie") == "instance=fixture; parent=fixture")
            return (200, ["Content-Type": "video/mp4"], Data("fixture video bytes".utf8))
        }
        let (temporary, response) = try await client.download(for: URLRequest(url: mediaURL))
        precondition((response as? HTTPURLResponse)?.statusCode == 200)
        let downloaded = try Data(contentsOf: temporary)
        precondition(downloaded == Data("fixture video bytes".utf8))
        try FileManager.default.removeItem(at: temporary)
        CloudFixture.handler = { _ in (200, ["Content-Type": "text/html"], Data("login".utf8)) }
        do { _ = try await client.download(for: URLRequest(url: mediaURL)); preconditionFailure("Login page downloaded as media") }
        catch GPUTWError.signInRequired {} catch { throw error }
        print("PASS: authenticated media downloads and rejection of HTML instead of video")

        for (status, type) in [(302, "text/plain"), (401, "application/json"), (403, "application/json"), (200, "text/html")] {
            CloudFixture.handler = { _ in (status, ["Content-Type": type, "Location": "https://gputw.ai/login"], Data("login".utf8)) }
            do { try await client.verifyComfyUI(at: origin); preconditionFailure("Login must not count as an idle queue") }
            catch GPUTWError.signInRequired {} catch { throw error }
        }
        for body in [#"{"status":"ok"}"#, "<html>Login</html>"] {
            CloudFixture.handler = { _ in (200, ["Content-Type": "application/json"], Data(body.utf8)) }
            do { try await client.verifyComfyUI(at: origin); preconditionFailure("Non-ComfyUI response accepted") }
            catch GPUTWError.notComfyUI {} catch { throw error }
        }
        print("PASS: expired sessions, HTML login and unrelated JSON cannot imply completion")

        // Exercise the production delegate, including POST redirects to sibling instances.
        let policy = GPUTWRedirectPolicy()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: queueURL)
        for target in ["https://8080-instance-b.gputw.ai/queue", "https://gputw.ai/login", "http://8080-instance-a.gputw.ai/queue", "https://evil.test/queue"] {
            var redirected = URLRequest(url: URL(string: target)!); redirected.httpMethod = "POST"
            redirected.setValue("instance=fixture", forHTTPHeaderField: "Cookie")
            var callbackCalled = false
            policy.urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: queueURL, statusCode: 307, httpVersion: nil, headerFields: nil)!, newRequest: redirected) { result in
                callbackCalled = true; precondition(result == nil)
            }
            precondition(callbackCalled)
        }
        print("PASS: redirects never replay cookies or mutations to other destinations")

        CloudFixture.handler = { _ in preconditionFailure("Cleared authentication must not start a request") }
        store.beforeRead = { client.beginClearingAuthentication() }
        do { _ = try await client.data(for: URLRequest(url: queueURL)); preconditionFailure("Stale request accepted") }
        catch is CancellationError {} catch { throw error }
        store.beforeRead = nil
        do { _ = try await client.data(for: URLRequest(url: queueURL)); preconditionFailure("Request during logout accepted") }
        catch GPUTWError.signInRequired {} catch { throw error }
        client.finishClearingAuthentication()
        print("PASS: clearing login invalidates pending authentication and suspends requests")
        print("GPUtw regression checks passed (fixture cookies only; no account or live generation).")
    }
}
