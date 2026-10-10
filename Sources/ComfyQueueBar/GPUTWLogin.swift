import AppKit
import SwiftUI
import WebKit

@MainActor
final class GPUTWLoginWindow: NSObject, ObservableObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    static let shared = GPUTWLoginWindow()
    @Published private(set) var service: URL?
    @Published private(set) var displayedHost = "gputw.ai"
    @Published private(set) var message: String?
    private var window: NSWindow?
    private var webView: WKWebView?
    private var onConnect: ((String) -> Void)?

    func open(address: String, onConnect: @escaping (String) -> Void) {
        self.onConnect = onConnect
        service = nil; message = nil
        let origin = URL(string: address).flatMap { GPUTWAddress.serviceOrigin($0) }
        // Reuse the sign-in window when checking a paired port; the address the
        // user asked to inspect must replace whichever service was open before.
        if let window {
            webView?.load(URLRequest(url: origin ?? GPUTWAddress.dashboard))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        browser.load(URLRequest(url: origin ?? GPUTWAddress.dashboard))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func openDashboard() { webView?.load(URLRequest(url: GPUTWAddress.dashboard)) }
    func goBack() { webView?.goBack() }

    func connect() {
        guard let service else { return }
        // The separate review card reads this exact service without changing monitoring.
        // Keep the browser available so Cancel lets the user choose another port.
        onConnect?(service.absoluteString)
    }

    func windowWillClose(_ notification: Notification) {
        webView?.stopLoading()
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil
        window?.contentViewController = nil
        webView = nil; window = nil; onConnect = nil; service = nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        service = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        displayedHost = webView.url?.host ?? ""
        service = webView.url.flatMap { GPUTWAddress.serviceOrigin($0) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
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
        if (error as NSError).code != NSURLErrorCancelled { message = L10n.text("Could not open GPUtw. Check your connection and try again.") }
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
                Button(L10n.text("Review this ComfyUI")) { controller.connect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.service == nil)
            }
            Text(L10n.text("Open your ComfyUI, then review its port and recent jobs before monitoring."))
                .font(.callout)
            if let message = controller.message { Text(message).font(.callout).foregroundStyle(.red) }
            GPUTWBrowser(browser: browser)
        }.padding(12)
    }
}
