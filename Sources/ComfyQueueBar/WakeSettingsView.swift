import AppKit
import Foundation
import SwiftUI
import WebKit

@MainActor
final class WakeSettingsDraft: ObservableObject {
    @Published var settings = WakeSettings()
    @Published var portInput = "9"
}

struct WakeSettingsView: View {
    @ObservedObject var queue: QueueViewModel
    let profile: ServerProfile
    @StateObject private var draft = WakeSettingsDraft()

    var body: some View {
        DisclosureGroup(L10n.text("Wake Mac")) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(L10n.text("MAC address"), text: $draft.settings.macAddress)
                TextField(L10n.text("Broadcast IPv4 address"), text: $draft.settings.broadcastAddress)
                TextField(L10n.text("UDP port"), text: $draft.portInput)
                Toggle(L10n.text("Automatically wake when offline"), isOn: $draft.settings.automaticallyWake)
                    .toggleStyle(.checkbox)
                Text(L10n.text("Checks the selected server only. Retries every 2 minutes. Enable Wake for network access on the target Mac; the network must allow wake packets."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("Save wake settings")) { save() }
                    Button(L10n.text("Wake now")) {
                        guard save() else { return }
                        queue.wakeServer(profile.id)
                    }
                }.controlSize(.small)
                if let message = queue.wakeMessages[profile.id] {
                    Text(message).font(.caption).textSelection(.enabled)
                }
            }.textFieldStyle(.roundedBorder).padding(.top, 6)
        }
        .onAppear {
            draft.settings = profile.wake ?? WakeSettings()
            draft.portInput = String(draft.settings.port)
        }
    }

    @discardableResult
    private func save() -> Bool {
        draft.settings.port = UInt16(draft.portInput) ?? 0
        queue.saveWakeSettings(draft.settings, for: profile.id)
        return (try? WakeOnLAN.validate(draft.settings)) != nil
    }
}
