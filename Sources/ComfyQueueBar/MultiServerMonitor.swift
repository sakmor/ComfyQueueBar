import Foundation

/// A queue becoming empty means capacity is available, not that its jobs succeeded.
struct MonitoredServer: Identifiable {
    var id: String { endpoint }
    let endpoint: String
    var name: String
    var state: MonitoringState = .checking
    var runningCount = 0
    var pendingCount = 0
    var currentJobTitle: String?
    var checkedAt: Date?
    var becameAvailableAt: Date?
    var error: String?
    var observedWork = false

    var isAvailable: Bool { state == .connected && runningCount == 0 && pendingCount == 0 }
    var statusLabel: String {
        guard state == .connected else { return state.label }
        if runningCount > 0 { return L10n.text("Rendering") }
        return pendingCount > 0 ? L10n.text("Waiting to run") : L10n.text("Available")
    }

    /// Keep an observed busy period through outages; an outage itself never frees capacity.
    @discardableResult
    mutating func receive(_ inspection: ConnectionInspection) -> Bool {
        runningCount = inspection.running.count
        pendingCount = inspection.pending.count
        currentJobTitle = inspection.running.first?.title
        checkedAt = inspection.checkedAt
        state = .connected
        error = nil
        if runningCount + pendingCount > 0 {
            observedWork = true
            becameAvailableAt = nil
            return false
        }
        guard observedWork else { return false }
        observedWork = false
        becameAvailableAt = inspection.checkedAt
        return true
    }

    @discardableResult
    mutating func fail(_ failure: Error) -> Bool {
        let wasConnected = state == .connected || state == .stale
        state = MonitoringState.requiresSignIn(failure) ? .signInRequired : .disconnected
        error = failure.localizedDescription
        return wasConnected
    }

    mutating func expire(now: Date) {
        if state == .connected, checkedAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
            state = .stale
        }
    }
}

/// Each endpoint has its own in-flight request. A slow or broken server cannot
/// delay another server, and removing/re-adding one invalidates its old response.
@MainActor
final class MultiServerMonitor {
    typealias Inspection = (String) async throws -> ConnectionInspection
    private let inspect: Inspection
    private var servers: [String: MonitoredServer] = [:]
    private var order: [String] = []
    private var polls: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    var onUpdate: (([MonitoredServer]) -> Void)?
    var onAvailable: ((MonitoredServer) -> Void)?
    var onDisconnected: ((MonitoredServer) -> Void)?

    init(inspect: Inspection? = nil) {
        self.inspect = inspect ?? { try await ConnectionInspector.inspectQueue($0, timeout: 8) }
    }

    static func key(_ endpoint: String) -> String {
        (try? ConnectionAddress.normalize(endpoint)) ?? endpoint
    }

    func configure(profiles: [ServerProfile]) {
        let targets = profiles.map { (Self.key($0.endpoint), $0.name) }
        let retained = Set(targets.map(\.0))
        for endpoint in Array(servers.keys) where !retained.contains(endpoint) {
            polls.removeValue(forKey: endpoint)?.task.cancel()
            servers.removeValue(forKey: endpoint)
        }
        order = []
        for (endpoint, name) in targets where !order.contains(endpoint) {
            order.append(endpoint)
            if servers[endpoint] == nil { servers[endpoint] = MonitoredServer(endpoint: endpoint, name: name) }
            else { servers[endpoint]?.name = name }
        }
        publish()
    }

    func refresh() {
        for endpoint in order where polls[endpoint] == nil {
            let token = UUID()
            let inspect = self.inspect
            let task = Task { @MainActor [weak self] in
                let outcome: Result<ConnectionInspection, Error>
                do { outcome = .success(try await inspect(endpoint)) }
                catch { outcome = .failure(error) }
                guard !Task.isCancelled, let self, self.polls[endpoint]?.token == token,
                      var server = self.servers[endpoint] else { return }
                self.polls.removeValue(forKey: endpoint)
                switch outcome {
                case .success(let inspection):
                    let becameAvailable = server.receive(inspection)
                    self.servers[endpoint] = server
                    if becameAvailable { self.onAvailable?(server) }
                case .failure(let error):
                    let disconnected = server.fail(error)
                    self.servers[endpoint] = server
                    if disconnected { self.onDisconnected?(server) }
                }
                self.publish()
            }
            polls[endpoint] = (token, task)
        }
    }

    func publish(now: Date = Date()) {
        for endpoint in order { servers[endpoint]?.expire(now: now) }
        onUpdate?(order.compactMap { servers[$0] })
    }

    func clearGPUTWAuthentication() {
        for endpoint in order where URL(string: endpoint).flatMap({ GPUTWAddress.serviceOrigin($0) }) != nil {
            polls.removeValue(forKey: endpoint)?.task.cancel()
            _ = servers[endpoint]?.fail(GPUTWError.signInRequired)
        }
        publish()
    }

    func stop() {
        for poll in polls.values { poll.task.cancel() }
        polls.removeAll()
    }

    deinit { for poll in polls.values { poll.task.cancel() } }
}
