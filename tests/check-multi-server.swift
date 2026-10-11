import Foundation

@MainActor
private final class FleetFixture {
    var counts: [String: (running: Int, pending: Int)] = [:]
    var failing = Set<String>()
    var slow = Set<String>()
    var waiting: [String: [CheckedContinuation<ConnectionInspection, Error>]] = [:]
    var calls: [String: Int] = [:]

    func snapshot(_ endpoint: String, running: Int = 0, pending: Int = 0) -> ConnectionInspection {
        func job(_ index: Int) -> QueueJob {
            QueueJob(id: "shared-id-\(index)", title: "Fixture clip", nodeCount: 0, queueNumber: index,
                position: index, prompt: [:], extraData: [:])
        }
        return ConnectionInspection(endpoint: endpoint, checkedAt: Date(), running: (0..<running).map(job),
            pending: (0..<pending).map(job), completed: [], failures: [], historyAvailable: false)
    }

    func inspect(_ endpoint: String) async throws -> ConnectionInspection {
        calls[endpoint, default: 0] += 1
        if slow.contains(endpoint) {
            return try await withCheckedThrowingContinuation { waiting[endpoint, default: []].append($0) }
        }
        if failing.contains(endpoint) { throw URLError(.cannotConnectToHost) }
        let count = counts[endpoint] ?? (0, 0)
        return snapshot(endpoint, running: count.running, pending: count.pending)
    }

    func release(_ endpoint: String, running: Int = 0) {
        let continuation = waiting[endpoint]!.removeFirst()
        continuation.resume(returning: snapshot(endpoint, running: running))
    }
}

@MainActor
private func fleetEventually(_ predicate: () -> Bool) async {
    for _ in 0..<200 {
        if predicate() { return }
        try! await Task.sleep(nanoseconds: 5_000_000)
    }
    preconditionFailure("Fleet fixture did not settle")
}

@MainActor
func checkMultiServerMonitoring() async {
    let a = "http://mac.fixture.invalid:8188/base"
    let b = "http://render.fixture.invalid:8188"
    let c = "http://slow.fixture.invalid:8188"
    let fixture = FleetFixture()
    fixture.counts[a] = (1, 2)
    fixture.counts[b] = (1, 0)
    fixture.slow = [c]
    let monitor = MultiServerMonitor(inspect: fixture.inspect)
    var snapshots: [MonitoredServer] = []
    var available: [String] = []
    var disconnected: [String] = []
    monitor.onUpdate = { snapshots = $0 }
    monitor.onAvailable = { available.append($0.endpoint) }
    monitor.onDisconnected = { disconnected.append($0.endpoint) }
    let profiles = [ServerProfile(name: "Mac", endpoint: a), ServerProfile(name: "Remote", endpoint: b),
        ServerProfile(name: "Slow", endpoint: c), ServerProfile(name: "Duplicate", endpoint: a + "/")]
    monitor.configure(profiles: profiles)
    monitor.refresh()
    await fleetEventually { snapshots.filter { $0.state == .connected }.count == 2 && fixture.waiting[c]?.count == 1 }
    precondition(snapshots.count == 3 && available.isEmpty)
    precondition(snapshots[0].runningCount == 1 && snapshots[0].pendingCount == 2)
    monitor.refresh()
    await fleetEventually { fixture.calls[a] == 2 && fixture.calls[b] == 2 }
    precondition(fixture.calls[c] == 1, "No overlapping requests to a slow endpoint")

    fixture.counts[b] = (0, 0)
    monitor.refresh()
    await fleetEventually { snapshots[1].isAvailable }
    precondition(available == [b] && snapshots[1].becameAvailableAt != nil && !snapshots[0].isAvailable)
    fixture.failing = [b]
    monitor.refresh()
    await fleetEventually { snapshots[1].state == .disconnected }
    precondition(!snapshots[1].isAvailable && available == [b] && disconnected == [b])
    monitor.refresh()
    await fleetEventually { fixture.calls[b] == 5 }
    precondition(disconnected == [b], "Only one disconnection event per outage")
    fixture.failing = []
    monitor.refresh()
    await fleetEventually { snapshots[1].isAvailable }
    precondition(available == [b], "Reconnect to the same idle period must not notify twice")

    fixture.counts[b] = (0, 2)
    monitor.refresh()
    await fleetEventually { snapshots[1].pendingCount == 2 }
    precondition(!snapshots[1].isAvailable && snapshots[1].statusLabel == L10n.text("Waiting to run"))
    fixture.failing = [b]
    monitor.refresh()
    await fleetEventually { snapshots[1].state == .disconnected }
    precondition(available == [b], "A failed read must never look like an empty queue")
    fixture.counts[b] = (0, 0)
    fixture.failing = []
    monitor.refresh()
    await fleetEventually { available.count == 2 }
    precondition(available == [b, b], "Busy state survives an outage until a fresh empty response")

    monitor.configure(profiles: [profiles[0], ServerProfile(name: "Renamed", endpoint: b)])
    precondition(snapshots.count == 2 && snapshots[1].name == "Renamed" && snapshots[1].isAvailable)
    monitor.configure(profiles: Array(profiles.prefix(3)))
    monitor.refresh()
    await fleetEventually { fixture.waiting[c]?.count == 2 }
    fixture.release(c, running: 1) // Old request ignores cancellation until its continuation resumes.
    await Task.yield()
    precondition(snapshots[2].state == .checking, "Removed endpoint's late response must be ignored after re-add")
    fixture.release(c, running: 1)
    await fleetEventually { snapshots[2].state == .connected }
    precondition(snapshots[2].runningCount == 1)

    monitor.publish(now: Date().addingTimeInterval(31))
    precondition(snapshots.allSatisfy { $0.state == .stale && !$0.isAvailable })
    monitor.stop()

    let gpu = "https://8080-test-instance.gputw.ai"
    let gpu2 = "https://8090-other-instance.gputw.ai"
    fixture.slow = [gpu, gpu2]
    monitor.configure(profiles: [profiles[0], ServerProfile(name: "GPU", endpoint: gpu),
        ServerProfile(name: "GPU 2", endpoint: gpu2)])
    monitor.refresh()
    await fleetEventually { fixture.waiting[gpu]?.count == 1 && fixture.waiting[gpu2]?.count == 1 && snapshots[0].state == .connected }
    monitor.clearGPUTWAuthentication()
    fixture.release(gpu)
    fixture.release(gpu2)
    await Task.yield()
    precondition(snapshots[0].state == .connected && snapshots[1].state == .signInRequired && snapshots[2].state == .signInRequired)
    precondition(!snapshots[1].isAvailable && !snapshots[2].isAvailable)
    monitor.stop()

    var baseline = MonitoredServer(endpoint: b, name: "Baseline")
    precondition(!baseline.receive(fixture.snapshot(b)) && baseline.isAvailable && baseline.becameAvailableAt == nil)
    precondition(baseline.fail(GPUTWError.signInRequired))
    precondition(baseline.state == .signInRequired && !baseline.isAvailable)
    print("PASS: fleet polling, slow-server isolation, endpoint deduplication, switching, idle transitions, outages, stale states, removal races and GPUtw session clearing")
}
