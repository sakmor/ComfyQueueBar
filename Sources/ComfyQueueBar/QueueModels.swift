import AppKit
import Foundation
import SwiftUI
import WebKit

struct CompletedJob: Identifiable {
    let id: String
    let title: String
    let finishedAt: Date?
    let filenames: [String]
    let queueNumber: Double
    var outputs: [MediaOutput] = []
    var startedAt: Date? = nil
    var fingerprint: String = ""
}

// Only explicit successful, completed history records qualify. Never infer success from /queue.
enum CompletionHistory {
    static func parse(_ history: [String: Any], now: Date, maxAge: TimeInterval? = 86400, limit: Int = 20, title: ([String: Any], [String: Any]) -> String) -> [CompletedJob] {
        let cutoff = maxAge.map { now.addingTimeInterval(-$0) }
        let jobs: [CompletedJob] = history.compactMap { id, value in
            guard let entry = value as? [String: Any],
                  let status = entry["status"] as? [String: Any],
                  status["completed"] as? Bool == true,
                  status["status_str"] as? String == "success" else { return nil }
            let messages = status["messages"] as? [[Any]] ?? []
            guard !messages.contains(where: { ["execution_error", "execution_interrupted"].contains($0.first as? String ?? "") }) else { return nil }
            let milliseconds = messages.compactMap { message -> Double? in
                guard message.first as? String == "execution_success", message.count > 1,
                      let details = message[1] as? [String: Any], let timestamp = details["timestamp"] as? NSNumber else { return nil }
                let value = timestamp.doubleValue
                return value.isFinite && value > 0 ? value : nil
            }.max()
            let date = milliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
            if let date, let cutoff, date < cutoff { return nil }
            let prompt = entry["prompt"] as? [Any] ?? []
            let graph = prompt.count > 2 ? prompt[2] as? [String: Any] ?? [:] : [:]
            let extra = prompt.count > 3 ? prompt[3] as? [String: Any] ?? [:] : [:]
            var files = Set<String>()
            collectFiles(entry["outputs"] as Any, into: &files)
            let outputs = HistoryDetails.outputs(entry["outputs"] as Any)
            return CompletedJob(id: id, title: title(graph, extra), finishedAt: date, filenames: files.sorted(), queueNumber: (prompt.first as? NSNumber)?.doubleValue ?? 0, outputs: outputs, startedAt: HistoryDetails.eventDate(messages, events: ["execution_start"]), fingerprint: HistoryDetails.fingerprint(graph))
        }
        return Array(jobs.sorted {
            if $0.finishedAt != $1.finishedAt { return ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            if $0.queueNumber != $1.queueNumber { return $0.queueNumber > $1.queueNumber }
            return $0.id < $1.id
        }.prefix(limit))
    }

    private static func collectFiles(_ value: Any, into files: inout Set<String>) {
        if let object = value as? [String: Any] {
            if let filename = object["filename"] as? String, !filename.isEmpty, object["type"] as? String != "temp" {
                let subfolder = object["subfolder"] as? String ?? ""
                files.insert(subfolder.isEmpty ? filename : subfolder + "/" + filename)
            }
            for nested in object.values { collectFiles(nested, into: &files) }
        } else if let array = value as? [Any] {
            for nested in array { collectFiles(nested, into: &files) }
        }
    }
}

struct QueueJob: Identifiable {
    let id: String
    let title: String
    let nodeCount: Int
    let queueNumber: Int?
    let position: Int
    let prompt: [String: Any]
    let extraData: [String: Any]

    var shortID: String { String(id.prefix(8)) }
}

struct QueueProgress: Decodable {
    let promptID: String?
    let nodeID: String?
    let value: Double?
    let maxValue: Double?
    let percent: Double?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case promptID = "prompt_id"
        case nodeID = "node_id"
        case value
        case maxValue = "max"
        case percent
        case state
    }

    func nodeTitle(for job: QueueJob) -> String {
        guard let nodeID else { return L10n.text("Waiting for node progress") }
        if let node = job.prompt[nodeID] as? [String: Any],
           let meta = node["_meta"] as? [String: Any],
           let title = meta["title"] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return L10n.text("Node %@", String(nodeID))
    }
}

enum ProgressBridgeStatus: Equatable {
    case checking
    case available
    case missing
    case error
}

enum QueueError: LocalizedError {
    case invalidEndpoint
    case serverChanged
    case serverStatus(Int, String?)
    case invalidResponse
    case jobNoLongerPending
    case jobAlreadyRunning
    case jobNoLongerRunning
    case originalStillPending

    var errorDescription: String? {
        switch self {
        case .serverChanged: return L10n.text("Server changed. Refresh before trying again.")
        case .invalidEndpoint: return L10n.text("Enter a valid http:// or https:// address.")
        case .serverStatus(let status, let detail):
            return L10n.text("ComfyUI returned HTTP %@.", String(status)) + (detail.map { " \($0)" } ?? "")
        case .invalidResponse: return L10n.text("ComfyUI returned an unrecognized queue response.")
        case .jobNoLongerPending: return L10n.text("This job is no longer waiting. Refresh and try again.")
        case .jobAlreadyRunning: return L10n.text("The original job started. Prioritization was canceled; the running job will continue.")
        case .jobNoLongerRunning: return L10n.text("This job is no longer running. No stop request was sent.")
        case .originalStillPending: return L10n.text("ComfyUI did not remove the original job. Checking resubmission cleanup.")
        }
    }
}
