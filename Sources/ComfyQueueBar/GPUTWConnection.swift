import Foundation
import WebKit

enum ComfyQueuePayload {
    static func isValid(_ object: [String: Any]) -> Bool {
        ["queue_running", "queue_pending"].allSatisfy { key in
            guard let rows = object[key] as? [[Any]] else { return false }
            return rows.allSatisfy { $0.count > 1 && ($0[1] as? String)?.isEmpty == false }
        }
    }
}

/// GPUtw's documented HTTP service addresses are <port>-<instance-id>.gputw.ai.
/// Handoff query strings belong to the browser, never to a saved server address.
enum GPUTWAddress {
    static let dashboard = URL(string: "https://gputw.ai/dashboard")!

    static func instanceID(_ url: URL) -> String? {
        guard let host = serviceOrigin(url)?.host else { return nil }
        return String(host.dropLast(".gputw.ai".count).split(separator: "-", maxSplits: 1)[1])
    }

    static func serviceOrigin(_ url: URL, port: Int) -> URL? {
        guard (1024...65535).contains(port), let id = instanceID(url) else { return nil }
        return URL(string: "https://\(port)-\(id).gputw.ai")
    }

    static func serviceOrigin(_ url: URL) -> URL? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased(), host.hasSuffix(".gputw.ai") else { return nil }
        let label = String(host.dropLast(".gputw.ai".count))
        let components = label.split(separator: "-", maxSplits: 1)
        guard components.count == 2, let port = Int(components[0]), (1024...65535).contains(port),
              components[1].range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://" + host)
    }

    /// GPUtw commonly exposes the same ComfyUI pod on 8080 and 8090. When an
    /// inspected queue is empty, this gives the review flow a safe, same-pod
    /// alternative to check without silently changing the selected server.
    static func pairedServiceOrigin(_ url: URL) -> URL? {
        guard let origin = serviceOrigin(url), let host = origin.host else { return nil }
        let label = String(host.dropLast(".gputw.ai".count))
        let components = label.split(separator: "-", maxSplits: 1)
        guard components.count == 2, let port = Int(components[0]) else { return nil }
        let pairedPort: Int
        switch port {
        case 8080: pairedPort = 8090
        case 8090: pairedPort = 8080
        default: return nil
        }
        return URL(string: "https://\(pairedPort)-\(components[1]).gputw.ai")
    }

    static func isDashboard(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "gputw.ai"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    static func cookies(_ cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> [HTTPCookie] {
        guard serviceOrigin(url) != nil, let host = url.host?.lowercased() else { return [] }
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let domainMatches = domain.hasPrefix(".")
                ? host == String(domain.dropFirst()) || host.hasSuffix(domain)
                : host == domain
            let path = url.path.isEmpty ? "/" : url.path
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = path == cookiePath || (path.hasPrefix(cookiePath)
                && (cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).hasPrefix("/")))
            return domainMatches && pathMatches && (cookie.expiresDate.map { $0 > now } ?? true)
        }.sorted { $0.path.count > $1.path.count }
    }
}

enum GPUTWSetupError: LocalizedError {
    case invalidKey, invalidResponse, notRunning, portLimit, unsafeHandoff, apiStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return L10n.text("Enter a GPUtw API key with instances:read and ports:manage permissions.")
        case .invalidResponse: return L10n.text("GPUtw returned an unexpected configuration. No further changes were made. Retry or use the dashboard.")
        case .notRunning: return L10n.text("This GPUtw instance is not running. Start it in the dashboard, then connect again.")
        case .portLimit: return L10n.text("This instance already has 20 HTTP ports. Manage its ports in the GPUtw dashboard.")
        case .unsafeHandoff: return L10n.text("GPUtw returned a sign-in link for a different service. Please retry.")
        case .apiStatus(let code):
            if code == 401 || code == 403 { return L10n.text("GPUtw rejected the API request. Check the key and its instances:read and ports:manage permissions.") }
            return L10n.text("GPUtw setup returned HTTP %@. Retry or check the dashboard.", String(code))
        }
    }
}

/// Official GPUtw API: GET the current instance, merge the HTTP port list,
/// PATCH only if missing, then mint the target service's short-lived handoff.
/// API keys are sent only to this fixed API host, never to the browser/service.
@MainActor
final class GPUTWPortConnector {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: GPUTWRedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func prepareAccess(to origin: URL, apiKey: String) async throws -> URL {
        guard GPUTWAddress.serviceOrigin(origin) == origin,
              let id = GPUTWAddress.instanceID(origin),
              let port = origin.host?.split(separator: "-").first.flatMap({ Int($0) }) else { throw GPUTWError.notComfyUI }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("gputw_live_"), key.count > "gputw_live_".count,
              !key.contains(where: { $0.isWhitespace || $0.isNewline }),
              !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw GPUTWSetupError.invalidKey }

        func request(_ suffix: String = "", method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
            try Task.checkCancellation()
            var request = URLRequest(url: URL(string: "https://api.gputw.ai/api/instances/" + id + suffix)!)
            request.httpMethod = method; request.timeoutInterval = 15
            request.httpShouldHandleCookies = false
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            request.setValue("ComfyQueueBar/1.7 GPUtw-Connect", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw GPUTWSetupError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw GPUTWSetupError.apiStatus(response.statusCode) }
            guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  envelope["success"] as? Bool == true,
                  let object = envelope["data"] as? [String: Any] else { throw GPUTWSetupError.invalidResponse }
            return object
        }

        func configuration(_ object: [String: Any]) throws -> (ports: [Int], access: [String: [String: String]]) {
            guard object["id"] as? String == id,
                  let status = object["status"] as? String else { throw GPUTWSetupError.invalidResponse }
            guard status == "RUNNING" else { throw GPUTWSetupError.notRunning }
            guard let ports = object["allowedPorts"] as? [Int], ports.count <= 20,
                  Set(ports).count == ports.count,
                  ports.allSatisfy({ (1024...65535).contains($0) }),
                  let rawAccess = object["portAccess"] as? [String: Any] else { throw GPUTWSetupError.invalidResponse }
            var access: [String: [String: String]] = [:]
            for number in ports {
                let entry = rawAccess[String(number)]
                let mode: String
                if let entry {
                    guard let entry = entry as? [String: Any], let value = entry["mode"] as? String,
                          ["private", "public", "unlisted"].contains(value) else { throw GPUTWSetupError.invalidResponse }
                    mode = value
                } else { mode = "private" }
                // Omit password: GPUtw retains existing unlisted passwords.
                access[String(number)] = ["mode": mode]
            }
            return (ports, access)
        }

        let current = try configuration(await request())
        if !current.ports.contains(port) {
            guard current.ports.count < 20 else { throw GPUTWSetupError.portLimit }
            var access = current.access
            access[String(port)] = ["mode": "private"]
            let ports = current.ports + [port]
            let updated = try configuration(await request("/ports", method: "PATCH", body: ["ports": ports, "portAccess": access]))
            guard Set(updated.ports) == Set(ports), updated.access == access else { throw GPUTWSetupError.invalidResponse }
        }
        let handoff = try await request("/access-token", method: "POST", body: ["port": port, "path": ""])
        guard handoff["port"] as? Int == port,
              let value = handoff["url"] as? String, let url = URL(string: value),
              GPUTWAddress.serviceOrigin(url) == origin else { throw GPUTWSetupError.unsafeHandoff }
        return url
    }
}

enum GPUTWError: LocalizedError {
    case signInRequired, notComfyUI
    var errorDescription: String? {
        switch self {
        case .signInRequired: return L10n.text("Sign in to GPUtw again, then open your ComfyUI Web UI.")
        case .notComfyUI: return L10n.text("Open a ComfyUI Web UI in this window before connecting.")
        }
    }
}

@MainActor
protocol BrowserCookieStore {
    func cookies() async -> [HTTPCookie]
    func setCookie(_ cookie: HTTPCookie) async
}

@MainActor
struct GPUTWCookieStore: BrowserCookieStore {
    func cookies() async -> [HTTPCookie] {
        await WKWebsiteDataStore.default().httpCookieStore.allCookies()
    }
    func setCookie(_ cookie: HTTPCookie) async {
        await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
    }
}

// Never replay service cookies or a POST body at a redirect target, including
// another instance belonging to the same provider. Login redirects use WebKit.
final class GPUTWRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class ComfyHTTPClient {
    static let shared = ComfyHTTPClient()
    private let cookieStore: any BrowserCookieStore
    private let session: URLSession
    private var generation = UUID()
    private var isClearing = false

    init(cookieStore: (any BrowserCookieStore)? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        self.cookieStore = cookieStore ?? GPUTWCookieStore()
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: GPUTWRedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    /// Invalidates in-flight results when the user clears the browser session.
    func beginClearingAuthentication() { generation = UUID(); isClearing = true }
    func finishClearingAuthentication() { isClearing = false }

    private func authenticated(_ request: URLRequest) async throws -> URLRequest {
        guard !isClearing else { throw GPUTWError.signInRequired }
        guard let url = request.url, GPUTWAddress.serviceOrigin(url) != nil else { throw GPUTWError.notComfyUI }
        var request = request
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let cookies = GPUTWAddress.cookies(await cookieStore.cookies(), for: url)
        // Avoid Foundation's formatting of same-name cookies at different paths.
        let header = cookies.map { $0.name + "=" + $0.value }.joined(separator: "; ")
        request.setValue(header.isEmpty ? nil : header, forHTTPHeaderField: "Cookie")
        return request
    }

    private func received(_ response: URLResponse, generation expected: UUID) async throws {
        guard expected == generation else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse, let url = response.url,
              GPUTWAddress.serviceOrigin(url) != nil else { throw URLError(.badServerResponse) }
        if (300..<400).contains(response.statusCode) || [401, 403].contains(response.statusCode)
            || ((200..<300).contains(response.statusCode) && response.mimeType?.lowercased() == "text/html") {
            throw GPUTWError.signInRequired
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            if let name = entry.key as? String, let value = entry.value as? String { result[name] = value }
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            guard expected == generation else { throw CancellationError() }
            // Only accept updates scoped to this instance, never parent/account cookies.
            guard cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == url.host?.lowercased() else { continue }
            await cookieStore.setCookie(cookie)
        }
        guard expected == generation else { throw CancellationError() }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let url = request.url { try GPUTWSSHTunnel.checkOwnedEndpoint(url) }
        guard let url = request.url, GPUTWAddress.serviceOrigin(url) != nil else {
            return try await URLSession.shared.data(for: request)
        }
        let expected = generation
        let request = try await authenticated(request)
        guard expected == generation else { throw CancellationError() }
        let result = try await session.data(for: request)
        try await received(result.1, generation: expected)
        return result
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        if let url = request.url { try GPUTWSSHTunnel.checkOwnedEndpoint(url) }
        guard let url = request.url, GPUTWAddress.serviceOrigin(url) != nil else {
            return try await URLSession.shared.download(for: request)
        }
        let expected = generation
        let request = try await authenticated(request)
        guard expected == generation else { throw CancellationError() }
        let result = try await session.download(for: request)
        do { try await received(result.1, generation: expected) }
        catch { try? FileManager.default.removeItem(at: result.0); throw error }
        return result
    }

    func verifyComfyUI(at origin: URL) async throws {
        guard GPUTWAddress.serviceOrigin(origin) == origin else { throw GPUTWError.notComfyUI }
        var request = URLRequest(url: origin.appendingPathComponent("queue"))
        request.timeoutInterval = 15
        let (data, response) = try await data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              ComfyQueuePayload.isValid(object) else { throw GPUTWError.notComfyUI }
    }
}
