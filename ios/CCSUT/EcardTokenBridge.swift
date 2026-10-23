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
//    bridge 自己不弹任何界面。调用方必须把 `bridge.webView` 放进视图层级
//    （sheet / 容器），再 `await bridge.fetchToken(forAccount: sno)`。
//
//  凭证安全：
//    - token 只在内存缓存，绑定 `sno`，并校验 JWT `exp` 未过期
//    - `forAccount` 为 nil 时完全绕过缓存
//    - 退出登录调用 `EcardTokenBridge.clearCachedToken()`
//    - 只接受 ecard.ccsut.cn/charge-app 路径下、且能解出未过期 exp 的 JWT
//

import Foundation
import WebKit

@MainActor
final class EcardTokenBridge: NSObject {

    /// 展示给用户的 WebView（调用方负责放进视图层级）
    let webView: WKWebView

    private let feeitemID: String
    private let timeout: TimeInterval

    /// 请求代数：每次新请求自增，用于丢弃迟到回调
    private var generation = 0
    /// 本次导航所属的代数：导航回调只对同代请求生效
    private var navigationGeneration = 0

    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
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

    /// 加载 + 等 token
    /// - Parameter account: 当前登录学号。传了就只在同学号缓存上复用；传 nil 不复用缓存。
    func fetchToken(forAccount account: String?) async throws -> String {
        if let cached = Self.cachedToken(forAccount: account) { return cached }
        return try await startRequest(account: account)
    }

    // MARK: 缓存

    private struct CacheEntry {
        let token: String
        let sno: String?
        let expiresAt: Date
    }

    private static var cache: CacheEntry?

    static func cachedToken(forAccount account: String?) -> String? {
        guard let entry = cache else { return nil }
        guard entry.expiresAt.timeIntervalSinceNow > 60 else {
            cache = nil
            return nil
        }
        guard let account, !account.isEmpty, let sno = entry.sno, sno == account else {
            return nil
        }
        return entry.token
    }

    static func clearCachedToken() { cache = nil }

    /// 只有「结构合法 + 未过期」才入缓存
    private static func store(token: String) {
        guard let claims = JWT.claims(token), let exp = claims.expiresAt,
              exp.timeIntervalSinceNow > 60 else { return }
        cache = CacheEntry(token: token, sno: claims.studentNumber, expiresAt: exp)
    }

    // MARK: 请求生命周期

    private func startRequest(account: String?) async throws -> String {
        // 结掉上一个等待者，避免 continuation 泄漏
        if let old = continuation {
            continuation = nil
            timeoutTask?.cancel()
            old.resume(throwing: EcardError.canceled)
        }

        generation &+= 1
        let myGeneration = generation
        pendingAccount = account

        // 导航与本次请求绑定
        navigationGeneration = myGeneration
        refresh()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                self.startTimeout(generation: myGeneration)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                // 只允许「自己这一代」被取消，不能误伤后来者
                self?.cancel(generation: myGeneration)
            }
        }
    }

    private func refresh() {
        let url = URL(string:
            "https://ecard.ccsut.cn/charge/feeitem/toAppitem?feeitemid=\(feeitemID)")!
        webView.load(URLRequest(url: url))
    }

    private func cancel(generation gen: Int) {
        guard gen == generation, let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        // 让这一代之后的所有回调失效
        generation &+= 1
        cont.resume(throwing: EcardError.canceled)
    }

    private func finish(_ result: Result<String, Error>, generation gen: Int) {
        guard gen == generation, let cont = continuation else { return }
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

    private func startTimeout(generation gen: Int) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            let seconds = self.timeout
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.finish(.failure(EcardError.noToken), generation: gen)
        }
    }

    /// 只认缴费网关这一条路径，且 JWT 未过期
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

        return validate(raw, account: account)
    }

    /// 结构 + 过期 + 账号一致性
    private func validate(_ token: String, account: String?) -> String? {
        guard let claims = JWT.claims(token), let exp = claims.expiresAt,
              exp.timeIntervalSinceNow > 60 else { return nil }
        if let account, !account.isEmpty {
            guard let sno = claims.studentNumber, sno == account else { return nil }
        }
        return token
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
            guard let self, self.navigationGeneration == self.generation else { return }
            guard let token = self.token(from: url, account: self.pendingAccount) else { return }
            self.finish(.success(token), generation: self.generation)
            webView.stopLoading()
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let url = webView.url
        Task { @MainActor [weak self] in
            guard let self, self.navigationGeneration == self.generation else { return }
            guard let token = self.token(from: url, account: self.pendingAccount) else { return }
            self.finish(.success(token), generation: self.generation)
            webView.stopLoading()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let pageURL = webView.url
        Task { @MainActor [weak self] in
            guard let self, self.navigationGeneration == self.generation,
                  self.continuation != nil else { return }

            if let token = self.token(from: pageURL, account: self.pendingAccount) {
                self.finish(.success(token), generation: self.generation)
                return
            }

            // 兜底只读固定键，且必须确认还在缴费域名下
            guard let pageURL, pageURL.host?.lowercased() == "ecard.ccsut.cn" else { return }

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
                  let raw = value as? String,
                  let token = self.validate(raw, account: self.pendingAccount)
            else { return }

            self.finish(.success(token), generation: self.generation)
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        let code = (error as NSError).code
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, code != NSURLErrorCancelled else { return }
            // 用导航所属的代数：旧导航的错误不能落到新请求上
            self.finish(.failure(EcardError.transport(message)),
                        generation: self.navigationGeneration)
        }
    }
}

// MARK: - JWT

enum JWT {
    struct Claims {
        let studentNumber: String?
        let expiresAt: Date?
        let clientID: String?

        var isExpired: Bool {
            guard let expiresAt else { return true }
            return expiresAt.timeIntervalSinceNow <= 60
        }
    }

    static func claims(_ token: String) -> Claims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty else { return nil }
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
