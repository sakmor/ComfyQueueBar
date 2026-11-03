import AppKit
import SwiftUI
import WebKit

@MainActor
final class GPUTWPortRecovery: ObservableObject {
    @Published private(set) var endpoint: String?
    @Published private(set) var checking = false
    @Published private(set) var issue: PairedPortIssue?
    @Published private(set) var error: String?
    @Published private(set) var settingUp = false
    @Published var apiKey = ""
    private var revision = UUID()
    private let inspect: (String) async throws -> Void

    var browserURL: URL { endpoint.flatMap(URL.init(string:)) ?? GPUTWAddress.dashboard }

    init(inspect: @escaping (String) async throws -> Void = { address in
        _ = try await ConnectionInspector.inspectQueue(address, timeout: 8)
    }) {
        self.inspect = inspect
    }

    func prepare(_ address: String?) {
        revision = UUID()
        endpoint = address.flatMap(URL.init(string:)).flatMap(GPUTWAddress.serviceOrigin)?.absoluteString
        checking = false; settingUp = false; issue = nil; error = nil; apiKey = ""
    }

    func setup(using connector: GPUTWPortConnector) async -> URL? {
        guard let endpoint, let origin = URL(string: endpoint), !settingUp, !checking, !Task.isCancelled else { return nil }
        let token = revision
        settingUp = true; issue = nil; error = nil
        let key = apiKey
        apiKey = ""
        defer { if revision == token { settingUp = false } }
        do {
            let handoff = try await connector.prepareAccess(to: origin, apiKey: key)
            guard revision == token, !Task.isCancelled else { return nil }
            return handoff
        } catch {
            guard revision == token, !Task.isCancelled else { return nil }
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Returns only the exact requested origin after a valid queue response.
    /// Opening a browser page or receiving HTTP 200 alone is not verification.
    func recheck() async -> String? {
        guard let endpoint, !checking, !Task.isCancelled else { return nil }
        let token = revision
        checking = true; issue = nil; error = nil
        defer { if revision == token { checking = false } }
        do {
            try await inspect(endpoint)
            guard revision == token, !Task.isCancelled else { return nil }
            return endpoint
        } catch {
            guard revision == token, !Task.isCancelled else { return nil }
            issue = PairedPortIssue.classify(error)
            self.error = error.localizedDescription
            return nil
        }
    }
}

@MainActor
final class GPUTWLoginWindow: NSObject, ObservableObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    static let shared = GPUTWLoginWindow()
    @Published private(set) var service: URL?
    @Published private(set) var displayedHost = "gputw.ai"
    @Published private(set) var message: String?
    @Published private(set) var dashboardNotice: String?
    @Published private(set) var connectingPort = false
    private var window: NSWindow?
    private var webView: WKWebView?
    private var onConnect: ((String) -> Void)?
    private var onConnected: ((String) -> Void)?
    let recovery: GPUTWPortRecovery
    private var recoveryTask: Task<Void, Never>?
    private let connector = GPUTWPortConnector()
    private var automaticEndpoint: String?
    private var awaitingHandoff = false

    init(recovery: GPUTWPortRecovery? = nil) {
        self.recovery = recovery ?? GPUTWPortRecovery()
        super.init()
    }

    func open(recoveryAddress: String? = nil, onConnected: ((String) -> Void)? = nil,
              onConnect: @escaping (String) -> Void) {
        resetRecovery()
        recovery.prepare(recoveryAddress)
        self.onConnect = onConnect
        self.onConnected = onConnected
        service = nil; message = nil; dashboardNotice = nil
        // Sign-in always starts at the dashboard. Only an explicit port recovery
        // may open a saved service; it must never replay a one-time handoff URL.
        let destination = recovery.browserURL
        displayedHost = destination.host ?? "gputw.ai"
        // Reuse the sign-in window when checking a paired port; the address the
        // user asked to inspect must replace whichever service was open before.
        if let window {
            webView?.load(URLRequest(url: destination))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            connectPreparedPort()
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self
        browser.uiDelegate = self
        webView = browser
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.text("GPUtw sign-in")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 560)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: GPUTWLoginView(controller: self, browser: browser))
        self.window = window
        // Do not replay a pasted one-time handoff token; the dashboard issues a new one.
        browser.load(URLRequest(url: destination))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        connectPreparedPort()
    }

    private func resetRecovery(keepingTarget: Bool = false) {
        recoveryTask?.cancel(); recoveryTask = nil
        automaticEndpoint = nil; awaitingHandoff = false; connectingPort = false
        if keepingTarget { recovery.apiKey = "" }
        else { recovery.prepare(nil) }
    }

    func openDashboard() { showDashboard(notice: nil) }

    private func showDashboard(notice: String?, keepingTarget: Bool = false) {
        resetRecovery(keepingTarget: keepingTarget)
        service = nil; message = nil; dashboardNotice = notice
        displayedHost = GPUTWAddress.dashboard.host ?? "gputw.ai"
        webView?.load(URLRequest(url: GPUTWAddress.dashboard))
    }
    func goBack() { webView?.goBack() }

    @discardableResult
    func connectPreparedPort() -> Task<Void, Never>? {
        guard let target = recovery.endpoint else { return nil }
        automaticEndpoint = target
        // An existing HTTP route/session needs no management key or settings change.
        recheckPort()
        return recoveryTask
    }

    func recheckPort() {
        guard recoveryTask == nil else { return }
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            let verified = await recovery.recheck()
            guard !Task.isCancelled else { return }
            recoveryTask = nil
            if let verified {
                if automaticEndpoint == verified { finishConnecting(verified) }
                else { onConnect?(verified) }
            } else if automaticEndpoint != nil, recovery.issue == .notFound {
                let port = ConnectionAddress.port(recovery.endpoint ?? "")
                showDashboard(notice: L10n.text("GPUtw port %@ returned 404. This instance may have stopped or changed, or its HTTP port may be unavailable. Select a running instance in the dashboard and open its ComfyUI.", port), keepingTarget: true)
            } else if automaticEndpoint != nil, recovery.issue == .signInRequired {
                showDashboard(notice: L10n.text("Sign in to GPUtw again, then open your ComfyUI Web UI."), keepingTarget: true)
            }
        }
    }

    func choose8090() {
        guard !connectingPort, let service,
              let target = GPUTWAddress.serviceOrigin(service, port: 8090) else { return }
        recoveryTask?.cancel(); recoveryTask = nil
        automaticEndpoint = nil; awaitingHandoff = false
        dashboardNotice = nil
        recovery.prepare(target.absoluteString)
        connectPreparedPort()
    }

    func setupAndConnect() {
        guard recoveryTask == nil, !connectingPort else { return }
        connectingPort = true; message = L10n.text("Setting up HTTP access…")
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            let handoff = await recovery.setup(using: connector)
            guard !Task.isCancelled else { return }
            recoveryTask = nil
            guard let handoff else { connectingPort = false; message = nil; return }
            automaticEndpoint = recovery.endpoint
            awaitingHandoff = true
            message = L10n.text("Signing in to the target port…")
            // This request contains only the short-lived service handoff, never the API key.
            webView?.load(URLRequest(url: handoff))
        }
    }

    private func verifyAutomaticConnection() {
        guard recoveryTask == nil, let target = automaticEndpoint else { return }
        message = L10n.text("Waiting for ComfyUI on Port %@…", ConnectionAddress.port(target))
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            // HTTP routes can take a few seconds to become active after enabling.
            for attempt in 0..<5 {
                if let verified = await recovery.recheck() {
                    guard !Task.isCancelled else { return }
                    recoveryTask = nil
                    finishConnecting(verified)
                    return
                }
                guard !Task.isCancelled else { return }
                if recovery.issue == .signInRequired { break }
                if attempt < 4 {
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                    catch { return }
                }
            }
            recoveryTask = nil; connectingPort = false
            message = L10n.text("HTTP access is ready. Complete any password page, or start ComfyUI on this port, then retry the connection.")
        }
    }

    private func finishConnecting(_ endpoint: String) {
        automaticEndpoint = nil; awaitingHandoff = false; connectingPort = false; message = nil
        (onConnected ?? onConnect)?(endpoint)
    }

    func connect() {
        guard let service else { return }
        // The separate review card reads this exact service without changing monitoring.
        // Keep the browser available so Cancel lets the user choose another port.
        onConnect?(service.absoluteString)
    }

    func windowWillClose(_ notification: Notification) {
        resetRecovery()
        dashboardNotice = nil; onConnected = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil
        window?.contentViewController = nil
        webView = nil; window = nil; onConnect = nil; service = nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        service = nil
        if !connectingPort { message = nil }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishedNavigation(to: webView.url)
    }

    func prepareNavigation(to url: URL?) {
        guard let destination = url.flatMap(GPUTWAddress.serviceOrigin),
              let endpoint = recovery.endpoint, destination.absoluteString != endpoint else { return }
        // Cancel before the new page loads, so the old request cannot close the
        // browser and connect its instance while the user is choosing a new one.
        resetRecovery()
        service = nil; message = nil; dashboardNotice = nil
    }

    func finishedNavigation(to url: URL?) {
        prepareNavigation(to: url)
        displayedHost = url?.host ?? ""
        service = url.flatMap { GPUTWAddress.serviceOrigin($0) }
        if service != nil { dashboardNotice = nil }
        if awaitingHandoff, let target = automaticEndpoint {
            if service?.absoluteString == target { verifyAutomaticConnection() }
            else {
                connectingPort = false
                message = L10n.text("Complete GPUtw sign-in in this window, then retry the connection.")
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        if navigationAction.targetFrame?.isMainFrame == true { prepareNavigation(to: url) }
        // HTTPS identity-provider redirects are allowed in the visible login browser.
        // Native monitoring requests use a separate session that refuses redirects.
        // Embedded login widgets need both about:blank and about:srcdoc frames.
        // https://developers.cloudflare.com/turnstile/get-started/mobile-implementation/
        let localFrame = ["about:blank", "about:srcdoc"].contains(url?.absoluteString ?? "")
        decisionHandler(url?.scheme == "https" || localFrame ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // The dashboard's Web UI handoff opens a new window. Keep it in this browser
        // so the resulting instance session remains in the app's cookie store.
        if navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    private func navigationFailed(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            connectingPort = false
            message = L10n.text("Could not open GPUtw. Check your connection and try again.")
        }
    }

    func close() { window?.close() }
}

private struct GPUTWBrowser: NSViewRepresentable {
    let browser: WKWebView
    func makeNSView(context: Context) -> WKWebView { browser }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct GPUTWLoginView: View {
    @ObservedObject var controller: GPUTWLoginWindow
    let browser: WKWebView
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(L10n.text("Back")) { controller.goBack() }
                Button(L10n.text("GPUtw dashboard")) { controller.openDashboard() }
                Text(controller.displayedHost).font(.system(.caption, design: .monospaced)).lineLimit(1)
                Spacer()
                if controller.service != nil {
                    Button(L10n.text("Connect Port 8090…")) { controller.choose8090() }
                        .disabled(controller.connectingPort)
                }
                Button(L10n.text("Review this ComfyUI")) { controller.connect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.service == nil || controller.connectingPort)
            }
            Text(L10n.text("Sign in, select a running GPUtw instance, and open its ComfyUI. Review the port and recent jobs before monitoring."))
                .font(.callout)
            if let notice = controller.dashboardNotice {
                Text(notice).font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GPUTWPortRecoveryView(recovery: controller.recovery, connecting: controller.connectingPort,
                                 setup: controller.setupAndConnect, recheck: controller.recheckPort,
                                 dashboard: controller.openDashboard, showIssue: controller.dashboardNotice == nil)
            if let message = controller.message { Text(message).font(.callout).foregroundStyle(.red) }
            GPUTWBrowser(browser: browser)
        }.padding(12)
    }
}

private struct GPUTWPortRecoveryView: View {
    @ObservedObject var recovery: GPUTWPortRecovery
    let connecting: Bool
    let setup: () -> Void
    let recheck: () -> Void
    let dashboard: () -> Void
    let showIssue: Bool

    var body: some View {
        if let endpoint = recovery.endpoint {
            let port = ConnectionAddress.port(endpoint)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.text("Connect Port %@", port)).font(.headline)
                    Spacer()
                    Button(L10n.text("Copy port")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(port, forType: .string)
                    }
                    if recovery.checking || connecting { ProgressView().controlSize(.small) }
                }
                Text(endpoint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L10n.text("Choose a running GPUtw instance"), action: dashboard)
                        .buttonStyle(.borderedProminent)
                    Button(L10n.text("Retry connection"), action: recheck)
                        .disabled(connecting || recovery.settingUp || recovery.checking)
                }
                Text(L10n.text("Open ComfyUI from the dashboard to connect without an API key. If you changed instances, select the new one."))
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup(L10n.text("Advanced: enable an HTTP port with an API key")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("The app enables this HTTP port if needed, signs in, and starts monitoring when ComfyUI responds."))
                        SecureField(L10n.text("GPUtw API key"), text: $recovery.apiKey)
                            .textFieldStyle(.roundedBorder).disabled(connecting || recovery.settingUp)
                        Button(L10n.text("Enable and connect Port %@", port), action: setup)
                            .buttonStyle(.borderedProminent)
                            .disabled(connecting || recovery.settingUp || recovery.checking || recovery.apiKey.isEmpty)
                        Text(L10n.text("Requires instances:read and ports:manage. The key is used once and is not saved. Additional ports may incur GPUtw fees."))
                            .font(.caption).foregroundStyle(.secondary)
                        Link(L10n.text("API key setup"), destination: URL(string: "https://docs.gputw.ai/zh-TW/docs/api-keys")!)
                            .font(.caption)
                    }
                }
                DisclosureGroup(L10n.text("Connect manually without an API key")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("1. Select the instance matching this address and confirm it is running with ComfyUI started."))
                        Text(L10n.text("2. In Network Ports, confirm port %@ is enabled as HTTP.", port))
                        Text(L10n.text("3. Open port %@ from Other ports in this window, complete any sign-in, then recheck.", port))
                    }
                }
                if showIssue, let issue = recovery.issue {
                    Text(recoveryMessage(issue, port: port)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if recovery.issue == nil, let error = recovery.error {
                    Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func recoveryMessage(_ issue: PairedPortIssue, port: String) -> String {
        switch issue {
        case .notFound:
            return L10n.text("GPUtw port %@ returned 404. This instance may have stopped or changed, or its HTTP port may be unavailable. Select a running instance in the dashboard and open its ComfyUI.", port)
        case .signInRequired:
            return L10n.text("Port %@ needs an owner session. Open it from the GPUtw dashboard's Other ports menu.", port)
        case .unavailable:
            return recovery.error ?? L10n.text("Could not check GPUtw port %@. Check your connection and retry.", port)
        }
    }
}
