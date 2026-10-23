//
//  WebPanel.swift
//  CCSUT
//
//  WKWebView 的 SwiftUI 容器
//
//  为什么不用 iOS 26 的 WebView(page)：
//    实测在 if/else 两个分支间切换时（1×1 ↔ 全屏），同一个 WebPage
//    会被两个 WebView 实例争用，直接闪退。
//    WKWebView + UIViewRepresentable 是十年验证过的方案，行为确定。
//
//  另外：WKWebView 只要挂在视图层级里就会正常加载，
//  不需要靠"可见"来驱动；但不能 alpha = 0 或 frame = 0，
//  WebKit 会判定不可见并停止导航。
//

import SwiftUI
import WebKit
import OSLog

// MARK: - 容器

struct WebPanel: UIViewRepresentable {
    let webView: WKWebView
    var onRefresh: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        if let onRefresh {
            let coordinator = context.coordinator
            coordinator.onRefresh = onRefresh
            coordinator.control.addTarget(coordinator, action: #selector(Coordinator.refresh), for: .valueChanged)
            webView.scrollView.refreshControl = coordinator.control
            webView.scrollView.alwaysBounceVertical = true
            coordinator.observation = webView.observe(\.isLoading, options: [.new]) { [weak coordinator] _, change in
                guard change.newValue == false else { return }
                Task { @MainActor in coordinator?.control.endRefreshing() }
            }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onRefresh = onRefresh
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        if uiView.scrollView.refreshControl === coordinator.control {
            uiView.scrollView.refreshControl = nil
        }
        coordinator.observation?.invalidate()
    }

    final class Coordinator: NSObject {
        let control = UIRefreshControl()
        var onRefresh: (() -> Void)?
        var observation: NSKeyValueObservation?
        @objc func refresh() { onRefresh?() }
    }
}

// MARK: - 工厂

enum WebFactory {
    /// 用共享的 Cookie 仓库造一个 WKWebView
    static func make(delegate: WKNavigationDelegate? = nil) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WebStore.dataStore
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.customUserAgent = UserAgent.mobile
        wv.navigationDelegate = delegate
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.keyboardDismissMode = .interactive
        // 不要设 isOpaque = false / alpha = 0，会让 WebKit 停下加载
        return wv
    }
}

// MARK: - 导航观察

/// WKWebView 没有可观察的 url 属性，靠 delegate 把变化推出来
@Observable
@MainActor
final class WebNavigator: NSObject, WKNavigationDelegate {
    /// 每次 didFinish / didCommit 都会更新，UI 用 onChange 观察它
    private(set) var currentURL: URL?
    private(set) var lastError: String?
    private(set) var isFinished = false
    private static let logger = Logger(subsystem: "com.imzhien.ccsut", category: "WebLogin")

    /// 外部注入的处理逻辑
    var onNavigate: ((URL) -> Void)?
    var onFailure: ((String) -> Void)?

    func loadLoginPage(in webView: WKWebView) {
        lastError = nil
        isFinished = false
        webView.navigationDelegate = self
        webView.load(URLRequest(url: SessionStore.casLoginURL,
                                cachePolicy: .reloadIgnoringLocalCacheData,
                                timeoutInterval: 30))
    }

    /// Reparenting a failed/empty web view does not start a new navigation.
    /// Preserve a live authentication page, but recover an initial failed load.
    func recoverLoginPageIfNeeded(in webView: WKWebView) {
        guard !webView.isLoading else { return }
        if lastError != nil || !isFinished || webView.url == nil {
            loadLoginPage(in: webView)
        }
    }

    func refresh(in webView: WKWebView) {
        if lastError != nil || !isFinished || webView.url == nil {
            loadLoginPage(in: webView)
        } else {
            lastError = nil
            isFinished = false
            if webView.reloadFromOrigin() == nil { loadLoginPage(in: webView) }
        }
    }

    private func recordFailure(_ error: Error) {
        let underlying = error as NSError
        guard underlying.domain != NSURLErrorDomain || underlying.code != NSURLErrorCancelled else { return }
        isFinished = false
        lastError = error.localizedDescription
        // No URL, account, ticket, Cookie or server response is logged.
        Self.logger.error("Navigation failed: domain=\(underlying.domain, privacy: .public), code=\(underlying.code, privacy: .public)")
        onFailure?(error.localizedDescription)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            let url = webView.url
            currentURL = url
            isFinished = true
            lastError = nil
            if let url { onNavigate?(url) }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            isFinished = false
            lastError = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            recordFailure(error)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            recordFailure(error)
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            isFinished = false
            lastError = "加载失败，请重试"
            Self.logger.error("Web content process terminated")
        }
    }

    /// 302 也算一次导航，这里补捉，避免 didFinish 漏掉重定向后的地址
    nonisolated func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            if let url = webView.url { currentURL = url }
        }
    }
}

// MARK: - JS 执行（带参数 + 支持 await）

extension WKWebView {
    /// 对应 iOS 26 的 WebPage.callJavaScript，iOS 15 起就有
    func callAsync(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            self.callAsyncJavaScript(
                body,
                arguments: arguments,
                in: nil,
                in: .page
            ) { result in
                switch result {
                case .success(let value): cont.resume(returning: value)
                case .failure(let error): cont.resume(throwing: error)
                }
            }
        }
    }
}
