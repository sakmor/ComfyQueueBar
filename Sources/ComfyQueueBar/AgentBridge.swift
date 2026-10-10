import Foundation

// Same-user file IPC. Only the app writes subscriptions; MCP clients submit atomic commands.
// No listening port, shell execution, credentials, or workflow graphs are exposed.
struct AgentJobResult: Codable, Equatable {
    var status: String
    var outputs: [[String: String]] = []
    var error: String? = nil
    var terminal: Bool { ["completed", "failed", "interrupted"].contains(status) }
}

struct AgentEvent: Codable, Equatable {
    var id: String
    var kind: String
    var created_at: Double
    var prompt_id: String?
    var monitoring_status: String?
}

struct AgentSubscription: Codable, Equatable {
    var subscription_id: String
    var endpoint: String
    var prompt_ids: [String]
    var label: String
    var created_at: Double
    var cancelled = false
    var results: [String: AgentJobResult] = [:]
    var events: [AgentEvent] = []
    var acknowledged: [String] = []
    var monitoring_status: String? = nil
    var finished: Bool { prompt_ids.allSatisfy { results[$0]?.terminal == true } }
}

struct AgentCommand: Codable {
    var request_id: String
    var action: String
    var subscription_id: String
    var endpoint: String?
    var prompt_ids: [String]?
    var label: String?
    var event_ids: [String]?
}

final class AgentBridge {
    static let maxSubscriptionCount = 1000
    static let maxActiveSubscriptionCount = 100
    /// Completed/cancelled subscriptions remain durable until their events have
    /// been acknowledged and this retention period has elapsed.
    static let subscriptionRetention: TimeInterval = 30 * 24 * 60 * 60
    /// The adapter considers the app unavailable after 15 seconds. Keep a
    /// safety margin while avoiding a disk write on every one-second UI tick.
    static let snapshotHeartbeatInterval: TimeInterval = 10

    private struct SnapshotState: Equatable {
        let enabled: Bool
        let lastQueueUpdate: Double?
        let endpoint: String
        let connected: Bool
        let historyAvailable: Bool
        let running: [String]
        let pending: [String]
    }

    private struct Snapshot: Encodable {
        let enabled: Bool
        let heartbeat_at: Double
        let last_queue_update: Double?
        let endpoint: String
        let connected: Bool
        let history_available: Bool
        let running: [String]
        let pending: [String]
    }

    static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["COMFYQUEUEBAR_AGENT_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ComfyQueueBar/AgentBridge", isDirectory: true)
    }
    let root: URL
    private(set) var subscriptions: [String: AgentSubscription] = [:]
    private var historyCursor = 0
    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private var lastSnapshotState: SnapshotState?
    private var lastSnapshotWrite: Date?

    init(root: URL = AgentBridge.defaultRoot) throws {
        self.root = root
        encoder.outputFormatting = [.sortedKeys]
        for directory in [root, root.appendingPathComponent("commands"), root.appendingPathComponent("responses"), root.appendingPathComponent("rejected")] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        let state = root.appendingPathComponent("subscriptions.json")
        if fm.fileExists(atPath: state.path) {
            // A damaged store must not silently erase existing subscriptions.
            subscriptions = try JSONDecoder().decode([String: AgentSubscription].self, from: Data(contentsOf: state))
        }
    }

    private func write<T: Encodable>(_ value: T, to name: String) throws {
        let file = root.appendingPathComponent(name)
        try encoder.encode(value).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private func persist() throws { try write(subscriptions, to: "subscriptions.json") }
    private func validID(_ id: String) -> Bool { UUID(uuidString: id) != nil }
    private func validPrompt(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 200 && id.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0)
        }
    }

    /// Quarantine malformed regular command files so they are visible for
    /// diagnosis without allowing them to starve valid requests. Symlinks are
    /// unlinked instead of moved, so the bridge never follows or preserves a
    /// link supplied to the IPC directory.
    private func quarantineCommand(_ file: URL, reason: String) {
        guard let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]) else { return }
        if values.isSymbolicLink == true {
            try? fm.removeItem(at: file)
            return
        }
        guard values.isRegularFile == true else { return }
        let safeReason = reason.replacingOccurrences(of: "[^A-Za-z0-9-]", with: "-", options: .regularExpression)
        let destination = root.appendingPathComponent("rejected", isDirectory: true)
            .appendingPathComponent("\(safeReason)-\(UUID().uuidString).json")
        do { try fm.moveItem(at: file, to: destination) }
        catch { try? fm.removeItem(at: file) }
    }

    func processCommands(endpoint: String) throws {
        let directory = root.appendingPathComponent("commands")
        let listed = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var files: [URL] = []
        for file in listed {
            let requestID = file.deletingPathExtension().lastPathComponent
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            guard values.isSymbolicLink != true else {
                quarantineCommand(file, reason: "symlink")
                continue
            }
            guard values.isRegularFile == true else { continue }
            guard (values.fileSize ?? 0) <= 65536 else {
                quarantineCommand(file, reason: "oversized")
                continue
            }
            guard validID(requestID) else {
                quarantineCommand(file, reason: "invalid-request-id")
                continue
            }
            files.append(file)
        }
        for file in files.prefix(32) {
            let requestID = file.deletingPathExtension().lastPathComponent
            let responsePath = "responses/\(requestID).json"
            if fm.fileExists(atPath: root.appendingPathComponent(responsePath).path) {
                try fm.removeItem(at: file); continue
            }
            var response: [String: String]
            do {
                let command = try JSONDecoder().decode(AgentCommand.self, from: Data(contentsOf: file))
                guard command.request_id == requestID, validID(command.subscription_id) else { throw BridgeError.invalidCommand }
                let previous = subscriptions
                do {
                    try apply(command, endpoint: endpoint)
                    try persist() // Commit before acknowledging the command.
                } catch {
                    subscriptions = previous
                    throw error
                }
                response = ["status": "accepted", "subscription_id": command.subscription_id]
            } catch {
                response = ["status": "error", "error": String(describing: error)]
            }
            try write(response, to: responsePath)
            try fm.removeItem(at: file)
        }
        // IPC acknowledgments are temporary, unlike durable task events.
        for file in try fm.contentsOfDirectory(at: root.appendingPathComponent("responses"), includingPropertiesForKeys: [.contentModificationDateKey]) {
            if let date = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               Date().timeIntervalSince(date) > 86400 { try? fm.removeItem(at: file) }
        }
    }

    private func apply(_ command: AgentCommand, endpoint: String) throws {
        switch command.action {
        case "subscribe":
            guard command.endpoint == endpoint, let ids = command.prompt_ids, !ids.isEmpty, ids.count <= 100,
                  Set(ids).count == ids.count, ids.allSatisfy(validPrompt), (command.label?.utf8.count ?? 0) <= 500 else { throw BridgeError.invalidCommand }
            if let existing = subscriptions[command.subscription_id] {
                guard existing.endpoint == endpoint, existing.prompt_ids == ids, !existing.cancelled else { throw BridgeError.conflictingSubscription }
                return // Idempotent recovery if a response was lost.
            }
            pruneSubscriptions(now: Date().timeIntervalSince1970)
            guard subscriptions.count < Self.maxSubscriptionCount,
                  subscriptions.values.filter({ !$0.cancelled && !$0.finished }).count < Self.maxActiveSubscriptionCount else { throw BridgeError.capacityReached }
            subscriptions[command.subscription_id] = AgentSubscription(subscription_id: command.subscription_id,
                endpoint: endpoint, prompt_ids: ids, label: command.label ?? "", created_at: Date().timeIntervalSince1970)
        case "unsubscribe":
            guard var subscription = subscriptions[command.subscription_id] else { throw BridgeError.unknownSubscription }
            subscription.cancelled = true
            subscriptions[command.subscription_id] = subscription
        case "acknowledge":
            guard var subscription = subscriptions[command.subscription_id], let ids = command.event_ids,
                  ids.count <= 200, ids.allSatisfy({ id in subscription.events.contains { $0.id == id } }) else { throw BridgeError.invalidCommand }
            subscription.acknowledged = Array(Set(subscription.acknowledged).union(ids)).sorted()
            subscriptions[command.subscription_id] = subscription
        default: throw BridgeError.invalidCommand
        }
    }

    @discardableResult
    private func pruneSubscriptions(now: TimeInterval) -> Bool {
        let removable = subscriptions.values.filter { subscription in
            guard (subscription.cancelled || subscription.finished),
                  now - subscription.created_at >= Self.subscriptionRetention else { return false }
            let eventIDs = Set(subscription.events.map(\.id))
            return eventIDs.isSubset(of: Set(subscription.acknowledged))
        }.sorted {
            if $0.created_at != $1.created_at { return $0.created_at < $1.created_at }
            return $0.subscription_id < $1.subscription_id
        }
        guard !removable.isEmpty else { return false }
        for subscription in removable { subscriptions.removeValue(forKey: subscription.subscription_id) }
        return true
    }

    private func addEvent(_ kind: String, prompt: String? = nil, to subscription: inout AgentSubscription) {
        // Terminal events have deterministic IDs; monitoring events are transition based.
        let id = ["batch_finished", "job_failed"].contains(kind)
            ? subscription.subscription_id + ":" + kind + ":" + (prompt ?? "batch")
            : UUID().uuidString
        guard !subscription.events.contains(where: { $0.id == id }) else { return }
        subscription.events.append(AgentEvent(id: id, kind: kind, created_at: Date().timeIntervalSince1970, prompt_id: prompt, monitoring_status: kind == "monitoring_changed" ? subscription.monitoring_status : nil))
        // Keep every terminal event, bound monitoring transition noise.
        if subscription.events.count > 300,
           let index = subscription.events.firstIndex(where: { $0.kind == "monitoring_changed" }) {
            let removed = subscription.events.remove(at: index)
            subscription.acknowledged.removeAll { $0 == removed.id }
        }
    }

    func ingest(endpoint: String, results: [String: AgentJobResult]) throws {
        let previous = subscriptions
        for id in Array(subscriptions.keys) {
            guard var subscription = subscriptions[id], subscription.endpoint == endpoint, !subscription.cancelled else { continue }
            for prompt in subscription.prompt_ids where subscription.results[prompt]?.terminal != true {
                guard let result = results[prompt] else { continue }
                subscription.results[prompt] = result
                if ["failed", "interrupted"].contains(result.status) { addEvent("job_failed", prompt: prompt, to: &subscription) }
            }
            if subscription.finished { addEvent("batch_finished", to: &subscription) }
            subscriptions[id] = subscription
        }
        do { if subscriptions != previous { try persist() } } catch { subscriptions = previous; throw error }
    }

    func tick(endpoint: String, connected: Bool, historyAvailable: Bool, lastUpdated: Date?, running: [String], pending: [String]) throws {
        try processCommands(endpoint: endpoint)
        let previous = subscriptions
        _ = pruneSubscriptions(now: Date().timeIntervalSince1970)
        for id in Array(subscriptions.keys) {
            guard var subscription = subscriptions[id], !subscription.cancelled, !subscription.finished else { continue }
            let status = subscription.endpoint != endpoint ? "paused_server_changed" : !connected ? "disconnected" : !historyAvailable ? "history_unavailable" : "monitoring"
            if subscription.monitoring_status != status {
                subscription.monitoring_status = status
                if status != "monitoring" || previous[id]?.monitoring_status != nil { addEvent("monitoring_changed", to: &subscription) }
            }
            if subscription.endpoint == endpoint && connected {
                for prompt in subscription.prompt_ids where subscription.results[prompt]?.terminal != true {
                    subscription.results[prompt] = AgentJobResult(status: running.contains(prompt) ? "running" : pending.contains(prompt) ? "queued" : "unknown")
                }
            }
            subscriptions[id] = subscription
        }
        do { if subscriptions != previous { try persist() } } catch { subscriptions = previous; throw error }
        let now = Date()
        let state = SnapshotState(enabled: true, lastQueueUpdate: lastUpdated?.timeIntervalSince1970,
            endpoint: endpoint, connected: connected, historyAvailable: historyAvailable,
            running: running, pending: pending)
        if lastSnapshotState != state || lastSnapshotWrite.map({ now.timeIntervalSince($0) >= Self.snapshotHeartbeatInterval }) ?? true {
            try write(Snapshot(enabled: true, heartbeat_at: now.timeIntervalSince1970,
                last_queue_update: state.lastQueueUpdate, endpoint: endpoint, connected: connected,
                history_available: historyAvailable, running: running, pending: pending), to: "snapshot.json")
            lastSnapshotState = state
            lastSnapshotWrite = now
        }
    }

    func historyCandidates(endpoint: String, queued: Set<String>, limit: Int = 8) -> [String] {
        let ids = Set(subscriptions.values.filter { !$0.cancelled && !$0.finished && $0.endpoint == endpoint }
            .flatMap { subscription in subscription.prompt_ids.filter { subscription.results[$0]?.terminal != true && !queued.contains($0) } }).sorted()
        guard !ids.isEmpty else { return [] }
        let count = min(limit, ids.count)
        let result = (0..<count).map { ids[(historyCursor + $0) % ids.count] }
        historyCursor = (historyCursor + count) % ids.count
        return result
    }

    func stop() {
        struct Disabled: Encodable { let enabled = false; let heartbeat_at = Date().timeIntervalSince1970 }
        try? write(Disabled(), to: "snapshot.json")
        lastSnapshotState = nil
        lastSnapshotWrite = Date()
    }
    enum BridgeError: Error { case invalidCommand, unknownSubscription, conflictingSubscription, capacityReached }
}
