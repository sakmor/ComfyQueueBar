import AppKit
import Foundation
import SwiftUI
import WebKit

enum JobState {
    case running
    case pending

    var label: String { self == .running ? L10n.text("Running") : L10n.text("Waiting") }
    var color: Color { self == .running ? .cyan : .orange }
    var symbol: String { self == .running ? "bolt.fill" : "clock" }
}

enum QueueConfirmation {
    case prioritize(QueueJob)
    case stop(QueueJob)
    case removeServer(ServerProfile)

    var title: String {
        switch self {
        case .prioritize: return L10n.text("Prioritize this job?")
        case .stop: return L10n.text("Stop this job?")
        case .removeServer: return L10n.text("Remove this server?")
        }
    }

    var message: String {
        switch self {
        case .prioritize(let job):
            return L10n.text("Move \"%@\" to the front of the waiting queue. The running job continues. This resubmits the job and changes its prompt ID.", String(job.title))
        case .removeServer(let profile):
            return L10n.text("Stop monitoring %@? Jobs on this server will continue running.", profile.name)
        case .stop(let job):
            return L10n.text("Stop generation for \"%@\". Waiting jobs remain queued and the next job can run.", String(job.title))
        }
    }
}

struct JobCard: View {
    let job: QueueJob
    let state: JobState
    let progress: QueueProgress?
    let progressBridgeStatus: ProgressBridgeStatus
    let isMoving: Bool
    let isStopping: Bool
    let isActionEnabled: Bool
    let onPrioritize: (() -> Void)?
    let onStop: (() -> Void)?
    var timing: ((Date) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if case .pending = state {
                    Text(String(job.position))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(job.title)
                    HStack(spacing: 5) {
                        Text(L10n.text("%@ nodes", String(job.nodeCount)))
                        Text("·")
                        Text(job.shortID).font(.system(size: 10, design: .monospaced))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if case .pending = state {
                    Button(action: { onPrioritize?() }) {
                        Label(L10n.text("Run next"), systemImage: "arrow.up.to.line")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isActionEnabled || isMoving)
                    .help(L10n.text("Run next after the current job"))
                    .accessibilityLabel(isMoving ? L10n.text("Working") : L10n.text("Prioritize"))
                } else {
                    Button(action: { onStop?() }) {
                        Label(L10n.text("Stop"), systemImage: "stop.circle")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isActionEnabled || isStopping)
                    .help(L10n.text("Stop this job while keeping waiting jobs"))
                    .accessibilityLabel(isStopping ? L10n.text("Stopping") : L10n.text("Stop"))
                }
            }
            if case .running = state {
                progressDetails
                if let timing {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(timing(context.date)).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .help(L10n.text("Estimates need 3 similar successful jobs. Elapsed time starts when this app first observes the job."))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var progressDetails: some View {
        if let progress {
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.nodeTitle(for: job))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.8))
                HStack(spacing: 6) {
                    if let percent = progress.percent {
                        ProgressView(value: min(max(percent / 100, 0), 1))
                            .controlSize(.mini)
                            .frame(maxWidth: .infinity)
                        Text("\(Int(percent.rounded()))%")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    } else {
                        ProgressView().controlSize(.mini)
                        Text(L10n.text("Node is processing"))
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        } else {
            HStack(spacing: 5) {
                if progressBridgeStatus == .checking {
                    ProgressView().controlSize(.mini)
                }
                Text(progressStatusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.top, 2)
        }
    }

    private var progressStatusText: String {
        switch progressBridgeStatus {
        case .checking: return L10n.text("Fetching node progress…")
        case .available: return L10n.text("No progress reported for this node yet")
        case .missing: return L10n.text("Install the progress extension and restart ComfyUI")
        case .error: return L10n.text("Unable to read live progress")
        }
    }
}
