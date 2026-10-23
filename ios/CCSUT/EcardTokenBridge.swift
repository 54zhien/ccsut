//
//  EcardTokenBridge.swift
//  CCSUT
//
//  用 WKWebView 拿一卡通缴费的 access_token
//
//  原理：
//    平台登录态（统一身份认证 SSO）存在 WKWebsiteDataStore 里，我们复用它，
//    直接访问换票接口 GET /charge/feeitem/toAppitem?feeitemid=408
//      → 服务端校验登录态
//      → 302 到 https://ecard.ccsut.cn/charge-app/?token=<access_token>&name=pays&id=408
//    在 302 被应用的那一刻从 URL 里截出 token（charge-app 加载后会立刻
//    history.replaceState 把参数抹掉，所以不能等页面加载完再看地址栏）。
//
//  首次使用会跳到 /plat/login，让用户在里面登录一次即可；之后会话持久化，
//  通常可以长期免登。校外需要 aTrust 放行，这时本 WebView 天然带着会话。
//

import Foundation
import WebKit

@MainActor
final class EcardTokenBridge: NSObject {

    /// 展示给用户的 WebView（放进 sheet / 容器即可）
    let webView: WKWebView

    private let feeitemID: String
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private var timeoutTask: Task<Void, Never>?

    /// 超时时间：留给用户登录的时间
    private let timeout: TimeInterval

    init(feeitemID: String = EcardClient.electricityFeeItemID,
         timeout: TimeInterval = 120,
         dataStore: WKWebsiteDataStore = .default()) {
        self.feeitemID = feeitemID
        self.timeout = timeout

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = false
        self.webView = wv
        super.init()
        wv.navigationDelegate = self
    }

    // MARK: 对外入口

    /// 取 token。调用前请先把 `webView` 放进视图层级并开始加载（见 `load()`）。
    func token() async throws -> String {
        if let cached = Self.cachedToken() { return cached }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.startTimeout()
        }
    }

    /// 开始换票流程
    func load() {
        let url = URL(string:
            "https://ecard.ccsut.cn/charge/feeitem/toAppitem?feeitemid=\(feeitemID)")!
        webView.load(URLRequest(url: url))
    }

    /// 一步到位：加载 + 等 token
    func fetchToken() async throws -> String {
        load()
        return try await token()
    }

    // MARK: token 缓存（只缓存内存，不落盘）

    private static var memoryToken: String?

    /// 从内存缓存取；没有就返回 nil（不做磁盘缓存，避免凭证外泄）
    static func cachedToken(validForFeeItem feeitemID: String? = nil) -> String? {
        memoryToken
    }

    static func clearCachedToken() { memoryToken = nil }

    // MARK: 内部

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil

        if case .success(let token) = result {
            Self.memoryToken = token
        }
        continuation?.resume(with: result)
        continuation = nil
    }

    private func startTimeout() {
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            let seconds = self.timeout
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.finish(.failure(EcardError.noToken))
            }
        }
    }

    /// 从 URL 里抠 token
    private func token(from url: URL?) -> String? {
        guard let url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = comps.queryItems?.first(where: { $0.name == "token" })?.value,
              !value.isEmpty
        else { return nil }
        return value
    }
}

// MARK: - WKNavigationDelegate

extension EcardTokenBridge: WKNavigationDelegate {

    /// 关键：302 的 Location 会作为一次新的 navigationAction 送进来
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        Task { @MainActor [weak self] in
            guard let self, let token = self.token(from: url) else { return }
            self.finish(.success(token))
            // 拿到就回退，别把缴费页真的渲染出来（可选）
            webView.stopLoading()
        }
        decisionHandler(.allow)
    }

    /// 兜底一：服务端重定向时再查一次当前 URL
    nonisolated func webView(_ webView: WKWebView,
                             didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let url = webView.url
        Task { @MainActor [weak self] in
            guard let self, let token = self.token(from: url) else { return }
            self.finish(.success(token))
            webView.stopLoading()
        }
    }

    /// 兜底二：页面已经渲染完（token 已被 replaceState 抹掉），从 sessionStorage 读
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, !self.finished else { return }

            if let token = self.token(from: webView.url) {
                self.finish(.success(token)); return
            }

            let js = """
            (function () {
              var keys = Object.keys(sessionStorage).filter(function (k) {
                return /token/i.test(k);
              });
              for (var i = 0; i < keys.length; i++) {
                var v = sessionStorage.getItem(keys[i]);
                if (v && v.length > 40) return v;
              }
              return '';
            })();
            """
            let value: Any?
            do {
                value = try await webView.evaluateJavaScript(js)
            } catch {
                // 还在登录页，什么都不做，等用户登录后继续
                return
            }
            if let token = value as? String, !token.isEmpty {
                self.finish(.success(token))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        let message = (error as NSError).code
        Task { @MainActor [weak self] in
            // -999 是被我们 stopLoading 打断的，不算错误
            guard let self, message != NSURLErrorCancelled else { return }
            self.finish(.failure(error))
        }
    }
}
