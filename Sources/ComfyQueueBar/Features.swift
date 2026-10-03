import AppKit
import AVKit
import CryptoKit
import Foundation
import SwiftUI
import UserNotifications

// PURE_FEATURE_MODELS_BEGIN
struct MediaOutput: Identifiable, Hashable {
    let filename: String
    let subfolder: String
    let type: String
    var id: String { type + ":" + subfolder + "/" + filename }
    var displayPath: String { subfolder.isEmpty ? filename : subfolder + "/" + filename }
    func absolutePath(root: String) -> String? {
        let root = root.trimmingCharacters(in: .whitespacesAndNewlines)
        let windows = root.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil || root.hasPrefix("\\\\")
        guard root.hasPrefix("/") || windows, type == "output" else { return nil }
        let parts = (subfolder + "/" + filename).replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        guard !filename.isEmpty, !filename.hasPrefix("/"), !filename.hasPrefix("\\"),
              !subfolder.hasPrefix("/"), !subfolder.hasPrefix("\\"),
              !parts.contains(".."), !parts.contains(where: { $0.contains(":") || $0.contains("\n") || $0.contains("\r") }),
              !root.contains("\n"), !root.contains("\r") else { return nil }
        let separator = windows && root.contains("\\") ? "\\" : "/"
        var base = root
        while base.hasSuffix("/") || base.hasSuffix("\\") { base.removeLast() }
        return base + separator + parts.filter { $0 != "." }.joined(separator: separator)
    }
    var isImage: Bool { ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp"].contains((filename as NSString).pathExtension.lowercased()) }
    var isVideo: Bool { ["mp4", "mov", "m4v"].contains((filename as NSString).pathExtension.lowercased()) }
    func url(endpoint: String) -> URL? {
        guard var components = URLComponents(string: endpoint), ["http", "https"].contains(components.scheme?.lowercased() ?? ""), components.host != nil,
              ["output", "input"].contains(type) else { return nil }
        let base = components.path.split(separator: "/").joined(separator: "/")
        components.path = "/" + [base, "view"].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = [URLQueryItem(name: "filename", value: filename), URLQueryItem(name: "subfolder", value: subfolder), URLQueryItem(name: "type", value: type)]
        components.fragment = nil
        return components.url
    }
}

struct ServerProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var endpoint: String
}

enum HistoryRange: String, CaseIterable {
    case hour, day, today, all
    var label: String {
        switch self { case .hour: return "Last hour"; case .day: return "Last 24 hours"; case .today: return "Today"; case .all: return "Loaded history" }
    }
    func includes(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let date else { return self == .all }
        switch self {
        case .hour: return date >= now.addingTimeInterval(-3600)
        case .day: return date >= now.addingTimeInterval(-86400)
        case .today: return date >= calendar.startOfDay(for: now)
        case .all: return true
        }
    }
}

struct FailedJob: Identifiable {
    let id: String
    let title: String
    let date: Date?
    let reason: String
    let interrupted: Bool
}

enum HistoryDetails {
    static func eventDate(_ messages: [[Any]], events: Set<String>) -> Date? {
        messages.compactMap { message -> Date? in
            guard let event = message.first as? String, events.contains(event), message.count > 1,
                  let details = message[1] as? [String: Any], let number = details["timestamp"] as? NSNumber else { return nil }
            let value = number.doubleValue
            return value.isFinite && value > 0 ? Date(timeIntervalSince1970: value / 1000) : nil
        }.max()
    }
    static func outputs(_ value: Any) -> [MediaOutput] {
        var files = Set<MediaOutput>()
        func visit(_ value: Any) {
            if let object = value as? [String: Any] {
                if let filename = object["filename"] as? String, !filename.isEmpty,
                   let type = object["type"] as? String, ["output", "input"].contains(type) {
                    files.insert(MediaOutput(filename: filename, subfolder: object["subfolder"] as? String ?? "", type: type))
                }
                for nested in object.values { visit(nested) }
            } else if let array = value as? [Any] { for nested in array { visit(nested) } }
        }
        visit(value)
        return files.sorted { $0.displayPath < $1.displayPath }
    }
    static func fingerprint(_ prompt: [String: Any]) -> String {
        // Match execution settings while ignoring labels, seed, text, and output names.
        let ignored = Set(["_meta", "seed", "noise_seed", "text", "filename_prefix", "file_prefix"])
        func clean(_ value: Any) -> Any {
            if let object = value as? [String: Any] { return object.filter { !ignored.contains($0.key) }.mapValues(clean) }
            if let array = value as? [Any] { return array.map(clean) }
            return value
        }
        guard !prompt.isEmpty, let data = try? JSONSerialization.data(withJSONObject: clean(prompt), options: .sortedKeys) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func failures(_ history: [String: Any], title: ([String: Any], [String: Any]) -> String) -> [FailedJob] {
        history.compactMap { id, value -> FailedJob? in
            guard let entry = value as? [String: Any], let status = entry["status"] as? [String: Any] else { return nil }
            let messages = status["messages"] as? [[Any]] ?? []
            let interrupted = messages.contains { $0.first as? String == "execution_interrupted" }
            let errors = messages.filter { $0.first as? String == "execution_error" }
            guard interrupted || !errors.isEmpty || status["status_str"] as? String == "error" else { return nil }
            let prompt = entry["prompt"] as? [Any] ?? []
            let graph = prompt.count > 2 ? prompt[2] as? [String: Any] ?? [:] : [:]
            let extra = prompt.count > 3 ? prompt[3] as? [String: Any] ?? [:] : [:]
            let details = errors.last.flatMap { $0.count > 1 ? $0[1] as? [String: Any] : nil } ?? [:]
            let reason = [details["node_type"], details["exception_type"], details["exception_message"]].compactMap { $0 as? String }.joined(separator: " · ")
            return FailedJob(id: id, title: title(graph, extra), date: eventDate(messages, events: ["execution_error", "execution_interrupted"]), reason: String(reason.prefix(2000)), interrupted: interrupted)
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    static func estimatedDuration(fingerprint: String, completed: [CompletedJob]) -> TimeInterval? {
        guard !fingerprint.isEmpty else { return nil }
        let samples = completed.filter { $0.fingerprint == fingerprint }.compactMap { job -> Double? in
            guard let start = job.startedAt, let end = job.finishedAt, end > start else { return nil }
            return end.timeIntervalSince(start)
        }.prefix(10).sorted()
        guard samples.count >= 3 else { return nil }
        let middle = samples.count / 2
        return samples.count % 2 == 0 ? (samples[middle - 1] + samples[middle]) / 2 : samples[middle]
    }
}
struct NotificationDelta {
    var successes = Set<String>()
    var failures = Set<String>()
    var batch: (completed: Int, failed: Int)?
}

struct NotificationTracker {
    private var seen: Set<String>?
    private var active = false
    private var succeeded = 0
    private var failed = 0
    mutating func observeQueue(count: Int) { if count > 0 { active = true } }
    mutating func ingest(ids: Set<String>, successes: Set<String>, failures: Set<String>, queueCount: Int) -> NotificationDelta {
        guard let known = seen else { seen = ids; return NotificationDelta() }
        var result = NotificationDelta(successes: successes.subtracting(known), failures: failures.subtracting(known))
        succeeded += result.successes.count; failed += result.failures.count
        if !result.successes.isEmpty || !result.failures.isEmpty { active = true }
        if queueCount == 0 && active {
            if succeeded + failed > 0 { result.batch = (succeeded, failed) }
            active = false; succeeded = 0; failed = 0
        }
        seen = known.union(ids)
        if (seen?.count ?? 0) > 1000 { seen = ids }
        return result
    }
}

// PURE_FEATURE_MODELS_END

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    @Published var permissionMessage: String?
    func authorize() async {
        #if !DOCUMENTATION_SCREENSHOT
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            permissionMessage = allowed ? nil : L10n.text("Allow notifications in macOS System Settings.")
            UNUserNotificationCenter.current().delegate = self
        } catch { permissionMessage = error.localizedDescription }
        #endif
    }
    func send(id: String, title: String, body: String) {
        #if !DOCUMENTATION_SCREENSHOT
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        #endif
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}

@MainActor
final class MediaPreviewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var player: AVPlayer?
    @Published var error: String?
    @Published var loading = false
    @Published var downloaded = false
    @Published var isDownloading = false
    private var loadTask: Task<Void, Never>?
    private var videoObservation: NSKeyValueObservation?
    func load(_ output: MediaOutput, endpoint: String) {
        loadTask?.cancel()
        videoObservation?.invalidate()
        player?.pause()
        player = nil; image = nil; error = nil; downloaded = false; loading = false
        guard let url = output.url(endpoint: endpoint) else { error = L10n.text("Preview unavailable"); return }
        #if DOCUMENTATION_SCREENSHOT
        image = NSImage(contentsOf: Bundle.main.url(forResource: "DemoOutput", withExtension: "png")!)
        #else
        if output.isVideo {
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item) // Native playback controls; no automatic playback.
            videoObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    if item.status == .failed { self?.error = item.error?.localizedDescription ?? L10n.text("Preview unavailable") }
                }
            }
        } else if output.isImage {
            loading = true
            loadTask = Task {
                defer { if !Task.isCancelled { loading = false } }
                do {
                    var request = URLRequest(url: url); request.timeoutInterval = 30
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard !Task.isCancelled else { return }
                    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 32 * 1024 * 1024, let decoded = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                    image = decoded
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        }
        #endif
    }
    func stop() { loadTask?.cancel(); videoObservation?.invalidate(); player?.pause() }
    func download(_ output: MediaOutput, endpoint: String) async {
        guard !isDownloading, let url = output.url(endpoint: endpoint) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (output.filename as NSString).lastPathComponent
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        isDownloading = true; downloaded = false; error = nil
        #if !DOCUMENTATION_SCREENSHOT
        defer { isDownloading = false }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = 60
            let (temporary, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            // The user explicitly chose the destination (and confirmed any replacement).
            let staging = destination.deletingLastPathComponent().appendingPathComponent(".comfyqueuebar-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: temporary, to: staging)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else { try FileManager.default.moveItem(at: staging, to: destination) }
            downloaded = true
        } catch { self.error = error.localizedDescription }
        #endif
    }
}

@MainActor
final class FeatureViewState: ObservableObject {
    @Published var outputRoot = ""
    @Published var copied = false
    @Published var selected = 0
    @Published var preview = false
    @Published var image: NSImage?
}

@MainActor
struct MediaPreview: View {
    let job: CompletedJob
    let endpoint: String
    @StateObject private var state = FeatureViewState()
    @ObservedObject var model: MediaPreviewModel
    private var output: MediaOutput? { job.outputs.indices.contains(state.selected) ? job.outputs[state.selected] : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(job.title).font(.headline)
            if job.outputs.count > 1 {
                Picker(L10n.text("Output"), selection: $state.selected) {
                    ForEach(Array(job.outputs.enumerated()), id: \.offset) { index, file in Text(file.filename).tag(index) }
                }
            }
            if let image = model.image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260)
            } else if let player = model.player {
                VideoPlayer(player: player).frame(height: 260)
            } else if model.loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Label(L10n.text("Preview unavailable"), systemImage: "doc").foregroundStyle(.secondary)
            }
            if let output {
                Text(output.displayPath).font(.caption).textSelection(.enabled)
                HStack {
                    Button(L10n.text("Download…")) { Task { await model.download(output, endpoint: endpoint) } }
                        .disabled(model.isDownloading)
                    Button(L10n.text(state.copied ? "Path copied" : "Copy absolute path")) {
                        guard let path = output.absolutePath(root: state.outputRoot) else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                        state.copied = true
                    }.disabled(output.absolutePath(root: state.outputRoot) == nil)
                }
                Button(L10n.text("Set output folder…")) { configureOutputRoot() }.font(.caption)
                if let path = output.absolutePath(root: state.outputRoot) {
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if model.isDownloading { ProgressView().controlSize(.small) }
            if model.downloaded { Text(L10n.text("Downloaded")).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .padding(20).frame(width: 440)
        .onAppear {
            state.outputRoot = UserDefaults.standard.dictionary(forKey: "outputRoots")?[endpoint] as? String ?? ""
            if let output { model.load(output, endpoint: endpoint) }
        }
        .onChange(of: state.selected) { _ in state.copied = false; if let output { model.load(output, endpoint: endpoint) } }
        .onDisappear { model.stop() }
    }
    private func configureOutputRoot() {
        let alert = NSAlert()
        alert.messageText = L10n.text("Set output folder…")
        alert.informativeText = L10n.text("Enter this server's absolute output folder path. Remote paths refer to the server, not this Mac.")
        let field = NSTextField(string: state.outputRoot)
        field.frame = NSRect(x: 0, y: 0, width: 340, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("Save folder"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let root = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard root.isEmpty || MediaOutput(filename: "check", subfolder: "", type: "output").absolutePath(root: root) != nil else {
            let error = NSAlert()
            error.messageText = L10n.text("Enter an absolute folder path.")
            error.runModal()
            return
        }
        state.outputRoot = root
        state.copied = false
        var roots = UserDefaults.standard.dictionary(forKey: "outputRoots") ?? [:]
        roots[endpoint] = root
        UserDefaults.standard.set(roots, forKey: "outputRoots")
    }

}

/// A separate retained window avoids nested popover dismissal in a menu-bar app.
@MainActor
final class MediaPreviewWindow: NSObject, NSWindowDelegate {
    static let shared = MediaPreviewWindow()
    private var window: NSWindow?
    private var model: MediaPreviewModel?
    func open(job: CompletedJob, endpoint: String) {
        window?.close()
        let model = MediaPreviewModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 460), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = job.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: MediaPreview(job: job, endpoint: endpoint, model: model).frame(width: 440, height: 560))
        self.model = model
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        model?.stop()
        window?.contentViewController = nil
        model = nil
        window = nil
    }
}

struct CompletionRow: View {
    let job: CompletedJob
    let endpoint: String
    @StateObject private var state = FeatureViewState()
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let file = job.outputs.first(where: { $0.isImage || $0.isVideo }) {
                Button { MediaPreviewWindow.shared.open(job: job, endpoint: endpoint) } label: {
                    Thumbnail(output: file, endpoint: endpoint)
                }.buttonStyle(.plain).help(L10n.text("Preview"))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Spacer(minLength: 4)
                    if let date = job.finishedAt {
                        Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale))).font(.system(size: 10)).foregroundStyle(.secondary)
                            .help(date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Text(job.filenames.isEmpty ? L10n.text("No output files reported") : job.filenames.joined(separator: "\n"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).help(job.filenames.joined(separator: "\n"))
                if job.finishedAt == nil { Text(L10n.text("Completion time unavailable")).font(.system(size: 10)).foregroundStyle(.tertiary) }
                if !job.outputs.isEmpty {
                    Button(L10n.text("Preview & download…")) { MediaPreviewWindow.shared.open(job: job, endpoint: endpoint) }.buttonStyle(.link).font(.system(size: 10))
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Thumbnail: View {
    let output: MediaOutput
    let endpoint: String
    @StateObject private var state = FeatureViewState()
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
            if let image = state.image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: output.isVideo ? "play.rectangle" : "photo").foregroundStyle(.secondary) }
        }
        .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: endpoint + output.id) {
            #if DOCUMENTATION_SCREENSHOT
            state.image = NSImage(contentsOf: Bundle.main.url(forResource: "DemoOutput", withExtension: "png")!)
            #else
            state.image = nil
            guard let url = output.url(endpoint: endpoint) else { return }
            if output.isImage {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.queryItems?.append(URLQueryItem(name: "preview", value: "webp;70"))
                guard let previewURL = components.url else { return }
                if let (data, response) = try? await URLSession.shared.data(from: previewURL),
                   (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8 * 1024 * 1024, !Task.isCancelled { state.image = NSImage(data: data) }
            } else if output.isVideo {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 120, height: 120)
                if let frame = try? await generator.image(at: .zero), !Task.isCancelled { state.image = NSImage(cgImage: frame.image, size: .zero) }
            }
            #endif
        }
    }
}
