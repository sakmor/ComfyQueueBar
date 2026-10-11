import Combine
import Darwin
import Foundation

struct LANSubnet: Equatable {
    let address: UInt32
    let mask: UInt32

    static func ipv4(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let byte = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    static func text(_ address: UInt32) -> String {
        [24, 16, 8, 0].map { String((address >> $0) & 255) }.joined(separator: ".")
    }

    var isPrivate: Bool {
        address >> 24 == 10 || address >> 20 == 0xAC1 || address >> 16 == 0xC0A8 || address >> 16 == 0xA9FE
    }

    var prefix: Int? {
        let inverse = ~mask
        guard inverse & (inverse &+ 1) == 0 else { return nil }
        return mask.nonzeroBitCount
    }

    // Bound large LANs to the /22 containing this Mac. The UI reports the limit.
    var scanPrefix: Int { max(prefix ?? 32, 22) }
    var isLimited: Bool { (prefix ?? 32) < scanPrefix }
    var scanMask: UInt32 { scanPrefix == 0 ? 0 : UInt32.max << (32 - scanPrefix) }
    var rangeLabel: String { Self.text(address & scanMask) + "/" + String(scanPrefix) }
    var hosts: [UInt32] {
        guard isPrivate, prefix != nil else { return [] }
        let first = address & scanMask
        let last = first | ~scanMask
        // Clipped range boundaries can be valid hosts in the original larger subnet.
        if scanPrefix >= 31 || isLimited { return Array(first...last) }
        return Array((first + 1)..<last)
    }

    static func active() -> [LANSubnet] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [LANSubnet] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let interface = entry.pointee
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  flags & (IFF_LOOPBACK | IFF_POINTOPOINT) == 0,
                  let address = interface.ifa_addr, let mask = interface.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            let netmask = UnsafeRawPointer(mask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            let subnet = LANSubnet(address: UInt32(bigEndian: ip), mask: UInt32(bigEndian: netmask))
            if subnet.isPrivate, subnet.prefix != nil, !result.contains(subnet) { result.append(subnet) }
        }
        return result.sorted { $0.address < $1.address }
    }
}

enum LANDiscoveryError: Error { case invalidPorts }

struct LANScanPlan {
    let hosts: [UInt32]
    let ranges: [String]
    let limited: Bool

    init(subnets: [LANSubnet]) {
        let valid = subnets.filter { $0.isPrivate && $0.prefix != nil }
        // Limit multiple interfaces too; always keep loopback and each interface address.
        var lanHosts = Set(valid.map(\.address).prefix(4096))
        var capped = valid.count > 4096
        for host in valid.flatMap(\.hosts) where !lanHosts.contains(host) {
            if lanHosts.count < 4096 { lanHosts.insert(host) }
            else { capped = true }
        }
        hosts = (lanHosts.union([UInt32(0x7F000001)])).sorted()
        ranges = Array(Set(valid.map(\.rangeLabel))).sorted()
        limited = valid.contains(where: \.isLimited) || capped
    }

    static func ports(_ text: String) throws -> [Int] {
        let values = text.split(separator: ",", omittingEmptySubsequences: false)
        guard !values.isEmpty, values.count <= 8 else { throw LANDiscoveryError.invalidPorts }
        var ports: [Int] = []
        for value in values {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let port = Int(text), (1...65535).contains(port) else { throw LANDiscoveryError.invalidPorts }
            if !ports.contains(port) { ports.append(port) }
        }
        return ports
    }

    func endpoints(ports: [Int]) -> [String] {
        hosts.flatMap { host in ports.map { "http://" + LANSubnet.text(host) + ":" + String($0) } }
    }
}

struct DiscoveredComfyServer: Identifiable, Equatable {
    let endpoint: String
    let device: String?
    let version: String?
    var id: String { endpoint }
    var name: String { "ComfyUI · " + (URL(string: endpoint)?.host ?? endpoint) + ":" + String(URL(string: endpoint)?.port ?? 8188) }

    static func parse(_ data: Data, endpoint: String) -> Self? {
        guard data.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let system = object["system"] as? [String: Any],
              system["os"] is String, system["python_version"] is String,
              let devices = object["devices"] as? [[String: Any]] else { return nil }
        return Self(endpoint: endpoint, device: (devices.first?["name"] as? String).map { String($0.prefix(160)) },
                    version: (system["comfyui_version"] as? String).map { String($0.prefix(80)) })
    }
}

private final class LANProbeDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum LANDiscovery {
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.connectionProxyDictionary = [:]
        return config
    }

    static func scan(endpoints: [String], configuration: URLSessionConfiguration = configuration(), concurrency: Int = 48,
                     onResult: @Sendable (DiscoveredComfyServer?) async -> Void) async {
        let session = URLSession(configuration: configuration, delegate: LANProbeDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        await withTaskGroup(of: DiscoveredComfyServer?.self) { group in
            var next = 0
            func enqueue() {
                guard next < endpoints.count, !Task.isCancelled else { return }
                let endpoint = endpoints[next]
                next += 1
                group.addTask {
                    guard !Task.isCancelled, let url = URL(string: endpoint + "/system_stats") else { return nil }
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    do {
                        let (data, response) = try await session.data(for: request)
                        guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                        return DiscoveredComfyServer.parse(data, endpoint: endpoint)
                    } catch { return nil }
                }
            }
            for _ in 0..<min(max(1, concurrency), endpoints.count) { enqueue() }
            for await result in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                await onResult(result)
                enqueue()
            }
        }
    }
}

@MainActor
final class LANDiscoveryModel: ObservableObject {
    @Published var ports = "8188, 8000"
    @Published private(set) var results: [DiscoveredComfyServer] = []
    @Published private(set) var scanning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var plan: LANScanPlan?
    @Published private(set) var invalidPorts = false
    @Published private(set) var stopped = false
    private var task: Task<Void, Never>?
    private var revision = UUID()

    func start(ports text: String, subnets: [LANSubnet]? = nil, configuration: URLSessionConfiguration? = nil) {
        let ports: [Int]
        do { ports = try LANScanPlan.ports(text) }
        catch { invalidPorts = true; return }
        cancel()
        invalidPorts = false; stopped = false; results = []; completed = 0
        let plan = LANScanPlan(subnets: subnets ?? LANSubnet.active())
        self.plan = plan
        let endpoints = plan.endpoints(ports: ports)
        total = endpoints.count; scanning = true
        let token = revision
        task = Task { [weak self] in
            await LANDiscovery.scan(endpoints: endpoints, configuration: configuration ?? LANDiscovery.configuration()) { [weak self] result in
                await self?.record(result, token: token)
            }
            guard let self, !Task.isCancelled, self.revision == token else { return }
            self.scanning = false; self.task = nil
        }
    }

    private func record(_ result: DiscoveredComfyServer?, token: UUID) {
        guard revision == token, scanning else { return }
        completed += 1
        if let result, !results.contains(where: { $0.id == result.id }) {
            results.append(result)
            results.sort { $0.endpoint.localizedStandardCompare($1.endpoint) == .orderedAscending }
        }
    }

    func cancel() {
        revision = UUID()
        task?.cancel(); task = nil
        if scanning { stopped = true }
        scanning = false
    }

    deinit { task?.cancel() }
}
