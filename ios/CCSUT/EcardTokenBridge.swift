//
//  EcardTokenBridge.swift
//  CCSUT
//
//  用 WKWebView 拿一卡通缴费的 access_token
//
//  原理：
//    先打开官方 /plat/login，用户完成一卡通登录并进入电费项目。
//    /charge/feeitem/toAppitem 是需要令牌的换票接口，不能作为未登录入口：
//    实际会直接返回「缺失令牌，鉴权失败」，并不会自动重定向到登录页。
//    由官方门户带着它自己的认证上下文进入电费项目后，跳转到：
//      https://ecard.ccsut.cn/charge-app/?token=<access_token>&name=pays&id=408
//    在 302 被应用的那一刻从 URL 里截出 token（charge-app 加载后会立刻
//    history.replaceState 把参数抹掉，所以不能等页面加载完再看地址栏）。
//
//  使用方式（重要）：
//    bridge 不弹界面，可先在后台 `await fetchToken(forAccount: sno)`。
//    onNeedsInteraction 通知调用方把同一个 webView 放进 sheet；不要重启请求。
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
    var onNeedsInteraction: (() -> Void)?

    private let feeitemID: String
    private let timeout: TimeInterval

    /// 请求代数：每次新请求自增，用于丢弃迟到回调
    private var generation = 0
    // Keep each navigation's owner, including retired navigations: a late error
    // must never be relabelled with the current request's generation.
    private var navigationGenerations: [WKNavigation: Int] = [:]
    private var currentNavigation: WKNavigation?
    private var requestCacheRevision = 0

    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingAccount: String?
    private var attemptedPortalActions: Set<String> = []
    private var advancingPortal = false
    private var reportedInteraction = false

    init(feeitemID: String = EcardClient.electricityFeeItemID,
         timeout: TimeInterval = 120,
         dataStore: WKWebsiteDataStore? = nil,
         webView: WKWebView? = nil) {
        self.feeitemID = feeitemID
        self.timeout = timeout

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore ?? .default()

        // Give the invisible page a real viewport for responsive login/portal
        // layouts. WebPanel supplies its actual size if interaction is needed.
        let wv = webView ?? WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: cfg)
        wv.allowsBackForwardNavigationGestures = false
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        self.webView = wv
        super.init()
        wv.navigationDelegate = self
        wv.uiDelegate = self
    }

    // MARK: 对外入口

    /// 加载 + 等 token
    /// - Parameter account: 当前登录学号。传了就只在同学号缓存上复用；传 nil 不复用缓存。
    func fetchToken(forAccount account: String?) async throws -> String {
        guard !Task.isCancelled else { throw EcardError.canceled }
        if let cached = Self.cachedToken(forAccount: account) { return cached }
        let revision = Self.cacheRevision
        // A prior cold-start injection may have failed. Fill gaps before SSO,
        // preserving cookies already rotated by the official WebView flow.
        do {
            try await WebStore.restoreCookies(CookieJar.shared,
                to: webView.configuration.websiteDataStore, policy: .fillMissing)
        } catch is CancellationError {
            throw EcardError.canceled
        } catch {
            throw EcardError.sessionSynchronization
        }
        guard revision == Self.cacheRevision, !Task.isCancelled else { throw EcardError.canceled }
        let token = try await startRequest(account: account)
        // Logout/cancellation may happen after finish resumes the continuation
        // but before this caller is scheduled to consume its result.
        guard revision == Self.cacheRevision, !Task.isCancelled else { throw EcardError.canceled }
        return token
    }

    // MARK: 缓存

    private struct CacheEntry {
        let token: String
        let sno: String?
        let expiresAt: Date
    }

    private static var cache: CacheEntry?
    private static var cacheRevision = 0
    private static var preparation: (id: UUID, account: String, task: Task<Void, Never>)?
    private static var preparationSuspensions = 0

    /// Best effort SSO after the main account has been verified. A gateway that
    /// requires interaction simply times out; it must not block the App login.
    static func prepareSession(forAccount account: String, dataStore: WKWebsiteDataStore) {
        guard preparationSuspensions == 0, !account.isEmpty, cachedToken(forAccount: account) == nil,
              preparation?.account != account else { return }
        cancelPreparation()
        let id = UUID()
        let task = Task { @MainActor in
            defer { if preparation?.id == id { preparation = nil } }
            let generation = CookieJar.generation
            let bridge = EcardTokenBridge(timeout: 20, dataStore: dataStore)
            do {
                _ = try await bridge.fetchToken(forAccount: account)
                let cookies = try await dataStore.httpCookieStore.cookieSnapshot()
                guard CookieJar.generation == generation, !Task.isCancelled else { return }
                CookieJar.upsert(cookies, generation: generation)
            } catch { /* Best effort only; payment startup can retry. */ }
        }
        preparation = (id, account, task)
    }

    static func cancelPreparation() {
        preparation?.task.cancel()
        preparation = nil
    }

    /// Drain suspended snapshot/write work before native CAS rotates cookies.
    static func cancelPreparationAndWait() async {
        let task = preparation?.task
        cancelPreparation()
        await task?.value
    }

    static func suspendPreparation() async {
        preparationSuspensions += 1
        await cancelPreparationAndWait()
    }

    static func resumePreparation() {
        preparationSuspensions = max(0, preparationSuspensions - 1)
    }

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

    static func clearCachedToken() {
        cancelPreparation()
        cache = nil
        cacheRevision &+= 1
    }

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
        webView.stopLoading()

        generation &+= 1
        let myGeneration = generation
        pendingAccount = account
        attemptedPortalActions = []
        advancingPortal = false
        reportedInteraction = false
        requestCacheRevision = Self.cacheRevision

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                self.startTimeout(generation: myGeneration)
                self.refresh(generation: myGeneration)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                // 只允许「自己这一代」被取消，不能误伤后来者
                self?.cancel(generation: myGeneration)
            }
        }
    }

    private func refresh(generation: Int) {
        let url = URL(string: "https://ecard.ccsut.cn/plat/login")!
        load(URLRequest(url: url), generation: generation)
    }

    private func load(_ request: URLRequest, generation: Int) {
        if let navigation = webView.load(request) {
            navigationGenerations[navigation] = generation
            currentNavigation = navigation
        }
    }

    private func cancel(generation gen: Int) {
        guard gen == generation, continuation != nil else { return }
        finish(.failure(EcardError.canceled), generation: gen)
    }

    private func finish(_ result: Result<String, Error>, generation gen: Int) {
        guard gen == generation, let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        generation &+= 1
        webView.stopLoading()

        guard requestCacheRevision == Self.cacheRevision else {
            cont.resume(throwing: EcardError.canceled)
            return
        }

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
            let stage = EcardAuthenticationStage(url: self.webView.url)
            self.finish(.failure(EcardError.authenticationTimeout(stage)), generation: gen)
        }
    }

    /// 只认缴费网关这一条路径，且 JWT 未过期
    private func token(from url: URL?, account: String?) -> String? {
        guard Self.isPaymentPage(url), let url else { return nil }

        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = comps.queryItems?.first(where: { $0.name == "token" })?.value,
              !raw.isEmpty
        else { return nil }

        return validate(raw, account: account)
    }

    private static func isPaymentPage(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "ecard.ccsut.cn",
              url.port == nil || url.port == 443 else { return false }
        return url.path == "/charge-app" || url.path.hasPrefix("/charge-app/")
    }

    private static func isPortalPage(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "ecard.ccsut.cn",
              url.port == nil || url.port == 443 else { return false }
        return url.path == "/plat" || url.path.hasPrefix("/plat/")
    }

    /// Only follow the observed official SSO/project entries. Never match or
    /// activate payment/confirmation controls. Manual login remains available.
    private func advancePortal(pageURL: URL, generation gen: Int) async {
        guard !advancingPortal else { return }
        advancingPortal = true
        defer { if gen == generation { advancingPortal = false } }
        let script = """
        for (let attempt = 0; attempt < 20; attempt++) {
          if (location.origin !== 'https://ecard.ccsut.cn' ||
              !(location.pathname === '/plat' || location.pathname.startsWith('/plat/'))) return '';
          const entries = [...document.querySelectorAll('a, button, [role="button"], span, div')];
          const exact = labels => {
            const matches = entries.filter(el => {
            const text = (el.textContent || '').replace(/\\s+/g, '').toLowerCase();
            return labels.includes(text) && el.getClientRects().length > 0 &&
              el.getAttribute('aria-disabled') !== 'true' && !el.disabled;
            });
            return matches.find(el => el.matches('a, button, [role="button"]')) ||
              matches.find(el => !matches.some(child => child !== el && el.contains(child)));
          };
          const electricity = allowElectricity ? exact(['电表缴费', '电费缴费']) : null;
          const cas = allowCAS ? exact(['智林cas']) : null;
          const entry = electricity || cas;
          if (entry) {
            entry.click();
            return electricity ? 'electricity' : 'cas';
          }
          await new Promise(resolve => setTimeout(resolve, 150));
        }
        return '';
        """
        let value = try? await webView.callAsyncJavaScript(script, arguments: [
            "allowCAS": !attemptedPortalActions.contains("cas"),
            "allowElectricity": !attemptedPortalActions.contains("electricity")
        ], in: nil, in: .page)
        guard gen == generation, continuation != nil else { return }
        if let action = value as? String, ["cas", "electricity"].contains(action) {
            attemptedPortalActions.insert(action)
        }
    }

    private func reportInteractionIfNeeded(pageURL: URL?, navigation: WKNavigation, generation gen: Int) async {
        guard onNeedsInteraction != nil, !reportedInteraction, let pageURL,
              pageURL.scheme?.lowercased() == "https", pageURL.port == nil || pageURL.port == 443,
              let host = pageURL.host?.lowercased(),
              host == "auth.ccsut.cn" || host == "zts.ccsut.cn" || Self.isPortalPage(pageURL),
              gen == generation, continuation != nil, webView.url == pageURL,
              currentNavigation === navigation else { return }
        // Inspect controls only, never their values or authentication payloads.
        // A network delay alone is not proof that a login window is necessary.
        let script = """
        const selector = portalOnly ? 'input[type="password"]' :
          'input[type="password"], input[autocomplete="one-time-code"], input[name*="code" i], ' +
          'input[placeholder*="验证码"], canvas, img[src*="qrcode" i], img[alt*="二维码"], ' +
          '[id*="qrcode" i], [class*="qrcode" i], [class*="qr-code" i]';
        const visibleControl = () => [...document.querySelectorAll(selector)].some(el =>
          el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden');
        for (let attempt = 0; attempt < 15; attempt++) {
          if (location.href !== expectedURL) return false;
          if (visibleControl()) {
            await new Promise(resolve => setTimeout(resolve, 800));
            return location.href === expectedURL && visibleControl();
          }
          await new Promise(resolve => setTimeout(resolve, 150));
        }
        return false;
        """
        let needsInteraction = try? await webView.callAsyncJavaScript(script, arguments: [
            "portalOnly": Self.isPortalPage(pageURL), "expectedURL": pageURL.absoluteString
        ], in: nil, in: .page)
        guard gen == generation, continuation != nil, webView.url == pageURL,
              currentNavigation === navigation, !webView.isLoading,
              needsInteraction as? Bool == true else { return }
        reportedInteraction = true
        onNeedsInteraction?()
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

    func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // A canceled/retired background SSO must not continue navigating the
        // shared website session after the interactive flow takes over.
        guard continuation != nil else { decisionHandler(.cancel); return }
        let url = navigationAction.request.url
        if let token = token(from: url, account: pendingAccount) {
            decisionHandler(.cancel)
            finish(.success(token), generation: generation)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let navigation, continuation != nil else { return }
        if navigationGenerations[navigation] == nil {
            navigationGenerations[navigation] = generation
        }
        if navigationGenerations[navigation] == generation { currentNavigation = navigation }
    }

    func webView(_ webView: WKWebView,
                             didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let navigation, navigationGenerations[navigation] == generation,
              let token = token(from: webView.url, account: pendingAccount) else { return }
        finish(.success(token), generation: generation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation, navigationGenerations[navigation] == generation,
              currentNavigation === navigation, continuation != nil else { return }
        let gen = generation
        let account = pendingAccount
        let pageURL = webView.url
        Task { @MainActor [weak self] in
            guard let self, gen == self.generation,
                  self.continuation != nil else { return }

            if let token = self.token(from: pageURL, account: account) {
                self.finish(.success(token), generation: gen)
                return
            }

            if Self.isPortalPage(pageURL), let pageURL, webView.url == pageURL {
                await self.advancePortal(pageURL: pageURL, generation: gen)
                await self.reportInteractionIfNeeded(pageURL: pageURL, navigation: navigation, generation: gen)
                return
            }

            // 兜底只读固定键，且必须确认还在缴费域名下
            guard Self.isPaymentPage(pageURL), webView.url == pageURL else {
                await self.reportInteractionIfNeeded(pageURL: pageURL, navigation: navigation, generation: gen)
                return
            }

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
                  gen == self.generation, self.currentNavigation === navigation,
                  webView.url == pageURL,
                  let raw = value as? String,
                  let token = self.validate(raw, account: account)
            else { return }

            self.finish(.success(token), generation: gen)
        }
    }

    func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        guard let navigation, let gen = navigationGenerations[navigation],
              (error as NSError).code != NSURLErrorCancelled else { return }
        finish(.failure(EcardError.transport(error.localizedDescription)), generation: gen)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
}

// The portal may open its electricity project with target=_blank/window.open.
// Keep that official flow in this sheet instead of silently discarding the tab.
extension EcardTokenBridge: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard continuation != nil, navigationAction.targetFrame == nil else { return nil }
        load(navigationAction.request, generation: generation)
        return nil
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
