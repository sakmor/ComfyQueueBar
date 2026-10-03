import Foundation
let now = Date(timeIntervalSince1970: 1_800_000_000)
func record(_ time: Date?, success: Bool = true, completed: Bool = true, interrupted: Bool = false, number: Int = 1) -> [String: Any] {
    var messages: [[Any]] = []
    if let time { messages.append(["execution_success", ["timestamp": time.timeIntervalSince1970 * 1000]]) }
    if interrupted { messages.append(["execution_interrupted", [:]]) }
    return ["status": ["completed": completed, "status_str": success ? "success" : "error", "messages": messages], "prompt": [number, "id", [:], [:]], "outputs": ["12": ["gifs": [["filename": "clip.mp4", "subfolder": "shots", "type": "output"], ["filename": "clip.mp4", "subfolder": "shots", "type": "output"]], "images": [["filename": "preview.png", "type": "temp"]]]]]
}
let input: [String: Any] = [
    "recent": record(now.addingTimeInterval(-60)),
    "older": record(now.addingTimeInterval(-120)),
    "expired": record(now.addingTimeInterval(-86_401)),
    "boundary": record(now.addingTimeInterval(-86_400)),
    "failed": record(now, success: false),
    "unfinished": record(now, completed: false),
    "interrupted": record(now, interrupted: true),
    "unknown-time": record(nil),
    "invalid": ["outputs": [:]]
]
let parsed = CompletionHistory.parse(input, now: now) { _, _ in "Workflow" }
precondition(parsed.map(\.id) == ["recent", "older", "boundary", "unknown-time"])
precondition(parsed[0].filenames == ["shots/clip.mp4"])
precondition(parsed[0].finishedAt == now.addingTimeInterval(-60))
precondition(parsed.last!.finishedAt == nil)
let many = Dictionary(uniqueKeysWithValues: (0..<30).map { (String($0), record(now.addingTimeInterval(-Double($0)))) })
precondition(CompletionHistory.parse(many, now: now, title: { _, _ in "Workflow" }).count == 20)
precondition(CompletionHistory.parse([:], now: now, title: { _, _ in "Workflow" }).isEmpty)
print("Completion history passed: success filtering, timestamps, 24-hour boundary, output files, deduplication, and limit")

let media = MediaOutput(filename: "shot #1 & next.mp4", subfolder: "a folder/中文", type: "output")
let mediaURL = media.url(endpoint: "https://example.com/comfy/?old=discard#fragment")!
let components = URLComponents(url: mediaURL, resolvingAgainstBaseURL: false)!
precondition(components.path == "/comfy/view")
precondition(components.queryItems!.first { $0.name == "filename" }!.value == media.filename)
precondition(components.queryItems!.first { $0.name == "subfolder" }!.value == media.subfolder)
precondition(components.fragment == nil)
precondition(MediaOutput(filename: "preview.png", subfolder: "", type: "temp").url(endpoint: "https://example.com") == nil)
precondition(media.url(endpoint: "file:///tmp") == nil)
precondition(media.isVideo && !media.isImage)
let details = (input["recent"] as! [String: Any])["outputs"]!
precondition(HistoryDetails.outputs(details).map(\.displayPath) == ["shots/clip.mp4"])
let failures = HistoryDetails.failures(input) { _, _ in "Workflow" }
precondition(Set(failures.map(\.id)) == ["failed", "interrupted"])
precondition(failures.first { $0.id == "interrupted" }!.interrupted)
precondition(HistoryRange.hour.includes(now.addingTimeInterval(-3599), now: now))
precondition(!HistoryRange.hour.includes(now.addingTimeInterval(-3601), now: now))
precondition(!HistoryRange.day.includes(nil, now: now))
precondition(HistoryRange.all.includes(nil, now: now))
let graphA: [String: Any] = ["1": ["class_type": "KSampler", "inputs": ["seed": 4, "steps": 20]], "2": ["class_type": "CLIPTextEncode", "inputs": ["text": "first"]]]
let graphB: [String: Any] = ["1": ["class_type": "KSampler", "inputs": ["seed": 8, "steps": 20]], "2": ["class_type": "CLIPTextEncode", "inputs": ["text": "second"]]]
let graphC: [String: Any] = ["1": ["class_type": "KSampler", "inputs": ["steps": 40]]]
let fingerprint = HistoryDetails.fingerprint(graphA)
precondition(!fingerprint.isEmpty && fingerprint == HistoryDetails.fingerprint(graphB))
precondition(fingerprint != HistoryDetails.fingerprint(graphC))
var samples: [CompletedJob] = []
for duration in [100.0, 140.0, 120.0] {
    samples.append(CompletedJob(id: String(duration), title: "Sample", finishedAt: now, filenames: [], queueNumber: 0, startedAt: now.addingTimeInterval(-duration), fingerprint: fingerprint))
}
precondition(HistoryDetails.estimatedDuration(fingerprint: fingerprint, completed: Array(samples.prefix(2))) == nil)
precondition(HistoryDetails.estimatedDuration(fingerprint: fingerprint, completed: samples) == 120)
precondition(HistoryDetails.estimatedDuration(fingerprint: "", completed: samples) == nil)
let profile = ServerProfile(name: "Windows", endpoint: "http://example.com:8188")
let decodedProfile = try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(profile))
precondition(decodedProfile == profile)
print("Extended features passed: URL encoding, output metadata, failures, range filters, estimates, and profile persistence")
var tracker = NotificationTracker()
tracker.observeQueue(count: 2)
let baseline = tracker.ingest(ids: ["old"], successes: ["old"], failures: [], queueCount: 2)
precondition(baseline.successes.isEmpty && baseline.batch == nil)
let first = tracker.ingest(ids: ["old", "new"], successes: ["old", "new"], failures: [], queueCount: 1)
precondition(first.successes == ["new"] && first.batch == nil)
let duplicate = tracker.ingest(ids: ["old", "new"], successes: ["old", "new"], failures: [], queueCount: 1)
precondition(duplicate.successes.isEmpty)
let drained = tracker.ingest(ids: ["old", "new", "error"], successes: ["old", "new"], failures: ["error"], queueCount: 0)
precondition(drained.failures == ["error"] && drained.batch?.completed == 1 && drained.batch?.failed == 1)
precondition(tracker.ingest(ids: ["old", "new", "error"], successes: ["old", "new"], failures: ["error"], queueCount: 0).batch == nil)
print("Notification state passed: baseline suppression, deduplication, and batch completion")

let fast = tracker.ingest(ids: ["old", "new", "error", "fast"], successes: ["old", "new", "fast"], failures: ["error"], queueCount: 0)
precondition(fast.batch?.completed == 1 && fast.successes == ["fast"])

precondition(media.absolutePath(root: "/Volumes/Render/output/") == "/Volumes/Render/output/a folder/中文/shot #1 & next.mp4")
precondition(media.absolutePath(root: #"D:\ComfyUI\output"#) == #"D:\ComfyUI\output\a folder\中文\shot #1 & next.mp4"#)
precondition(media.absolutePath(root: #"\\render\share\output"#) == #"\\render\share\output\a folder\中文\shot #1 & next.mp4"#)
precondition(media.absolutePath(root: "relative/output") == nil)
precondition(MediaOutput(filename: "clip.mp4", subfolder: "../other", type: "output").absolutePath(root: "/output") == nil)
precondition(MediaOutput(filename: "clip.mp4", subfolder: "", type: "input").absolutePath(root: "/output") == nil)
print("Absolute output paths passed: POSIX, Windows, UNC, invalid roots, traversal, and output type")
