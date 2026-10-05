import Foundation
import Darwin

let expectedMAC: [UInt8] = [0x02, 0x11, 0x22, 0x33, 0x44, 0x55]
let packet = try WakeOnLAN.packet(macAddress: "02:11:22:33:44:55")
precondition(packet.count == 102)
precondition(Array(packet.prefix(6)) == Array(repeating: 0xff, count: 6))
for index in 0..<16 {
    precondition(Array(packet[(6 + index * 6)..<(12 + index * 6)]) == expectedMAC)
}
let dashedPacket = try WakeOnLAN.packet(macAddress: "02-11-22-33-44-55")
precondition(dashedPacket == packet)
for invalid in ["", "02:11:22:33:44", "GG:11:22:33:44:55", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "02::11:22:33:44:55"] {
    precondition((try? WakeOnLAN.packet(macAddress: invalid)) == nil)
}
var settings = WakeSettings(macAddress: "02:11:22:33:44:55", broadcastAddress: "127.0.0.1")
settings.port = 0
precondition((try? WakeOnLAN.validate(settings)) == nil)
settings.port = 9
settings.broadcastAddress = "bad.invalid"
precondition((try? WakeOnLAN.validate(settings)) == nil)

// Receive the real UDP payload locally; never send a wake broadcast in tests.
let receiver = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
precondition(receiver >= 0)
defer { close(receiver) }
var address = sockaddr_in()
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
address.sin_family = sa_family_t(AF_INET)
address.sin_addr.s_addr = inet_addr("127.0.0.1")
let bound = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(receiver, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}
precondition(bound == 0)
var length = socklen_t(MemoryLayout<sockaddr_in>.size)
precondition(withUnsafeMutablePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(receiver, $0, &length) }
} == 0)
var timeout = timeval(tv_sec: 2, tv_usec: 0)
precondition(setsockopt(receiver, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
settings.broadcastAddress = "127.0.0.1"
settings.port = UInt16(bigEndian: address.sin_port)
try WakeOnLAN.send(settings)
var received = [UInt8](repeating: 0, count: 1024)
let count = received.withUnsafeMutableBytes { recv(receiver, $0.baseAddress, $0.count, 0) }
precondition(count == packet.count)
precondition(Array(received.prefix(count)) == packet)
print("Wake-on-LAN packet validation and UDP delivery passed")

let now = Date()
precondition(WakeOnLAN.canRetry(lastAttempt: nil, now: now))
precondition(!WakeOnLAN.canRetry(lastAttempt: now.addingTimeInterval(-119), now: now))
precondition(WakeOnLAN.canRetry(lastAttempt: now.addingTimeInterval(-120), now: now))
precondition(WakeOnLAN.isOfflineError(URLError(.cannotConnectToHost)))
precondition(WakeOnLAN.isOfflineError(URLError(.timedOut)))
precondition(!WakeOnLAN.isOfflineError(URLError(.cancelled)))
precondition(!WakeOnLAN.isOfflineError(URLError(.notConnectedToInternet)))
precondition(!WakeOnLAN.isOfflineError(NSError(domain: "HTTP", code: 500)))
print("Automatic wake error filtering and retry interval passed")
