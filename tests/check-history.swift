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
