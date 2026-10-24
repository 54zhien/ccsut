import SwiftUI
import WebKit

enum CampusWebDestination: String, Identifiable {
    case leaveList, leaveForm, departure, returning
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leaveList: return "请假记录"
        case .leaveForm: return "申请请假"
        case .departure: return "离校登记"
        case .returning: return "返校登记"
        }
    }
    var url: URL {
        switch self {
        case .leaveList: return CampusClient.leavePage
        case .leaveForm: return CampusClient.leaveForm
        case .departure: return CampusTravelKind.departure.page
        case .returning: return CampusTravelKind.returning.page
        }
    }
}

@MainActor
struct CampusWebView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: CampusWebDestination
    @State private var browser: CampusOfficialBrowser

    init(destination: CampusWebDestination, account: String) {
        self.destination = destination
        _browser = State(initialValue: CampusOfficialBrowser(account: account))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: destination.title) { dismiss() }
            ZStack {
                WebPanel(webView: browser.webView)
                if browser.isLoading || browser.error != nil {
                    Color(.systemBackground)
                    if browser.isLoading { ProgressView("正在打开官方页面…") }
                    else { ContentUnavailableView("无法打开官方页面", systemImage: "exclamationmark.shield") }
                }
            }
            if let error = browser.error {
                PageStatusNotice(message: error) { Task { await browser.open(destination.url) } }
            }
        }
        .presentationDetents([.large])
        .task { await browser.open(destination.url) }
        .onDisappear { browser.stop() }
    }
}

@Observable @MainActor
private final class CampusOfficialBrowser: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var isLoading = true
    private(set) var error: String?
    private let generation: UInt64
    private var active = true
    private var navigationRevision: UInt64 = 0
    private var destination: URL?
    private let handoff: CampusOfficialCookieHandoff

    init(account: String) {
        generation = CookieJar.generation
        handoff = CampusOfficialCookieHandoff(account: account, credentials: CampusCookieCredentials())
        let configuration = WKWebViewConfiguration()
        // A login inside an official form must not silently replace the App's identity.
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: CampusWebPrivacy.script, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: .page
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.customUserAgent = UserAgent.mobile
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func open(_ url: URL) async {
        guard current else { return }
        isLoading = true
        error = nil
        destination = url
        do {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in CookieJar.shared where ["ehall.ccsut.cn", "auth.ccsut.cn", ".ccsut.cn", "ccsut.cn"].contains(cookie.domain) {
                try Task.checkCancellation()
                guard current else { return }
                try await store.set(cookie)
            }
            try Task.checkCancellation()
            guard current else { return }
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        } catch is CancellationError { return }
        catch { failed() }
    }

    func stop() { active = false; webView.stopLoading() }
    private var current: Bool { active && CookieJar.generation == generation }
    private func failed() {
        guard current else { return }
        isLoading = false
        error = "官方页面暂时无法打开，请重试"
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        guard ["ehall.ccsut.cn", "auth.ccsut.cn"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil else {
            decisionHandler(.cancel)
            Task { @MainActor [weak self] in self?.failed() }
            return
        }
        if url.scheme == "http" {
            decisionHandler(.cancel)
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            let upgraded = components?.url
            Task { @MainActor [weak self] in
                guard let self, self.current, let upgraded else { return }
                self.webView.load(URLRequest(url: upgraded))
            }
        } else { decisionHandler(url.scheme == "https" ? .allow : .cancel) }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, self.current else { return }
            self.navigationRevision &+= 1
            self.isLoading = true
            self.error = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, self.current else { return }
            if self.webView.url?.host == "auth.ccsut.cn" {
                self.isLoading = false
                return
            }
            guard self.webView.url?.host == "ehall.ccsut.cn" else { self.failed(); return }
            let revision = self.navigationRevision
            do {
                for _ in 0..<8 {
                    guard self.current, revision == self.navigationRevision else { return }
                    if let proof = try await self.identityProof() {
                        do {
                            try self.handoff.accept(identity: proof, cookies: [])
                            let cookies = try await self.webView.configuration.websiteDataStore.httpCookieStore.cookieSnapshot()
                            guard self.current, revision == self.navigationRevision else { return }
                            try self.handoff.accept(identity: proof, cookies: cookies)
                            self.isLoading = false
                            return
                        } catch CampusError.authentication { /* Wait for the official SPA's CAS bootstrap. */ }
                    }
                    try await Task.sleep(for: .milliseconds(500))
                }
                throw CampusError.authentication
            } catch {
                guard self.current, revision == self.navigationRevision else { return }
                self.isLoading = false
                self.error = (error as? CampusError ?? .serviceUnavailable).localizedDescription
            }
        }
    }

    private func identityProof() async throws -> Data? {
        let script = """
        if (location.hostname !== 'ehall.ccsut.cn') return null;
        const url = new URL('/backstage/cas-proxy/app/validate_full', location.origin);
        url.searchParams.set('callback', callback);
        url.searchParams.set('timestamp', String(Date.now()));
        const response = await fetch(url, {credentials:'include', cache:'no-store'});
        if (!response.ok) return null;
        const value = await response.json();
        return JSON.stringify({errcode:value?.errcode, account:value?.account});
        """
        let json: String? = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            webView.callAsyncJavaScript(script, arguments: ["callback": destination?.absoluteString ?? CampusClient.leavePage.absoluteString],
                                        in: nil, in: .defaultClient) { result in
                continuation.resume(with: result.map { $0 as? String })
            }
        }
        return json.map { Data($0.utf8) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor [weak self] in self?.failed() }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor [weak self] in self?.failed() }
    }
}

#if DEBUG
/// A local HTML fixture tests the actual WebKit content-world boundary without school requests.
struct CampusPrivacyPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: CampusWebPrivacy.script, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: .page
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body><p id="split"><span>180</span><span>0000</span><span>0000</span></p>
        <input id="contact" name="contactValue" aria-label="联系号码">
        <p id="result">正在检查网页隐私</p>
        <script>
        const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        setTimeout(() => {
          const field = document.getElementById('contact');
          setter.call(field, '18000000000');
          const protected = field.type === 'password' && getComputedStyle(field).webkitTextSecurity === 'disc'
            && field.value === '18000000000' && !document.getElementById('split').textContent.includes('18000000000');
          document.getElementById('result').textContent = protected ? '网页隐私检查通过' : '网页隐私检查失败';
        }, 300);
        </script></body></html>
        """, baseURL: URL(string: "https://ehall.ccsut.cn"))
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
