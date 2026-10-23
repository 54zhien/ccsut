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
//  使用方式（重要）：
//    bridge 自己不会弹任何界面。调用方必须把 `bridge.webView` 放进视图层级
//    （sheet / 容器），再 `await bridge.fetchToken(forAccount:)`。
//
//  凭证安全：
//    - token 只在内存缓存，并且绑定 `sno` + 校验 JWT `exp`
//    - `forAccount` 传 nil 时**完全绕过缓存**，避免切换账号后沿用他人凭证
//    - 退出登录请调 `EcardTokenBridge.clearCachedToken()`
//

import Foundation
import WebKit

@MainActor
final class EcardTokenBridge: NSObject {

    /// 展示给用户的 WebView（调用方负责放进视图层级）
    let webView: WKWebView

    private let feeitemID: String
    private let timeout: TimeInterval

    /// 每次请求自增，用于丢弃迟到的回调
    private var generation = 0
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    /// 本次等待对应的学号（供导航回调校验）
    private var pendingAccount: String?

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

    /// 开始换票流程（只负责导航，不等结果）
    func load() {
        let url = URL(string:
            "https://ecard.ccsut.cn/charge/feeitem/toAppitem?feeitemid=\(feeitemID)")!
        webView.load(URLRequest(url: url))
    }

    /// 一步到位：加载 + 等 token
    ///
    /// - Parameter account: 当前登录者的学号。传了就只在**同一学号**的缓存上复用；
    ///   传 nil 表示不复用缓存（切换账号场景请传 sno，或干脆传 nil）。
    func fetchToken(forAccount account: String?) async throws -> String {
        if let cached = Self.cachedToken(forAccount: account) { return cached }
        load()
        return try await token(forAccount: account)
    }

    /// 只等待 token，不触发导航（适合已经手动 load 过的场景）
    func token(forAccount account: String?) async throws -> String {
        if let cached = Self.cachedToken(forAccount: account) { return cached }

        // 上一次请求若还挂着，先以「被新请求取代」结束掉，避免 continuation 泄漏
        cancelPending(.canceled)

        generation &+= 1
        let myGeneration = generation
        pendingAccount = account

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                self.startTimeout(generation: myGeneration)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPending(.canceled)
            }
        }
    }

    // MARK: 缓存

    private struct CacheEntry {
        let token: String
        let sno: String?
        let expiresAt: Date
    }

    private static var cache: CacheEntry?

    /// 只在「同一学号 + 未过期（留 60s 余量）」时复用
    static func cachedToken(forAccount account: String?) -> String? {
        guard let entry = cache else { return nil }
        guard entry.expiresAt.timeIntervalSinceNow > 60 else {
            cache = nil
            return nil
        }
        // 传了学号就必须一致；传 nil 不复用，避免跨账号串凭证
        guard let account, !account.isEmpty, let sno = entry.sno, sno == account else {
            return nil
        }
        return entry.token
    }

    static func clearCachedToken() { cache = nil }

    private static func store(token: String) {
        let claims = JWT.claims(token)
        let exp = claims?.expiresAt ?? Date().addingTimeInterval(30 * 60)
        cache = CacheEntry(token: token, sno: claims?.studentNumber, expiresAt: exp)
    }

    // MARK: 内部

    private func cancelPending(_ error: EcardError) {
        generation &+= 1
        timeoutTask?.cancel()
        timeoutTask = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(throwing: error)
        }
    }

    private func finish(_ result: Result<String, Error>, generation: Int) {
        // 迟到的回调直接丢弃
        guard generation == self.generation, let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        switch result {
        case .success(let token):
            Self.store(token: token)
            cont.resume(returning: token)
        case .failure(let error):
            cont.resume(throwing: error)
        }
    }

    private func startTimeout(generation: Int) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            let seconds = self.timeout
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.finish(.failure(EcardError.noToken), generation: generation)
        }
    }

    /// 只认缴费网关这一条路径上的 token
    private func token(from url: URL?, account: String?) -> String? {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "ecard.ccsut.cn",
              url.path.hasPrefix("/charge-app")
        else { return nil }

        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = comps.queryItems?.first(where: { $0.name == "token" })?.value,
              !raw.isEmpty
        else { return nil }

        // 必须是一张能解出 exp 的缴费 JWT
        guard let claims = JWT.claims(raw), claims.expiresAt != nil else { return nil }
        if let account, !account.isEmpty {
            guard let sno = claims.studentNumber else { return nil }
            guard sno == account else { return nil }
        }
        return raw
    }
}

// MARK: - WKNavigationDelegate

extension EcardTokenBridge: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)

        let url = navigationAction.request.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            let gen = self.generation
            let account = self.pendingAccount
            guard let token = self.token(from: url, account: account) else { return }
            self.finish(.success(token), generation: gen)
            webView.stopLoading()
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let url = webView.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            let gen = self.generation
            let account = self.pendingAccount
            guard let token = self.token(from: url, account: account) else { return }
            self.finish(.success(token), generation: gen)
            webView.stopLoading()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            let gen = self.generation
            let account = self.pendingAccount

            if let token = self.token(from: webView.url, account: account) {
                self.finish(.success(token), generation: gen)
                return
            }

            // 兜底：只读固定键，不扫「名字里带 token」的任意值
            let js = """
            (function () {
              var keys = ['access_token_pay', 'access_token'];
              for (var i = 0; i < keys.length; i++) {
                var v = sessionStorage.getItem(keys[i]);
                if (v && v.split('.').length === 3) return v;
              }
              return '';
            })();
            """
            guard let value = try? await webView.evaluateJavaScript(js),
                  let token = value as? String,
                  let claims = JWT.claims(token),
                  claims.expiresAt != nil
            else {
                // 大概率还停在登录页，等用户登完继续
                return
            }
            if let account, !account.isEmpty, claims.studentNumber != account { return }
            self.finish(.success(token), generation: gen)
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        let code = (error as NSError).code
        Task { @MainActor [weak self] in
            guard let self, code != NSURLErrorCancelled else { return }
            self.finish(.failure(EcardError.transport(error.localizedDescription)),
                        generation: self.generation)
        }
    }
}

// MARK: - JWT 解析

enum JWT {
    struct Claims {
        let studentNumber: String?
        let expiresAt: Date?
        let clientID: String?
    }

    static func claims(_ token: String) -> Claims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let data = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { return nil }

        let exp = (dict["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return Claims(studentNumber: dict["sno"] as? String,
                      expiresAt: exp,
                      clientID: dict["client_id"] as? String)
    }

    private static func base64URLDecode(_ input: String) -> Data? {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        if pad > 0 { s += String(repeating: "=", count: pad) }
        return Data(base64Encoded: s)
    }
}
