import Foundation

@main
struct AgentBridgeCheck {
    static let endpoint = "http://127.0.0.1:8188"
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func command(_ root: URL, _ action: String, _ sid: String, ids: [String]? = nil, events: [String]? = nil, source: String = endpoint, request: String = UUID().uuidString) throws -> String {
        let value = AgentCommand(request_id: request, action: action, subscription_id: sid, endpoint: source, prompt_ids: ids, label: "Test", event_ids: events)
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("commands/\(request).json"), options: .atomic)
        return request
    }
    static func response(_ root: URL, _ request: String) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("responses/\(request).json")))
    }
    static func test(_ root: URL) throws {
        var bridge = try AgentBridge(root: root)
        let sid = UUID().uuidString
        let request = try command(root, "subscribe", sid, ids: ["job-a", "job-b"])
        try bridge.tick(endpoint: endpoint, connected: true, historyAvailable: true, lastUpdated: Date(), running: ["job-a"], pending: ["job-b"])
        let accepted = try response(root, request)
        require(accepted["status"] == "accepted", "subscribe acknowledged")
        require(bridge.subscriptions[sid]?.results["job-a"]?.status == "running", "running state")
        require(bridge.subscriptions[sid]?.events.isEmpty == true, "no initial monitoring event spam")
        try bridge.ingest(endpoint: "http://other:8188", results: ["job-a": AgentJobResult(status: "completed")])
        require(bridge.subscriptions[sid]?.results["job-a"]?.status == "running", "server isolation")
        try bridge.tick(endpoint: endpoint, connected: true, historyAvailable: true, lastUpdated: Date(), running: [], pending: [])
        require(bridge.subscriptions[sid]?.results["job-a"]?.status == "unknown", "missing queue entry is not completion")
        try bridge.ingest(endpoint: endpoint, results: ["job-a": AgentJobResult(status: "failed", error: "GPU error")])
        require(bridge.subscriptions[sid]?.events.filter { $0.kind == "job_failed" }.count == 1, "early failure once")
        require(bridge.subscriptions[sid]?.finished == false, "batch unfinished with unknown remaining job")
        try bridge.ingest(endpoint: endpoint, results: ["job-a": AgentJobResult(status: "failed")])
        require(bridge.subscriptions[sid]?.events.count == 1, "terminal deduplication")
        bridge = try AgentBridge(root: root)
        require(bridge.subscriptions[sid]?.results["job-a"]?.error == "GPU error", "durable results across restart")
        try bridge.tick(endpoint: "http://other:8188", connected: true, historyAvailable: true, lastUpdated: Date(), running: [], pending: [])
        require(bridge.subscriptions[sid]?.monitoring_status == "paused_server_changed", "server switch pauses subscription")
        try bridge.tick(endpoint: "http://other:8188", connected: true, historyAvailable: true, lastUpdated: Date(), running: [], pending: [])
        require(bridge.subscriptions[sid]?.events.count == 2, "no repeated pause events")
        try bridge.ingest(endpoint: endpoint, results: ["job-b": AgentJobResult(status: "completed", outputs: [["filename": "clip.mp4", "url": "http://example/view"]])])
        require(bridge.subscriptions[sid]?.finished == true, "whole batch completion requires all explicit terminal results")
        require(bridge.subscriptions[sid]?.events.filter { $0.kind == "batch_finished" }.count == 1, "one batch event")
        try bridge.ingest(endpoint: endpoint, results: ["job-b": AgentJobResult(status: "completed")])
        require(bridge.subscriptions[sid]?.events.count == 3, "completion not repeated")
        let eventIDs = bridge.subscriptions[sid]!.events.map(\.id)
        _ = try command(root, "acknowledge", sid, events: eventIDs)
        try bridge.processCommands(endpoint: endpoint)
        bridge = try AgentBridge(root: root)
        require(Set(bridge.subscriptions[sid]!.acknowledged) == Set(eventIDs), "durable event acknowledgment")
        let bad = try command(root, "subscribe", UUID().uuidString, ids: ["../../secret"])
        try bridge.processCommands(endpoint: endpoint)
        let badResponse = try response(root, bad)
        require(badResponse["status"] == "error", "path traversal rejected")
        let conflict = try command(root, "subscribe", sid, ids: ["different"])
        try bridge.processCommands(endpoint: endpoint)
        let conflictResponse = try response(root, conflict)
        require(conflictResponse["status"] == "error", "conflicting subscription rejected")
        let wrongServer = try command(root, "subscribe", UUID().uuidString, ids: ["job"], source: "http://other:8188")
        try bridge.processCommands(endpoint: endpoint)
        let wrongServerResponse = try response(root, wrongServer)
        require(wrongServerResponse["status"] == "error", "wrong server registration rejected")
        let sid2 = UUID().uuidString
        let ids = (0..<20).map { "missing-\($0)" }
        let original = try command(root, "subscribe", sid2, ids: ids)
        try bridge.processCommands(endpoint: endpoint)
        _ = try command(root, "subscribe", sid2, ids: ids, request: original)
        try bridge.processCommands(endpoint: endpoint)
        require(bridge.subscriptions.count == 2, "replayed command idempotent")
        let candidates = (0..<3).flatMap { _ in bridge.historyCandidates(endpoint: endpoint, queued: [], limit: 8) }
        require(Set(candidates) == Set(ids), "targeted history lookup rotates beyond UI history")
        _ = try command(root, "unsubscribe", sid2)
        try bridge.processCommands(endpoint: endpoint)
        try bridge.ingest(endpoint: endpoint, results: ["missing-0": AgentJobResult(status: "interrupted")])
        require(bridge.subscriptions[sid2]?.events.isEmpty == true, "cancelled subscription gets no new events")
        bridge.stop()
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("snapshot.json"))) as! [String: Any]
        require(snapshot["enabled"] as? Bool == false, "disabled snapshot")
        try Data("broken".utf8).write(to: root.appendingPathComponent("subscriptions.json"))
        do { _ = try AgentBridge(root: root); require(false, "damaged store must fail") } catch { }
        print("Agent bridge lifecycle checks passed")
    }
    struct Fixture: Decodable {
        var endpoint: String?
        var connected: Bool?
        var history_available: Bool?
        var running: [String]?
        var pending: [String]?
        var results: [String: AgentJobResult]?
    }
    static func serve(_ root: URL) throws {
        let bridge = try AgentBridge(root: root)
        while true {
            let path = root.appendingPathComponent("fixture.json")
            let fixture = FileManager.default.fileExists(atPath: path.path)
                ? try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: path)) : Fixture()
            let source = fixture.endpoint ?? endpoint
            try bridge.tick(endpoint: source, connected: fixture.connected ?? true, historyAvailable: fixture.history_available ?? true,
                lastUpdated: Date(), running: fixture.running ?? [], pending: fixture.pending ?? [])
            if let results = fixture.results { try bridge.ingest(endpoint: source, results: results) }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--serve" {
            try serve(URL(fileURLWithPath: CommandLine.arguments[2])); return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try test(root)
    }
}
