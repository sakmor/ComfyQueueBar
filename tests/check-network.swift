import AppKit
import Foundation

// URLProtocol intercepts every URLSession request: these tests cannot contact ComfyUI.
let validationSuite = "io.github.sakmor.comfyqueuebar.tests." + UUID().uuidString
let validationDefaults = UserDefaults(suiteName: validationSuite)!

final class FixtureProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest) -> (Int, Any))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let (status, object) = Self.handler(request)
        Self.lock.unlock()
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ServerFixture {
    enum Mode { case normal, originalStarts, refuseDelete, offlineAfterSubmit, staleStop, stalePending }
    let graph: [String: Any] = ["12": ["class_type": "KSampler", "_meta": ["title": "Test sampler"]]]
    let extra: [String: Any] = ["extra_pnginfo": ["workflow": ["name": "Disposable test"]]]
    var running = ["running-original"]
    var pending = ["pending-original", "pending-other"]
    var mode: Mode = .normal
    var queueStatus = 200
    var queueBody: [String: Any]?
    var historyStatus = 200
    var historyBody: [String: Any] = [:]
    var progressStatus = 200
    var progressID = "running-original"
    var submitted = false
    var mutations: [(String, [String: Any])] = []
    var paths: [String] = []
    func row(_ id: String) -> [Any] { [1, id, graph, extra] }
    func handle(_ request: URLRequest) -> (Int, Any) {
        let url = request.url!
        precondition(url.host == "fixture.invalid", "Unexpected external request")
        paths.append(url.path)
        let route = url.lastPathComponent
        if request.httpMethod == "POST" {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            mutations.append((route, body))
            if route == "prompt" {
                precondition(body["front"] as? Bool == true)
                precondition(NSDictionary(dictionary: body["prompt"] as! [String: Any]).isEqual(to: graph))
                precondition(NSDictionary(dictionary: body["extra_data"] as! [String: Any]).isEqual(to: extra))
                submitted = true
                pending.insert("replacement-new", at: 0)
                if mode == .originalStarts {
                    pending.removeAll { $0 == "pending-original" }
                    running.append("pending-original")
                }
                return (200, ["prompt_id": "replacement-new"])
            }
            if route == "queue" {
                let ids = body["delete"] as! [String]
                if !(mode == .refuseDelete && ids == ["pending-original"]) {
                    pending.removeAll { ids.contains($0) }
                }
                return (200, [:])
            }
            if route == "interrupt" {
                let id = body["prompt_id"] as! String
                running.removeAll { $0 == id }
                return (200, [:])
            }
            preconditionFailure("Unexpected mutation: \(route)")
        }
        if route == "queue" {
            precondition(request.cachePolicy == .reloadIgnoringLocalCacheData, "Queue freshness must not come from a cached response")
            if submitted && mode == .offlineAfterSubmit { return (503, ["error": "fixture disconnected"]) }
            if mode == .staleStop { running = [] }
            if mode == .stalePending { pending.removeAll { $0 == "pending-original" } }
            return (queueStatus, queueBody ?? ["queue_running": running.map(row), "queue_pending": pending.map(row)])
        }
        if route == "queue-progress" {
            return (progressStatus, ["prompt_id": progressID, "node_id": "12", "value": 3, "max": 10, "percent": 30, "state": "running"])
        }
        if route == "history" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            precondition(query == [URLQueryItem(name: "max_items", value: "200")] || query == [URLQueryItem(name: "max_items", value: "20")])
            return (historyStatus, historyBody)
        }
        preconditionFailure("Unexpected route: \(route)")
    }
}

@main
struct NetworkChecks {
    @MainActor static func main() async {
        let now = Date()
        precondition(MonitoringState.resolve(connected: false, loading: true, needsSignIn: false, lastUpdated: nil, hasError: false, now: now) == .checking)
        precondition(MonitoringState.resolve(connected: false, loading: true, needsSignIn: false, lastUpdated: nil, hasError: true, now: now) == .disconnected)
        precondition(MonitoringState.resolve(connected: true, loading: true, needsSignIn: false, lastUpdated: now.addingTimeInterval(-29), hasError: false, now: now) == .connected)
        precondition(MonitoringState.resolve(connected: true, loading: true, needsSignIn: false, lastUpdated: now.addingTimeInterval(-30), hasError: false, now: now) == .stale)
        precondition(MonitoringState.resolve(connected: false, loading: true, needsSignIn: true, lastUpdated: now, hasError: true, now: now) == .signInRequired)
        precondition(MonitoringState.stale.badge(count: 3) == "—" && MonitoringState.connected.badge(count: 100) == "99+")
        precondition(ConnectionAddress.port("https://8090-test-instance.gputw.ai") == "8090")
        precondition(ConnectionAddress.port("http://fixture.invalid:8188/base") == "8188")
        precondition(try! ConnectionAddress.normalize(" https://8090-test-instance.gputw.ai/path?token=secret#fragment ") == "https://8090-test-instance.gputw.ai")
        print("PASS: checking, fresh, stale and sign-in states; service-port labels and safe review addresses")
        validationDefaults.set("http://fixture.invalid/base", forKey: "comfyEndpoint")
        defer { validationDefaults.removePersistentDomain(forName: validationSuite) }
        URLProtocol.registerClass(FixtureProtocol.self)
        defer { URLProtocol.unregisterClass(FixtureProtocol.self) }
        var server = ServerFixture()
        FixtureProtocol.handler = { server.handle($0) }
        let model = QueueViewModel()
        // Let the production initializer's first refresh finish before assertions/actions.
        for _ in 0..<200 {
            if model.lastUpdated != nil && !model.isLoading { break }
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(model.isConnected && !model.isLoading)
        precondition(model.monitoringState == .connected && model.queueBadge == "3")
        precondition(model.totalJobs == 3 && model.pending[0].title == "Disposable test")
        precondition(model.queueProgress?.percent == 30 && model.progressBridgeStatus == .available)
        precondition(server.paths.allSatisfy { $0.hasPrefix("/base/") })
        print("PASS: queue parsing, workflow title, base path, bounded history and matching progress")

        server.progressID = "unrelated-job"
        await model.refreshProgress()
        precondition(model.queueProgress == nil)
        server.progressStatus = 404
        await model.refreshProgress()
        precondition(model.progressBridgeStatus == .missing && model.isConnected)
        server.progressStatus = 200
        server.progressID = "running-original"
        server.historyStatus = 500
        await model.refresh(forceHistory: true)
        precondition(model.historyUnavailable && model.isConnected && model.progressBridgeStatus == .available)
        print("PASS: mismatched/missing progress, bridge retry and independent history failure")

        server.historyStatus = 200
        await model.moveToFront(model.pending[0])
        precondition(!model.actionIsError && server.pending == ["replacement-new", "pending-other"])
        precondition(server.mutations.map { $0.0 } == ["prompt", "queue"])
        precondition(server.mutations[1].1["delete"] as? [String] == ["pending-original"])
        precondition(model.canChangeServer)
        print("PASS: prioritize preserves graph/metadata, submits first, then deletes only original")

        for mode in [ServerFixture.Mode.originalStarts, .refuseDelete, .offlineAfterSubmit, .stalePending] {
            server = ServerFixture()
            await model.refresh(forceHistory: true)
            let job = model.pending[0]
            server.mode = mode
            await model.moveToFront(job)
            precondition(model.canChangeServer)
            switch mode {
            case .originalStarts:
                precondition(server.running.contains("pending-original"))
                precondition(!server.pending.contains("replacement-new") && !model.actionIsError)
                precondition(server.mutations.allSatisfy { $0.0 != "interrupt" })
                precondition(server.mutations.last?.1["delete"] as? [String] == ["replacement-new"])
                print("PASS: original starts during prioritize; replacement removed, running job untouched")
            case .refuseDelete:
                precondition(server.pending == ["pending-original", "pending-other"] && model.actionIsError)
                print("PASS: original deletion refused; replacement cleaned up and failure reported")
            case .offlineAfterSubmit:
                precondition(model.actionIsError && !model.isConnected)
                precondition(model.actionMessage?.contains("pending-") == true && model.actionMessage?.contains("replacem") == true)
                precondition(server.mutations.count == 1)
                print("PASS: connection lost after submit; both IDs reported without blind deletion")
            case .stalePending:
                precondition(model.actionIsError && server.mutations.isEmpty)
                print("PASS: stale waiting job rejected without submission")
            default: break
            }
        }

        server = ServerFixture()
        await model.refresh(forceHistory: true)
        await model.stopRunning(model.running[0])
        precondition(!model.actionIsError && server.running.isEmpty)
        precondition(server.pending == ["pending-original", "pending-other"])
        precondition(server.mutations.count == 1 && server.mutations[0].0 == "interrupt")
        precondition(server.mutations[0].1["prompt_id"] as? String == "running-original")
        print("PASS: targeted stop leaves waiting jobs intact")

        server = ServerFixture()
        await model.refresh(forceHistory: true)
        let stale = model.running[0]
        server.mode = .staleStop
        await model.stopRunning(stale)
        precondition(model.actionIsError && server.mutations.isEmpty)
        print("PASS: stale running job rejected without interruption")

        server = ServerFixture()
        server.running = []; server.pending = []
        await model.refresh(forceHistory: true)
        precondition(model.isConnected && model.totalJobs == 0 && model.queueProgress == nil)
        precondition(model.queueBadge == "0", "Only a healthy empty queue should display zero")
        server.queueBody = ["login_required": true]
        await model.refresh()
        precondition(!model.isConnected, "Unrelated JSON must not be accepted as an empty ComfyUI queue")
        precondition(model.queueBadge == "—")
        server.queueBody = ["queue_running": [[1, 42]], "queue_pending": []]
        await model.refresh()
        precondition(model.queueBadge == "—", "Malformed jobs must not silently become an empty queue")
        server.queueBody = nil
        server.queueStatus = 503
        await model.refresh()
        precondition(!model.isConnected && model.totalJobs == 0 && model.errorMessage != nil)
        precondition(model.monitoringState == .disconnected && model.queueBadge == "—")
        for code in [401, 403] {
            server.queueStatus = code
            await model.refresh()
            precondition(model.monitoringState == .signInRequired && model.queueBadge == "!")
        }
        server.queueStatus = 200
        await model.refresh()
        precondition(model.monitoringState == .connected && model.queueBadge == "0")

        let originalEndpoint = model.endpoint
        let originalSavedEndpoint = validationDefaults.string(forKey: "comfyEndpoint")
        let originalProfiles = model.profiles
        server.historyBody = Dictionary(uniqueKeysWithValues: (0..<5).map { index in
            let timestamp = now.addingTimeInterval(-Double(90_000 + index)).timeIntervalSince1970 * 1000
            let status: [String: Any] = ["completed": true, "status_str": "success", "messages": [["execution_success", ["timestamp": timestamp]]]]
            return ("success-\(index)", ["prompt": server.row("success-\(index)"), "status": status] as [String: Any])
        })
        server.historyBody["interrupted"] = ["prompt": server.row("interrupted"), "status": ["completed": true, "status_str": "error", "messages": [["execution_interrupted", ["timestamp": now.timeIntervalSince1970 * 1000]]]]]
        server.paths = []; server.mutations = []
        let candidate = "http://fixture.invalid:8090/candidate"
        let inspection = try! await ConnectionInspector.inspect(candidate)
        precondition(inspection.endpoint == candidate && inspection.isIdle && inspection.historyAvailable)
        precondition(inspection.completed.map(\.id) == ["success-0", "success-1", "success-2"])
        precondition(inspection.failures.first?.id == "interrupted")
        precondition(server.paths == ["/candidate/queue", "/candidate/history"] && server.mutations.isEmpty)
        precondition(model.endpoint == originalEndpoint && model.profiles == originalProfiles && model.queueBadge == "0")
        precondition(validationDefaults.string(forKey: "comfyEndpoint") == originalSavedEndpoint)
        server.historyStatus = 503
        let unavailable = try! await ConnectionInspector.inspect(candidate)
        precondition(!unavailable.historyAvailable && unavailable.completed.isEmpty)
        let review = ConnectionReviewModel()
        await review.inspect(candidate)
        precondition(review.inspection != nil && !review.checking)
        let cancelled = Task { await review.inspect("http://fixture.invalid/cancelled") }
        cancelled.cancel()
        await cancelled.value
        precondition(review.inspection?.endpoint == candidate && !review.checking)
        precondition(!server.paths.contains("/cancelled/queue"), "A cancelled review must not replace a newer card or send a request")
        review.cancel()
        precondition(review.inspection == nil && !review.checking)
        server.queueStatus = 401
        await review.inspect(candidate)
        precondition(review.inspection == nil && review.error != nil && !review.checking)
        precondition(model.endpoint == originalEndpoint && model.profiles == originalProfiles && server.mutations.isEmpty)
        print("PASS: read-only candidate review, latest three successes, interruption, unavailable history, cancellation and authentication failure")
        await model.connect(to: "file:///invalid")
        precondition(!model.isConnected && model.errorMessage != nil)
        precondition(model.saveProfile(name: "GPUtw fixture", address: "https://8080-test-instance.gputw.ai/handoff?token=do-not-save#secret"))
        precondition(model.profiles.last?.endpoint == "https://8080-test-instance.gputw.ai")
        let saved = String(data: validationDefaults.data(forKey: "serverProfiles")!, encoding: .utf8)!
        precondition(!saved.contains("do-not-save") && !saved.contains("secret"))
        print("PASS: unrelated JSON rejected and GPUtw handoff credentials excluded from saved profiles")
        print("PASS: connected idle, HTTP disconnection and invalid endpoint states")
        print("Network/action regression checks passed (intercepted HTTP; no live generation).")
    }
}
