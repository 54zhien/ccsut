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
    @State private var browser = CampusOfficialBrowser()

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: destination.title) { dismiss() }
            ZStack {
                WebPanel(webView: browser.webView)
                if browser.isLoading {
                    Color(.systemBackground)
                    ProgressView("正在打开官方页面…")
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

    override init() {
        generation = CookieJar.generation
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WebStore.dataStore
        configuration.userContentController.addUserScript(WKUserScript(
            source: CampusWebPrivacy.script, injectionTime: .atDocumentEnd,
            forMainFrameOnly: false, in: .defaultClient
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
            self.isLoading = true
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, self.current else { return }
            self.isLoading = false
            let store = self.webView.configuration.websiteDataStore.httpCookieStore
            guard let cookies = try? await store.cookieSnapshot(), self.current else { return }
            CookieJar.upsert(cookies.filter { ["ehall.ccsut.cn", "auth.ccsut.cn", ".ccsut.cn", "ccsut.cn"].contains($0.domain) }, generation: self.generation)
        }
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
