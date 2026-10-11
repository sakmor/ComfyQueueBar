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
        receive(running: inspection.running, pending: inspection.pending, checkedAt: inspection.checkedAt)
    }

    @discardableResult
    mutating func receive(running: [QueueJob], pending: [QueueJob], checkedAt: Date) -> Bool {
        runningCount = running.count
        pendingCount = pending.count
        currentJobTitle = running.first?.title
        self.checkedAt = checkedAt
        state = .connected
        error = nil
        if runningCount + pendingCount > 0 {
            observedWork = true
            becameAvailableAt = nil
            return false
        }
        guard observedWork else { return false }
        observedWork = false
        becameAvailableAt = checkedAt
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

/// How often background servers are polled. The selected server is not polled
/// here at all: its detailed queue refresh feeds results in through `record`.
struct FleetPollPolicy {
    /// Interval between successful polls of a server that is not selected.
    var backgroundInterval: TimeInterval = 12
    /// First retry delay after a failure; doubles per consecutive failure.
    var retryBase: TimeInterval = 4
    var retryMax: TimeInterval = 60
    /// Minimum time between two disconnection notices for the same server,
    /// so a flapping connection cannot flood Notification Center.
    var disconnectNoticeCooldown: TimeInterval = 300

    /// Poll on every tick and notify on every outage (used by regression fixtures).
    static let immediate = FleetPollPolicy(backgroundInterval: 0, retryBase: 0, retryMax: 0, disconnectNoticeCooldown: 0)

    func delay(consecutiveFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return backgroundInterval }
        return min(retryBase * pow(2, Double(min(failures, 16) - 1)), retryMax)
    }
}

/// Each endpoint has its own in-flight request. A slow or broken server cannot
/// delay another server, and removing/re-adding one invalidates its old response.
@MainActor
final class MultiServerMonitor {
    typealias Inspection = (String) async throws -> ConnectionInspection
    private let inspect: Inspection
    private let policy: FleetPollPolicy
    private let clock: () -> Date
    private var servers: [String: MonitoredServer] = [:]
    private var order: [String] = []
    private var polls: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    private var nextPollAt: [String: Date] = [:]
    private var failures: [String: Int] = [:]
    private var lastDisconnectNotice: [String: Date] = [:]
    /// The selected server, refreshed by the detailed queue view instead of this monitor.
    private(set) var focusedEndpoint: String?
    var onUpdate: (([MonitoredServer]) -> Void)?
    var onAvailable: ((MonitoredServer) -> Void)?
    var onDisconnected: ((MonitoredServer) -> Void)?

    init(inspect: Inspection? = nil, policy: FleetPollPolicy = FleetPollPolicy(), clock: @escaping () -> Date = { Date() }) {
        self.inspect = inspect ?? { try await ConnectionInspector.inspectQueue($0, timeout: 8) }
        self.policy = policy
        self.clock = clock
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
            nextPollAt.removeValue(forKey: endpoint)
            failures.removeValue(forKey: endpoint)
            lastDisconnectNotice.removeValue(forKey: endpoint)
        }
        order = []
        for (endpoint, name) in targets where !order.contains(endpoint) {
            order.append(endpoint)
            if servers[endpoint] == nil { servers[endpoint] = MonitoredServer(endpoint: endpoint, name: name) }
            else { servers[endpoint]?.name = name }
        }
        publish()
    }

    /// Stop polling `endpoint` here; the caller reports its results through `record`.
    /// Pass nil to return every server to background polling.
    func focus(_ endpoint: String?) {
        let key = endpoint.map(Self.key)
        guard key != focusedEndpoint else { return }
        if let previous = focusedEndpoint { nextPollAt[previous] = nil } // Poll promptly once unfocused.
        focusedEndpoint = key
        if let key { polls.removeValue(forKey: key)?.task.cancel() }
    }

    /// Poll every background server whose schedule is due. `force` ignores the
    /// schedule (manual refresh) but still never overlaps an in-flight request.
    func refresh(force: Bool = false) {
        let now = clock()
        for endpoint in order where polls[endpoint] == nil && endpoint != focusedEndpoint {
            if !force, let due = nextPollAt[endpoint], due > now { continue }
            let token = UUID()
            let inspect = self.inspect
            let task = Task { @MainActor [weak self] in
                let outcome: Result<ConnectionInspection, Error>
                do { outcome = .success(try await inspect(endpoint)) }
                catch { outcome = .failure(error) }
                guard !Task.isCancelled, let self, self.polls[endpoint]?.token == token else { return }
                self.polls.removeValue(forKey: endpoint)
                switch outcome {
                case .success(let inspection):
                    self.apply(endpoint) { $0.receive(inspection) }
                case .failure(let error):
                    self.applyFailure(endpoint, error)
                }
            }
            polls[endpoint] = (token, task)
        }
    }

    /// Feed the selected server's detailed queue refresh into the fleet without a second request.
    func record(_ endpoint: String, running: [QueueJob], pending: [QueueJob], checkedAt: Date) {
        let key = Self.key(endpoint)
        guard key == focusedEndpoint else { return }
        apply(key) { $0.receive(running: running, pending: pending, checkedAt: checkedAt) }
    }

    func recordFailure(_ endpoint: String, _ error: Error) {
        let key = Self.key(endpoint)
        guard key == focusedEndpoint else { return }
        applyFailure(key, error)
    }

    private func apply(_ endpoint: String, _ update: (inout MonitoredServer) -> Bool) {
        guard var server = servers[endpoint] else { return }
        let becameAvailable = update(&server)
        servers[endpoint] = server
        failures[endpoint] = 0
        nextPollAt[endpoint] = clock().addingTimeInterval(policy.delay(consecutiveFailures: 0))
        if becameAvailable { onAvailable?(server) }
        publish()
    }

    private func applyFailure(_ endpoint: String, _ error: Error) {
        guard var server = servers[endpoint] else { return }
        let disconnected = server.fail(error)
        servers[endpoint] = server
        let count = (failures[endpoint] ?? 0) + 1
        failures[endpoint] = count
        let now = clock()
        nextPollAt[endpoint] = now.addingTimeInterval(policy.delay(consecutiveFailures: count))
        if disconnected {
            let quiet = lastDisconnectNotice[endpoint].map { now.timeIntervalSince($0) < policy.disconnectNoticeCooldown } ?? false
            if !quiet {
                lastDisconnectNotice[endpoint] = now
                onDisconnected?(server)
            }
        }
        publish()
    }

    /// Seconds until `endpoint` is next polled in the background (nil when due now or unknown).
    func secondsUntilNextPoll(_ endpoint: String) -> TimeInterval? {
        guard let due = nextPollAt[Self.key(endpoint)] else { return nil }
        let remaining = due.timeIntervalSince(clock())
        return remaining > 0 ? remaining : nil
    }

    func publish(now: Date? = nil) {
        let now = now ?? clock()
        for endpoint in order { servers[endpoint]?.expire(now: now) }
        onUpdate?(order.compactMap { servers[$0] })
    }

    func clearGPUTWAuthentication() {
        for endpoint in order where URL(string: endpoint).flatMap({ GPUTWAddress.serviceOrigin($0) }) != nil {
            polls.removeValue(forKey: endpoint)?.task.cancel()
            _ = servers[endpoint]?.fail(GPUTWError.signInRequired)
            nextPollAt[endpoint] = nil // Retry promptly after the user signs in again.
        }
        publish()
    }

    func stop() {
        for poll in polls.values { poll.task.cancel() }
        polls.removeAll()
    }

    deinit { for poll in polls.values { poll.task.cancel() } }
}
