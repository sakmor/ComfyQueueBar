import Foundation

private let stats = Data(#"{"system":{"os":"linux","python_version":"3.12","comfyui_version":"test"},"devices":[{"name":"Fixture GPU"}]}"#.utf8)

final class LANFixture: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var active = 0
    static var peak = 0
    private var finished = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request); Self.active += 1; Self.peak = max(Self.peak, Self.active)
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + (self.request.url?.port == 8188 ? 0.15 : 0.02)) { [self] in
            Self.lock.lock()
            guard !finished else { Self.lock.unlock(); return }
            finished = true; Self.active -= 1
            Self.lock.unlock()
            let port = request.url!.port!
            let status = port == 8002 ? 401 : 200
            let body = port == 8001 ? Data("<html>Other service</html>".utf8) : stats
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if !finished { finished = true; Self.active -= 1 }
    }
}

actor ScanResults {
    var calls = 0
    var found: [DiscoveredComfyServer] = []
    func record(_ server: DiscoveredComfyServer?) { calls += 1; if let server { found.append(server) } }
}

@main
struct LANChecks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--probe" {
            await LANDiscovery.scan(endpoints: Array(CommandLine.arguments.dropFirst(2))) { result in
                if let result { print(result.endpoint) }
            }
            return
        }
        func subnet(_ ip: String, _ mask: String) -> LANSubnet {
            LANSubnet(address: LANSubnet.ipv4(ip)!, mask: LANSubnet.ipv4(mask)!)
        }
        for invalid in ["1.2.3", "256.0.0.1", "1.2.3.-1", "1..2.3", "１.2.3.4"] { precondition(LANSubnet.ipv4(invalid) == nil) }
        let normal = subnet("192.168.4.12", "255.255.255.0")
        precondition(normal.prefix == 24 && normal.hosts.count == 254)
        precondition(normal.rangeLabel == "192.168.4.0/24")
        precondition(!normal.hosts.contains(LANSubnet.ipv4("192.168.4.255")!))
        precondition(!normal.hosts.contains(LANSubnet.ipv4("192.168.4.0")!))
        let small = subnet("10.3.4.5", "255.255.255.252")
        precondition(small.hosts.map(LANSubnet.text) == ["10.3.4.5", "10.3.4.6"])
        precondition(subnet("10.3.4.5", "255.255.255.254").hosts.count == 2)
        precondition(subnet("10.3.4.5", "255.255.255.255").hosts.count == 1)
        let large = subnet("10.3.6.5", "255.0.0.0")
        precondition(large.hosts.count == 1024 && large.rangeLabel == "10.3.4.0/22" && large.isLimited)
        for ip in ["172.16.2.3", "172.31.255.1", "169.254.1.1"] { precondition(subnet(ip, "255.255.255.0").isPrivate) }
        for ip in ["172.15.2.3", "172.32.2.3", "8.8.8.8", "127.0.0.1"] { precondition(subnet(ip, "255.255.255.0").hosts.isEmpty) }
        precondition(subnet("10.0.0.1", "255.0.255.0").hosts.isEmpty)
        let plan = LANScanPlan(subnets: [normal, normal, small, subnet("8.8.8.8", "255.255.255.0")])
        precondition(plan.hosts.count == 257 && plan.ranges.count == 2 && !plan.limited)
        precondition(plan.endpoints(ports: [8188, 8000]).count == 514)
        let capped = LANScanPlan(subnets: (0..<8).map { subnet("10.\($0).0.1", "255.255.0.0") })
        precondition(capped.limited && capped.hosts.count == 4097)
        let ports = try LANScanPlan.ports("8188, 8000,8188")
        precondition(ports == [8188, 8000])
        for invalid in ["", "0", "65536", "8188,", "8.0", "-1", "１", "1,2,3,4,5,6,7,8,9"] {
            do { _ = try LANScanPlan.ports(invalid); preconditionFailure("Invalid ports accepted") }
            catch LANDiscoveryError.invalidPorts {}
        }
        precondition(DiscoveredComfyServer.parse(stats, endpoint: "http://fixture:8188")?.device == "Fixture GPU")
        for bad in ["{}", "<html>ComfyUI</html>", #"{"system":{"os":"linux"},"devices":[]}"#] {
            precondition(DiscoveredComfyServer.parse(Data(bad.utf8), endpoint: "http://fixture:8188") == nil)
        }
        print("PASS: subnet masks, private ranges, limits, deduplication, ports and ComfyUI identification")

        let config = LANDiscovery.configuration()
        precondition(config.httpCookieStorage == nil && config.urlCredentialStorage == nil && config.urlCache == nil)
        config.protocolClasses = [LANFixture.self]
        let results = ScanResults()
        let endpoints = (0..<20).map { "http://192.0.2.\($0 + 1):8000" } + ["http://192.0.2.30:8001", "http://192.0.2.30:8002"]
        await LANDiscovery.scan(endpoints: endpoints, configuration: config, concurrency: 3) { await results.record($0) }
        let count = await results.calls
        let found = await results.found
        precondition(count == 22 && found.count == 20 && LANFixture.peak <= 3)
        for request in LANFixture.requests {
            precondition(request.httpMethod == "GET" && request.url?.path == "/system_stats")
            precondition(request.value(forHTTPHeaderField: "Cookie") == nil && request.value(forHTTPHeaderField: "Authorization") == nil)
            precondition(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }
        print("PASS: bounded concurrent read-only probes, HTML/auth rejection and isolated transport")

        let cancelled = ScanResults()
        let scan = Task { await LANDiscovery.scan(endpoints: endpoints, configuration: config, concurrency: 2) { await cancelled.record($0) } }
        try await Task.sleep(nanoseconds: 5_000_000)
        scan.cancel(); await scan.value
        let cancelledCalls = await cancelled.calls
        precondition(cancelledCalls == 0)

        let model = LANDiscoveryModel()
        model.start(ports: "8188", subnets: [], configuration: config)
        try await Task.sleep(nanoseconds: 5_000_000)
        model.start(ports: "8000", subnets: [], configuration: config)
        while model.scanning { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(model.completed == 1 && model.results.map(\.endpoint) == ["http://127.0.0.1:8000"])
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(model.completed == 1 && model.results.count == 1)
        model.start(ports: "8188", subnets: [], configuration: config)
        model.cancel()
        precondition(model.stopped && !model.scanning)
        model.start(ports: "bad", subnets: [], configuration: config)
        precondition(model.invalidPorts && !model.scanning)
        print("PASS: cancellation and restart discard old results; invalid input makes no requests")
    }
}
