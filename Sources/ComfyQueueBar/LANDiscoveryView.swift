import SwiftUI

struct LANDiscoveryView: View {
    @ObservedObject var queue: QueueViewModel
    let select: (DiscoveredComfyServer) -> Void
    @StateObject private var discovery = LANDiscoveryModel()

    var body: some View {
        DisclosureGroup(L10n.text("Scan local network")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("Find ComfyUI on this Mac and nearby Wi-Fi or Ethernet devices."))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField(L10n.text("Ports (comma separated)"), text: $discovery.ports).textFieldStyle(.roundedBorder)
                        .disabled(discovery.scanning)
                    if discovery.scanning {
                        Button(L10n.text("Stop scan")) { discovery.cancel() }
                    } else {
                        Button(L10n.text("Scan")) { discovery.start(ports: discovery.ports) }
                    }
                }
                if discovery.invalidPorts {
                    Text(L10n.text("Enter up to 8 ports from 1 to 65535, separated by commas.")).foregroundStyle(.red)
                }
                if let plan = discovery.plan {
                    Text((["127.0.0.1"] + plan.ranges).joined(separator: " · "))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    if plan.limited {
                        Text(L10n.text("Large networks are limited to the nearby /22 range, up to 4096 LAN addresses. Enter other addresses manually."))
                            .foregroundStyle(.secondary)
                    }
                    if discovery.scanning {
                        ProgressView(value: Double(discovery.completed), total: Double(max(1, discovery.total)))
                        Text(L10n.text("Checked %@ / %@ addresses and ports", String(discovery.completed), String(discovery.total)))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.text(discovery.stopped ? "Scan stopped. Found %@ servers." : "Scan complete. Found %@ servers.", String(discovery.results.count)))
                    }
                    if !discovery.scanning && discovery.results.isEmpty {
                        Text(L10n.text("Check the port, firewall, and macOS Local Network permission. Start remote ComfyUI with --listen 0.0.0.0."))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(discovery.results) { server in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.endpoint).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        if let device = server.device { Text(device).foregroundStyle(.secondary).lineLimit(2) }
                        HStack {
                            Button(L10n.text("Review this ComfyUI")) { select(server) }.disabled(!queue.canChangeServer)
                            if queue.profiles.contains(where: { $0.endpoint == server.endpoint }) {
                                Label(L10n.text("Address saved"), systemImage: "checkmark").foregroundStyle(.secondary)
                            } else {
                                Button(L10n.text("Save address")) { queue.saveProfile(name: server.name, address: server.endpoint) }
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }.padding(.top, 6)
        }
        .font(.system(size: 11)).controlSize(.small)
        .onDisappear { discovery.cancel() }
    }
}
