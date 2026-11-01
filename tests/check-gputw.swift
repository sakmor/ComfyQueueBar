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
        let validID = "6cade7d4-03ec-46bc-8fef-7209df8628b1"
        precondition(GPUTWSSHTunnel.normalizedID(" pod-" + validID.uppercased() + " ") == validID)
        for invalid in ["", "6cade7d4", "-oProxyCommand=x", validID + "@evil.test"] {
            precondition(GPUTWSSHTunnel.normalizedID(invalid) == nil)
        }
        print("PASS: validate GPUtw SSH instance IDs")
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

        // Proxy error pages are often HTML. Preserve their HTTP status so a
        // missing route or unavailable service is not mistaken for expired login.
        for status in [404, 502, 503] {
            CloudFixture.handler = { _ in (status, ["Content-Type": "text/html"], Data("proxy error".utf8)) }
            let (_, response) = try await client.data(for: URLRequest(url: queueURL))
            precondition((response as? HTTPURLResponse)?.statusCode == status)
        }
        print("PASS: HTML 404/502/503 responses preserve the diagnostic HTTP status")

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

        let platformConfiguration = URLSessionConfiguration.ephemeral
        platformConfiguration.protocolClasses = [CloudFixture.self]
        let connector = GPUTWPortConnector(configuration: platformConfiguration)
        let target = URL(string: "https://8090-instance-a.gputw.ai")!
        var platformInstance: [String: Any] = ["id": "instance-a", "status": "RUNNING", "allowedPorts": [8080, 18080],
            "portAccess": ["8080": ["mode": "unlisted", "hasPassword": true], "18080": ["mode": "public"]]]
        var platformCalls: [String] = []
        var handoffAddress = target.absoluteString + "/?__t=fixture-short-lived"
        func apiResponse(_ object: [String: Any]) -> (Int, [String: String], Data) {
            (200, ["Content-Type": "application/json"], try! JSONSerialization.data(withJSONObject: ["success": true, "data": object, "error": NSNull()]))
        }
        CloudFixture.handler = { request in
            precondition(request.url?.host == "api.gputw.ai" && request.url?.scheme == "https")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer gputw_live_fixture-only")
            precondition(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("ComfyQueueBar/") == true)
            precondition(request.value(forHTTPHeaderField: "Cookie") == nil && !request.httpShouldHandleCookies)
            let method = request.httpMethod!
            let route = request.url!.path
            platformCalls.append(method + " " + route)
            if method == "GET" {
                precondition(route == "/api/instances/instance-a")
                return apiResponse(platformInstance)
            }
            var bytes = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            if method == "PATCH" {
                precondition(route == "/api/instances/instance-a/ports")
                precondition(body["ports"] as? [Int] == [8080, 18080, 8090])
                let access = body["portAccess"] as! [String: [String: String]]
                precondition(access == ["8080": ["mode": "unlisted"], "18080": ["mode": "public"], "8090": ["mode": "private"]],
                             "Retain other ports and access modes; never overwrite existing passwords")
                platformInstance["allowedPorts"] = body["ports"]
                platformInstance["portAccess"] = access
                return apiResponse(platformInstance)
            }
            precondition(method == "POST" && route == "/api/instances/instance-a/access-token")
            precondition(body["port"] as? Int == 8090 && body["path"] as? String == "")
            return apiResponse(["url": handoffAddress, "port": 8090, "expiresIn": 90])
        }
        let handoff = try await connector.prepareAccess(to: target, apiKey: "gputw_live_fixture-only")
        precondition(handoff.absoluteString == handoffAddress)
        precondition(platformCalls.map { $0.components(separatedBy: " ")[0] } == ["GET", "PATCH", "POST"])
        platformCalls = []
        var existingAccess = platformInstance["portAccess"] as! [String: [String: String]]
        existingAccess["8090"] = ["mode": "unlisted"]
        platformInstance["portAccess"] = existingAccess
        _ = try await connector.prepareAccess(to: target, apiKey: "gputw_live_fixture-only")
        precondition(platformCalls.map { $0.components(separatedBy: " ")[0] } == ["GET", "POST"], "An enabled port must not be patched again")
        print("PASS: enable exact 8090 privately, preserve all other HTTP ports/modes/passwords, mint its handoff; skip updates when already enabled")

        handoffAddress = "https://8090-instance-b.gputw.ai/?__t=fixture"
        do { _ = try await connector.prepareAccess(to: target, apiKey: "gputw_live_fixture-only"); preconditionFailure("Wrong service handoff accepted") }
        catch GPUTWSetupError.unsafeHandoff {} catch { throw error }
        platformCalls = []
        platformInstance["status"] = "STOPPED"
        do { _ = try await connector.prepareAccess(to: target, apiKey: "gputw_live_fixture-only"); preconditionFailure("Stopped instance accepted") }
        catch GPUTWSetupError.notRunning {} catch { throw error }
        precondition(platformCalls.count == 1)
        platformCalls = []
        for key in ["", "wrong", "gputw_live_bad\r\nInjected: value"] {
            do { _ = try await connector.prepareAccess(to: target, apiKey: key); preconditionFailure("Invalid API key accepted") }
            catch GPUTWSetupError.invalidKey {} catch { throw error }
        }
        precondition(platformCalls.isEmpty)
        platformInstance["status"] = "RUNNING"
        platformInstance["id"] = "different-instance"
        do { _ = try await connector.prepareAccess(to: target, apiKey: "gputw_live_fixture-only"); preconditionFailure("Mismatched instance configuration accepted") }
        catch GPUTWSetupError.invalidResponse {} catch { throw error }
        precondition(platformCalls.count == 1)
        platformInstance["id"] = "instance-a"
        platformCalls = []
        platformInstance["allowedPorts"] = Array(11000..<11020)
        do { _ = try await connector.prepareAccess(to: target, apiKey: "gputw_live_fixture-only"); preconditionFailure("Port limit ignored") }
        catch GPUTWSetupError.portLimit {} catch { throw error }
        precondition(platformCalls.count == 1)
        print("PASS: wrong-instance handoffs, stopped instances, invalid keys and port limits fail without unintended writes")

        for status in [401, 403, 404, 429, 503] {
            CloudFixture.handler = { _ in (status, ["Content-Type": "text/html"], Data("error".utf8)) }
            do { _ = try await connector.prepareAccess(to: target, apiKey: "gputw_live_fixture-only"); preconditionFailure("API error ignored") }
            catch GPUTWSetupError.apiStatus(let code) { precondition(code == status) } catch { throw error }
        }
        CloudFixture.handler = { _ in preconditionFailure("Cancelled setup must not issue a request") }
        let cancelledSetup = Task { try await connector.prepareAccess(to: target, apiKey: "gputw_live_fixture-only") }
        cancelledSetup.cancel()
        do { _ = try await cancelledSetup.value; preconditionFailure("Cancelled setup succeeded") }
        catch is CancellationError {} catch { throw error }
        print("PASS: platform errors and cancellation stop setup; API credentials stay on the API host")
        print("GPUtw regression checks passed (fixture cookies only; no account or live generation).")
    }
}
