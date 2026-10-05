import Foundation
import Darwin

struct WakeSettings: Codable, Equatable {
    var macAddress = ""
    var broadcastAddress = "255.255.255.255"
    var port: UInt16 = 9
    var automaticallyWake = false
}

enum WakeOnLAN {
    static func isOfflineError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost].contains(error.code)
    }

    static func canRetry(lastAttempt: Date?, now: Date) -> Bool {
        lastAttempt.map { now.timeIntervalSince($0) >= 120 } ?? true
    }

    static func packet(macAddress: String) throws -> [UInt8] {
        let parts = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: ":").split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isHexDigit } }) else {
            throw failure("Enter a valid MAC address (AA:BB:CC:DD:EE:FF).")
        }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), bytes[0] & 1 == 0 else {
            throw failure("Enter a valid MAC address (AA:BB:CC:DD:EE:FF).")
        }
        return Array(repeating: 0xff, count: 6) + (0..<16).flatMap { _ in bytes }
    }

    static func destination(_ settings: WakeSettings) throws -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = settings.port.bigEndian
        guard settings.port > 0, settings.broadcastAddress.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            throw failure("Enter a valid IPv4 destination and UDP port.")
        }
        return address
    }

    static func validate(_ settings: WakeSettings) throws {
        _ = try packet(macAddress: settings.macAddress)
        _ = try destination(settings)
    }

    static func send(_ settings: WakeSettings) throws {
        let bytes = try packet(macAddress: settings.macAddress)
        var address = try destination(settings)
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { throw systemError() }
        defer { close(socketFD) }
        var enabled: Int32 = 1
        guard setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw systemError() }
        let count = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { destination in
                bytes.withUnsafeBytes { buffer in
                    sendto(socketFD, buffer.baseAddress, buffer.count, 0, destination, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard count == bytes.count else { throw systemError() }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "WakeOnLAN", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func systemError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
