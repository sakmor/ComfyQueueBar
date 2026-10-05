import AppKit
import Foundation
import SwiftUI

enum MonitoringState: Equatable {
    case checking, connected, disconnected, signInRequired, stale

    static func resolve(connected: Bool, loading: Bool, needsSignIn: Bool, lastUpdated: Date?, hasError: Bool, now: Date) -> Self {
        if needsSignIn { return .signInRequired }
        if connected {
            guard let lastUpdated, now.timeIntervalSince(lastUpdated) < 30 else { return .stale }
            return .connected
        }
        return loading && lastUpdated == nil && !hasError ? .checking : .disconnected
    }

    var label: String {
        switch self {
        case .checking: return L10n.text("Checking connection…")
        case .connected: return L10n.text("Connected")
        case .disconnected: return L10n.text("Disconnected")
        case .signInRequired: return L10n.text("Sign-in required")
        case .stale: return L10n.text("Queue status out of date")
        }
    }

    func badge(count: Int) -> String {
        switch self {
        case .connected: return count > 99 ? "99+" : String(count)
        case .checking: return "…"
        case .signInRequired: return "!"
        case .disconnected, .stale: return "—"
        }
    }

    static func requiresSignIn(_ error: Error) -> Bool {
        if case GPUTWError.signInRequired = error { return true }
        if case QueueError.serverStatus(let code, _) = error { return code == 401 || code == 403 }
        return false
    }
}

enum ConnectionAddress {
    static func normalize(_ address: String) throws -> String {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value), let host = parts.host, !host.isEmpty,
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil else { throw QueueError.invalidEndpoint }
        if let url = parts.url, let origin = GPUTWAddress.serviceOrigin(url) { return origin.absoluteString }
        parts.query = nil; parts.fragment = nil
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let url = parts.url else { throw QueueError.invalidEndpoint }
        return url.absoluteString
    }

    static func port(_ endpoint: String) -> String {
        guard let url = URL(string: endpoint) else { return "—" }
        if GPUTWAddress.serviceOrigin(url) != nil { return url.host?.split(separator: "-").first.map(String.init) ?? "—" }
        return String(url.port ?? (url.scheme == "https" ? 443 : 80))
    }

    static func portLabel(_ endpoint: String) -> String { L10n.text("Port %@", port(endpoint)) }
}

struct ConnectionInspection {
    let endpoint: String
    let checkedAt: Date
    let running: [QueueJob]
    let pending: [QueueJob]
    let completed: [CompletedJob]
    let failures: [FailedJob]
    let historyAvailable: Bool
    var isIdle: Bool { running.isEmpty && pending.isEmpty }
}

@MainActor
enum ConnectionInspector {
    static func inspect(_ address: String, client: ComfyHTTPClient? = nil) async throws -> ConnectionInspection {
        try Task.checkCancellation()
        let endpoint = try ConnectionAddress.normalize(address)
        let client = client ?? .shared
        func read(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
            var parts = URLComponents(string: endpoint)!
            parts.path += "/" + path
            parts.queryItems = query.isEmpty ? nil : query
            var request = URLRequest(url: parts.url!)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await client.data(for: request)
            guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else {
                throw QueueError.serverStatus((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QueueError.invalidResponse }
            return object
        }
        let queue = try await read("queue")
        guard ComfyQueuePayload.isValid(queue) else { throw QueueError.invalidResponse }
        let checkedAt = Date()
        var history: [String: Any] = [:]
        var historyAvailable = false
        do {
            history = try await read("history", query: [URLQueryItem(name: "max_items", value: "20")])
            historyAvailable = true
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            // A queue can be healthy while history is unsupported or temporarily unavailable.
        }
        try Task.checkCancellation()
        return ConnectionInspection(endpoint: endpoint, checkedAt: checkedAt,
            running: QueueViewModel.parseJobs(queue["queue_running"]), pending: QueueViewModel.parseJobs(queue["queue_pending"]),
            completed: CompletionHistory.parse(history, now: Date(), maxAge: nil, limit: 3, title: QueueViewModel.jobTitle),
            failures: Array(HistoryDetails.failures(history, title: QueueViewModel.jobTitle).prefix(1)),
            historyAvailable: historyAvailable)
    }
}

@MainActor
final class ConnectionReviewModel: ObservableObject {
    @Published private(set) var inspection: ConnectionInspection?
    @Published private(set) var error: String?
    @Published private(set) var checking = false
    private var revision = UUID()

    func cancel() { revision = UUID(); inspection = nil; error = nil; checking = false }

    func inspect(_ address: String) async {
        guard !Task.isCancelled else { return }
        let token = UUID(); revision = token
        inspection = nil; error = nil; checking = true
        defer { if revision == token { checking = false } }
        do {
            let result = try await ConnectionInspector.inspect(address)
            guard revision == token, !Task.isCancelled else { return }
            inspection = result
        } catch {
            guard revision == token, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class ConnectionReviewWindow: NSObject, NSWindowDelegate {
    static let shared = ConnectionReviewWindow()
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private let model = ConnectionReviewModel()
    private var onConfirm: ((String) -> Void)?

    func open(address: String, onConfirm: @escaping (String) -> Void) {
        close()
        self.onConfirm = onConfirm
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.text("Confirm monitoring server")
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentViewController = NSHostingController(rootView: ConnectionReviewView(address: address, model: model,
            refresh: { [weak self] in self?.inspect(address) }, cancel: { [weak self] in self?.close() },
            confirm: { [weak self] in self?.confirm() }))
        self.window = window
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        inspect(address)
    }

    private func inspect(_ address: String) {
        task?.cancel()
        task = Task { await model.inspect(address) }
    }

    private func confirm() {
        guard let inspection = model.inspection, !model.checking else { return }
        let callback = onConfirm
        close()
        callback?(inspection.endpoint)
    }

    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) {
        task?.cancel(); task = nil; model.cancel(); onConfirm = nil
        window?.contentViewController = nil; window = nil
    }
}

struct ConnectionReviewView: View {
    let address: String
    @ObservedObject var model: ConnectionReviewModel
    let refresh: () -> Void
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Confirm monitoring server")).font(.title2.bold())
            Text(ConnectionAddress.portLabel(address)).font(.title3.monospacedDigit().bold())
            Text(address).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.checking {
                        HStack { ProgressView().controlSize(.small); Text(L10n.text("Reading queue and recent history…")) }
                    } else if let error = model.error {
                        Label(L10n.text("Unable to read the queue"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(error).font(.callout)
                    } else if let inspection = model.inspection {
                        ConnectionInspectionCard(inspection: inspection)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text(L10n.text("Your current monitoring server changes only after you confirm.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(L10n.text("Refresh details"), action: refresh).disabled(model.checking)
                Spacer()
                Button(L10n.text("Monitor this server"), action: confirm).buttonStyle(.borderedProminent)
                    .disabled(model.inspection == nil || model.checking)
            }
        }.padding(22).frame(width: 480, height: 660)
    }
}

struct ConnectionInspectionCard: View {
    let inspection: ConnectionInspection
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                count(L10n.text("Running"), inspection.running.count)
                count(L10n.text("Waiting"), inspection.pending.count)
            }
            Text(L10n.text("Checked %@", inspection.checkedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(L10n.locale))))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Counts show ComfyUI jobs, not GPU utilization.")).font(.caption).foregroundStyle(.secondary)
            if inspection.isIdle {
                Label(L10n.text("This queue is empty. If you expect a running job, check the port and recent work below."), systemImage: "info.circle")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .padding(10).background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(inspection.running.prefix(2)) { job in
                Label(job.title, systemImage: "waveform.path").font(.callout).lineLimit(2).help(job.title)
            }
            Divider()
            Text(L10n.text("Recent successful jobs")).font(.headline)
            if !inspection.historyAvailable {
                Text(L10n.text("History could not be read. Recent work is unknown.")).foregroundStyle(.orange)
            } else if inspection.completed.isEmpty {
                Text(L10n.text("No successful jobs in the latest 20 history records.")).foregroundStyle(.secondary)
            } else {
                ForEach(inspection.completed) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title).font(.callout).lineLimit(2).help(job.title)
                        Text(job.finishedAt.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)) }
                             ?? L10n.text("Completion time unavailable")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let failure = inspection.failures.first {
                Divider()
                Text(L10n.text(failure.interrupted ? "Interrupted" : "Failed")).font(.headline).foregroundStyle(.orange)
                Text(failure.title).font(.callout).lineLimit(2).help(failure.title)
            }
        }.font(.callout)
    }

    private func count(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(value)).font(.title2.monospacedDigit().bold())
        }
    }
}
