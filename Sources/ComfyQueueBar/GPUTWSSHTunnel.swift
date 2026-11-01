import AppKit
import Foundation

/// One optional, loopback-only SSH tunnel. SSH uses the user's existing keys and
/// known_hosts; it never asks for a password or changes host-key policy.
@MainActor
final class GPUTWSSHTunnel: ObservableObject {
    static let shared = GPUTWSSHTunnel()
    static let endpoint = "http://127.0.0.1:18774"
    private static let defaultsKey = "gputwSSHInstanceID"
    private static let protectionKey = "gputwSSHProtectLocalEndpoint"
    @Published var instanceID: String
    @Published private(set) var status = ""
    private var process: Process?
    private var retryTimer: Timer?

    init() {
        instanceID = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        if !instanceID.isEmpty { start() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopProcess() }
        }
    }

    static func normalizedID(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidate = value.hasPrefix("pod-") ? String(value.dropFirst(4)) : value
        guard let uuid = UUID(uuidString: candidate), uuid.uuidString.lowercased() == candidate else { return nil }
        return candidate
    }

    @discardableResult func connect() -> Bool {
        guard let id = Self.normalizedID(instanceID) else {
            status = L10n.text("Enter the full GPUtw instance ID.")
            return false
        }
        instanceID = id
        UserDefaults.standard.set(true, forKey: Self.protectionKey)
        UserDefaults.standard.set(id, forKey: Self.defaultsKey)
        stopProcess()
        start()
        return true
    }

    /// Never send queue actions to an unrelated process that happens to occupy
    /// the reserved local port, including after a failed connection or restart.
    static func checkOwnedEndpoint(_ url: URL) throws {
        guard url.host == "127.0.0.1", url.port == 18774,
              UserDefaults.standard.bool(forKey: protectionKey) else { return }
        guard let process = shared.process, process.isRunning else { throw URLError(.cannotConnectToHost) }
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        check.arguments = ["-nP", "-a", "-p", String(process.processIdentifier), "-iTCP:18774", "-sTCP:LISTEN"]
        check.standardOutput = FileHandle.nullDevice; check.standardError = FileHandle.nullDevice
        do { try check.run(); check.waitUntilExit() } catch { throw URLError(.cannotConnectToHost) }
        guard check.terminationStatus == 0, process.isRunning else { throw URLError(.cannotConnectToHost) }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        instanceID = ""
        stopProcess()
        status = L10n.text("GPUtw SSH connection disabled.")
    }

    private func stopProcess() {
        retryTimer?.invalidate(); retryTimer = nil
        let old = process; process = nil
        if old?.isRunning == true { old?.terminate() }
    }

    private func start() {
        guard let id = Self.normalizedID(instanceID), process == nil else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        task.arguments = ["-N", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
                          "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30",
                          "-o", "ServerAliveCountMax=3", "-L", "127.0.0.1:18774:127.0.0.1:8090",
                          "-p", "2222", "pod-\(id)@ssh.gputw.ai"]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.process = nil
                self.status = L10n.text("GPUtw SSH disconnected. Retrying; check the instance, SSH key, known host, and local port 18774.")
                self.retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.start() }
                }
            }
        }
        do {
            try task.run()
            process = task
            status = L10n.text("Connecting GPUtw through SSH. The server card shows whether ComfyUI is reachable.")
        } catch {
            status = L10n.text("Could not start SSH: %@", error.localizedDescription)
        }
    }
}
