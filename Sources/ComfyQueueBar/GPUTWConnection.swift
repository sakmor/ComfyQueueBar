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
            || response.mimeType?.lowercased() == "text/html" { throw GPUTWError.signInRequired }
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
