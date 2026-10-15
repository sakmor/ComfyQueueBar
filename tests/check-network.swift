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
    var historyDetails: [String: [String: Any]] = [:]
    var historyDetailsStatus = 200
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
        if let historyIndex = url.pathComponents.lastIndex(of: "history"), historyIndex + 1 < url.pathComponents.count {
            let promptID = url.pathComponents[historyIndex + 1]
            return (historyDetailsStatus, historyDetails[promptID].map { [promptID: $0] } ?? [:])
        }
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
        await checkMultiServerMonitoring()
        let now = Date()
        precondition(QueueViewModel.connectionRetryInterval == 4)
        precondition(MonitoringState.resolve(connected: false, loading: true, needsSignIn: false, lastUpdated: nil, hasError: false, now: now) == .checking)
        precondition(MonitoringState.resolve(connected: false, loading: true, needsSignIn: false, lastUpdated: nil, hasError: true, now: now) == .disconnected)
        precondition(MonitoringState.resolve(connected: true, loading: true, needsSignIn: false, lastUpdated: now.addingTimeInterval(-29), hasError: false, now: now) == .connected)
        precondition(MonitoringState.resolve(connected: true, loading: true, needsSignIn: false, lastUpdated: now.addingTimeInterval(-30), hasError: false, now: now) == .stale)
        precondition(MonitoringState.resolve(connected: false, loading: true, needsSignIn: true, lastUpdated: now, hasError: true, now: now) == .signInRequired)
        precondition(MonitoringState.stale.badge(count: 3) == "—" && MonitoringState.connected.badge(count: 100) == "99+")
        precondition(ConnectionAddress.port("https://8090-test-instance.gputw.ai") == "8090")
        precondition(ConnectionAddress.port("http://fixture.invalid:8188/base") == "8188")
        precondition(try! ConnectionAddress.normalize(" https://8090-test-instance.gputw.ai/path?token=secret#fragment ") == "https://8090-test-instance.gputw.ai")
        precondition(GPUTWAddress.pairedServiceOrigin(URL(string: "https://8080-test-instance.gputw.ai/path")!)?.absoluteString == "https://8090-test-instance.gputw.ai")
        precondition(GPUTWAddress.pairedServiceOrigin(URL(string: "https://8090-test-instance.gputw.ai")!)?.absoluteString == "https://8080-test-instance.gputw.ai")
        precondition(GPUTWAddress.pairedServiceOrigin(URL(string: "https://8188-test-instance.gputw.ai")!) == nil)
        precondition(PairedPortIssue.classify(QueueError.serverStatus(404, nil)) == .portNotEnabled)
        precondition(PairedPortIssue.classify(QueueError.serverStatus(401, nil)) == .signInRequired)
        precondition(PairedPortIssue.classify(URLError(.cannotConnectToHost)) == .unavailable)
        print("PASS: four-second connection retries; checking, fresh, stale and sign-in states; service-port labels and safe review addresses")
        validationDefaults.set("http://fixture.invalid/base", forKey: "comfyEndpoint")
        validationDefaults.set(true, forKey: "agentIntegrationEnabled")
        defer { validationDefaults.removePersistentDomain(forName: validationSuite) }
        URLProtocol.registerClass(FixtureProtocol.self)
        defer { URLProtocol.unregisterClass(FixtureProtocol.self) }
        var server = ServerFixture()
        FixtureProtocol.handler = { server.handle($0) }
        let model = QueueViewModel(serverMonitor: MultiServerMonitor(inspect: { endpoint in
            guard URL(string: endpoint)?.host == "fixture.invalid" else { throw QueueError.invalidEndpoint }
            return try await ConnectionInspector.inspectQueue(endpoint)
        }))
        // Let the production initializer's first refresh finish before assertions/actions.
        for _ in 0..<200 {
            if model.lastUpdated != nil && !model.isLoading { break }
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
        for _ in 0..<200 {
            if model.progressBridgeStatus == .available || model.progressBridgeStatus == .missing { break }
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(model.isConnected && !model.isLoading)
        precondition(model.monitoringState == .connected && model.queueBadge == L10n.text("Queue %@", "3"))
        precondition(model.totalJobs == 3 && model.pending[0].title == "Disposable test")
        precondition(model.queueProgress?.percent == 30 && model.progressBridgeStatus == .available)
        precondition(server.paths.allSatisfy { $0.hasPrefix("/base/") })
        print("PASS: queue parsing, workflow title, base path, bounded history and matching progress")
        precondition(model.profiles.contains { MultiServerMonitor.key($0.endpoint) == MultiServerMonitor.key(model.endpoint) },
            "The legacy current address must become a persistent monitored server before selection changes")

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
        for _ in 0..<200 {
            if model.historyUnavailable && model.progressBridgeStatus == .available { break }
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(model.historyUnavailable && model.isConnected && model.progressBridgeStatus == .available)
        print("PASS: mismatched/missing progress, bridge retry and independent history failure")

        let acceptancePromptID = "three-little-pigs-prompt"
        let acceptanceSubscriptionID = UUID().uuidString
        let agentRoot = AgentBridge.defaultRoot
        let commandID = UUID().uuidString
        let command = AgentCommand(request_id: commandID, action: "subscribe", subscription_id: acceptanceSubscriptionID,
            endpoint: model.endpoint, prompt_ids: [acceptancePromptID], label: "三隻小豬")
        try! JSONEncoder().encode(command).write(to: agentRoot.appendingPathComponent("commands/\(commandID).json"), options: .atomic)
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: agentRoot.appendingPathComponent("responses/\(commandID).json").path) { break }
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(FileManager.default.fileExists(atPath: agentRoot.appendingPathComponent("responses/\(commandID).json").path), "agent subscription accepted")
        server.historyDetails[acceptancePromptID] = [
            "status": ["completed": true, "status_str": "success", "messages": [["execution_success", ["timestamp": Date().timeIntervalSince1970 * 1000]]]],
            "outputs": ["video": [["filename": "three-little-pigs.mp4", "subfolder": "", "type": "output"]]]
        ]
        server.historyStatus = 500
        server.running = []; server.pending = []
        await model.refresh(forceHistory: true)
        for _ in 0..<300 {
            let stateData = try? Data(contentsOf: agentRoot.appendingPathComponent("subscriptions.json"))
            let state = stateData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let subscription = state?[acceptanceSubscriptionID] as? [String: Any]
            let results = subscription?["results"] as? [String: Any]
            if (results?[acceptancePromptID] as? [String: Any])?["status"] as? String == "completed" { break }
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
        let state = try! JSONSerialization.jsonObject(with: Data(contentsOf: agentRoot.appendingPathComponent("subscriptions.json"))) as! [String: Any]
        let subscription = state[acceptanceSubscriptionID] as! [String: Any]
        let results = subscription["results"] as! [String: Any]
        let pigResult = results[acceptancePromptID] as! [String: Any]
        precondition(pigResult["status"] as? String == "completed", "per-ID history recovers success even when bulk history fails")
        precondition(pigResult["outputs"].debugDescription.contains("three-little-pigs.mp4"))
        precondition(server.paths.contains("/base/history/\(acceptancePromptID)"))
        precondition(model.historyUnavailable, "bulk history failure remains accurately visible")
        print("PASS: 三隻小豬 acceptance — targeted history reconciles success while bulk history is unavailable")

        server.historyStatus = 200
        server.running = ["running-original"]
        server.pending = ["pending-original", "pending-other"]
        await model.refresh()
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
        precondition(model.queueBadge == L10n.text("Queue %@", "0"), "Only a healthy empty queue should display zero")
        server.queueBody = ["login_required": true]
        await model.refresh()
        precondition(!model.isConnected, "Unrelated JSON must not be accepted as an empty ComfyUI queue")
        precondition(model.queueBadge == L10n.text("Queue %@", "—"))
        server.queueBody = ["queue_running": [[1, 42]], "queue_pending": []]
        await model.refresh()
        precondition(model.queueBadge == L10n.text("Queue %@", "—"), "Malformed jobs must not silently become an empty queue")
        server.queueBody = nil
        server.queueStatus = 503
        await model.refresh()
        precondition(!model.isConnected && model.totalJobs == 0 && model.errorMessage != nil)
        precondition(model.monitoringState == .disconnected && model.queueBadge == L10n.text("Queue %@", "—"))
        for code in [401, 403] {
            server.queueStatus = code
            await model.refresh()
            precondition(model.monitoringState == .signInRequired && model.queueBadge == L10n.text("Queue %@", "!"))
        }
        server.queueStatus = 200
        await model.refresh()
        precondition(model.monitoringState == .connected && model.queueBadge == L10n.text("Queue %@", "0"))

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
        precondition(model.endpoint == originalEndpoint && model.profiles == originalProfiles && model.queueBadge == L10n.text("Queue %@", "0"))
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
        let previousActionMessage = model.actionMessage
        let previousActionIsError = model.actionIsError
        precondition(!model.saveProfile(name: "Invalid", address: "192.168.1.140"))
        precondition(model.connectionMessage != nil && model.connectionMessageIsError)
        precondition(model.actionMessage == previousActionMessage && model.actionIsError == previousActionIsError,
            "Address validation must not leak into queue-action feedback")
        precondition(model.saveProfile(name: "Generic fixture", address: "http://fixture.invalid/base?token=do-not-save#fragment"))
        precondition(model.profiles.filter { $0.endpoint == "http://fixture.invalid/base" }.count == 1,
            "generic profile addresses use one canonical origin/path")
        precondition(model.saveProfile(name: "Generic renamed", address: "http://fixture.invalid/base///?another=secret"))
        precondition(model.profiles.filter { $0.endpoint == "http://fixture.invalid/base" }.count == 1
            && model.profiles.first(where: { $0.endpoint == "http://fixture.invalid/base" })?.name == "Generic renamed",
            "canonical profile matching updates an existing entry")
        precondition(model.saveProfile(name: "GPUtw fixture", address: "https://8080-test-instance.gputw.ai/handoff?token=do-not-save#secret"))
        precondition(model.connectionMessage == L10n.text("Address saved") && !model.connectionMessageIsError)
        precondition(model.profiles.last?.endpoint == "https://8080-test-instance.gputw.ai")
        let saved = String(data: validationDefaults.data(forKey: "serverProfiles")!, encoding: .utf8)!
        precondition(!saved.contains("do-not-save") && !saved.contains("secret"))
        server.queueStatus = 200
        await model.connect(to: originalEndpoint)
        precondition(model.isConnected && model.connectionMessage == nil && !model.connectionMessageIsError,
            "A confirmed connection must clear stale address feedback")
        print("PASS: unrelated JSON rejected and GPUtw handoff credentials excluded from saved profiles")
        print("PASS: connected idle, HTTP disconnection and invalid endpoint states")
        for profile in model.profiles where URL(string: profile.endpoint)?.host != "fixture.invalid" {
            model.deleteProfile(profile.id)
        }
        let firstMonitoredEndpoint = model.endpoint
        let otherMonitoredEndpoint = "http://fixture.invalid/another-server"
        let beforeSelection = Set(model.monitoredServers.map(\.endpoint))
        await model.connect(to: otherMonitoredEndpoint)
        precondition(model.profiles.contains { $0.endpoint == otherMonitoredEndpoint })
        precondition(Set(model.monitoredServers.map(\.endpoint)) == beforeSelection.union([otherMonitoredEndpoint]),
            "Selecting another server must retain every existing monitor")
        await model.connect(to: firstMonitoredEndpoint)
        precondition(Set(model.monitoredServers.map(\.endpoint)) == beforeSelection.union([otherMonitoredEndpoint]))
        let retained = try! JSONDecoder().decode([ServerProfile].self, from: validationDefaults.data(forKey: "serverProfiles")!)
        precondition(retained.contains { $0.endpoint == firstMonitoredEndpoint } && retained.contains { $0.endpoint == otherMonitoredEndpoint },
            "Both monitors must survive app restart")
        let selectedProfile = model.profiles.first { $0.endpoint == firstMonitoredEndpoint }!
        model.deleteProfile(selectedProfile.id)
        precondition(!model.monitoredServers.contains { $0.endpoint == firstMonitoredEndpoint },
            "Explicit removal must stop the selected monitor without silently re-adding it")
        precondition(model.endpoint != firstMonitoredEndpoint && model.profiles.contains { $0.endpoint == model.endpoint })
        for profile in model.profiles { model.deleteProfile(profile.id) }
        precondition(model.monitoredServers.isEmpty && model.endpoint.isEmpty && model.running.isEmpty && model.pending.isEmpty)
        await model.refresh()
        precondition(model.monitoredServers.isEmpty, "Refreshing after last removal must not recreate a monitor")
        print("PASS: persistent legacy/current monitors, selection isolation, restart persistence, explicit selected removal and last-server removal")
        print("Network/action regression checks passed (intercepted HTTP; no live generation).")
    }
}
