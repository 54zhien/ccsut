//
//  Session.swift
//  CCSUT
//
//  会话层 · 使用 iOS 17+ 的 @Observable 宏（取代 ObservableObject）
//
//  职责：
//    · Cookie 持久化（Keychain）
//    · 冷启动探测 /admin/ 判断登录态
//    · 用 TGC（14 天）静默续期
//
//  设计：WebView 只负责"登录"这一件脏活，之后所有请求走 URLSession
//

import Foundation
import WebKit
import Observation
import Security

// MARK: - Keychain

enum Keychain {
    private static let service = "cn.ccsut.app"

    static func save(_ data: Data, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let value = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var attrs = base
            attrs[kSecValueData as String] = data
            attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(attrs as CFDictionary, nil)
        }
    }

    static func load(_ key: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Cookie 序列化

struct StoredCookie: Codable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var isSecure: Bool
    var isHTTPOnly: Bool

    init(_ c: HTTPCookie) {
        name = c.name
        value = c.value
        domain = c.domain
        path = c.path
        expires = c.expiresDate
        isSecure = c.isSecure
        isHTTPOnly = c.isHTTPOnly
    }

    var asHTTPCookie: HTTPCookie? {
        var p: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
        ]
        if let expires { p[.expires] = expires }
        if isSecure { p[.secure] = "TRUE" }
        if isHTTPOnly { p[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: p)
    }
}

// MARK: - WKHTTPCookieStore async 包装

/// WebKit 回调丢失或任务取消时也要结束等待；迟到的回调只能完成一次。
final class CookieCallback<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?

    private func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    static func wait(timeout: Duration = .seconds(5),
                     start: (@escaping @Sendable (Value) -> Void) -> Void) async throws -> Value {
        let callback = CookieCallback<Value>()
        let deadline = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            callback.finish(.failure(URLError(.timedOut)))
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                callback.install(continuation)
                start { callback.finish(.success($0)) }
            }
        } onCancel: {
            callback.finish(.failure(CancellationError()))
        }
    }
}

extension WKHTTPCookieStore {
    func cookieSnapshot() async throws -> [HTTPCookie] {
        try await CookieCallback.wait { completion in getAllCookies(completion) }
    }

    func set(_ cookie: HTTPCookie) async throws {
        let _: Void = try await CookieCallback.wait { completion in
            setCookie(cookie) { completion(()) }
        }
    }

    /// deleteCookie 在新 SDK 里已改名为 delete，这里换个名字避免递归
    func remove(_ cookie: HTTPCookie) async throws {
        let _: Void = try await CookieCallback.wait { completion in
            delete(cookie) { completion(()) }
        }
    }
}

// MARK: - SessionStore

struct SessionStudentName: Equatable, Sendable {
    let account: String
    let generation: UInt64
    let value: String
}

typealias StudentNameResolver = @MainActor (String, UInt64) async -> SessionStudentName?

@Observable
@MainActor
final class SessionStore {

    enum Phase: Equatable, Sendable {
        case checking
        case loggedOut
        case loggedIn
        case refreshing
    }

    // MARK: 可观察状态

    private(set) var phase: Phase = .checking
    private(set) var lastError: String?
    private(set) var studentName: String?
    private(set) var studentId: String?
    private(set) var lastCookieCount = 0

    /// 供 UI 展示的会话健康摘要
    var cookieSummary: String {
        let list = allCookies()
            .sorted { ($0.expiresDate ?? .distantPast) > ($1.expiresDate ?? .distantPast) }
            .prefix(4)
            .map { c in
                let d = c.expiresDate.map { String(format: "%.1f天", $0.timeIntervalSinceNow / 86400) } ?? "会话"
                return "\(c.name)·\(d)"
            }
        return list.isEmpty ? "未登录" : list.joined(separator: "  ")
    }

    /// 调试用：当前所有 Cookie 的名字
    var cookieNames: String {
        let names = allCookies().map(\.name).sorted()
        return names.isEmpty ? "无" : names.joined(separator: ",")
    }

    var tgcRemainingDays: Double? {
        guard let tgc = allCookies().first(where: { $0.name == "TGC" }),
              let exp = tgc.expiresDate else { return nil }
        return exp.timeIntervalSinceNow / 86400
    }

    // MARK: 常量

    static let jwBase = URL(string: "https://tls.ccsut.cn")!
    static let serviceURL = "https://tls.ccsut.cn/admin/caslogin"

    static var casLoginURL: URL {
        var c = URLComponents(string: "https://auth.ccsut.cn/backstage/cas/login")!
        c.queryItems = [URLQueryItem(name: "service", value: serviceURL)]
        return c.url!
    }

    private let api: APIClient
    private let prepareEcardSession: @MainActor (String, WKWebsiteDataStore) -> Void
    private let studentNameResolver: StudentNameResolver?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var adoptionTask: Task<Bool, Never>?
    @ObservationIgnored private var isLoggingOut = false
    @ObservationIgnored private var verifiedIdentity: (value: StudentIdentity, generation: UInt64)?

    init(api: APIClient = .shared,
         prepareEcardSession: @escaping @MainActor (String, WKWebsiteDataStore) -> Void = {
             EcardTokenBridge.prepareSession(forAccount: $0, dataStore: $1)
         },
         studentNameResolver: StudentNameResolver? = nil) {
        self.api = api
        self.prepareEcardSession = prepareEcardSession
        self.studentNameResolver = studentNameResolver
    }

    private let cookieKey = "ccsut.cookies.v2"
    private let nameKey = "ccsut.student.name"
    private let sidKey = "ccsut.student.id"

    // MARK: 冷启动

    func bootstrap() async {
        phase = .checking
        lastError = nil
        defer {
            // 网络错误、取消和续期失败都必须离开启动页；保留凭证供用户重试。
            if phase == .checking || phase == .refreshing { phase = .loggedOut }
        }

        let restored = restoreFromKeychain()
        CookieJar.shared = restored
        let generation = CookieJar.generation
        guard !restored.isEmpty else {
            phase = .loggedOut
            return
        }

        do {
            try await verifySession()
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            // WebStore is deliberately non-persistent. The native session may
            // still be valid after a cold launch, but CAS/ecard WebViews start
            // empty until the restored (and verified) cookies are injected.
            // Do this before exposing MainTabs or starting the ecard prefetch.
            await injectToWebKit(allCookies())
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            guard publishVerifiedIdentity(generation: generation) else { return }
            phase = .loggedIn
            await refreshIfNeeded()
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            await loadProfile()
        } catch {
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            lastError = error.localizedDescription
            // 断网和 5xx 不会因重登改善；只在明确认证失效时尝试 CAS。
            if let e = error as? APIError, case .notLoggedIn = e,
               allCookies().contains(where: { $0.name == "TGC" }) {
                await refresh()
            } else {
                phase = .loggedOut
            }
        }
    }

    // MARK: 探测

    /// 发一个带 CookieJar 的请求，手动跟随重定向。
    ///
    /// 为什么要手动跟：续期要从 tls.ccsut.cn 跳到 auth.ccsut.cn 再跳回来，
    /// 而 TGC 属于 auth.ccsut.cn 域。关闭 URLSession 自动 Cookie 后，
    /// 自动重定向不会按新 host 补 Cookie，TGC 就永远发不出去。
    private func rawGet(_ url: URL, timeout: TimeInterval = 20) async throws -> HTTPURLResponse {
        var req = URLRequest(url: url)
        req.setValue(UserAgent.mobile, forHTTPHeaderField: "User-Agent")
        let (_, http) = try await api.response(for: req, timeout: timeout, allowAuthenticationRedirects: true)
        return http
    }

    /// 用身份相关的 JSON 验证会话，不能把任意一个 200 页面当成成功。
    func probe() async -> Bool {
        let generation = CookieJar.generation
        do {
            try await verifySession()
            guard CookieJar.generation == generation, !Task.isCancelled else { return false }
            lastError = nil
            return true
        } catch {
            guard CookieJar.generation == generation, !Task.isCancelled else { return false }
            lastError = error.localizedDescription
            return false
        }
    }

    private func verifySession() async throws {
        let generation = CookieJar.generation
        let profile = try await api.authenticatedProfile()
        guard CookieJar.generation == generation, !Task.isCancelled else { throw CancellationError() }
        if phase == .loggedIn || phase == .refreshing, let studentId, studentId != profile.studentNumber {
            throw APIError.notLoggedIn
        }
        verifiedIdentity = (profile, generation)
    }

    private func publishVerifiedIdentity(generation: UInt64) -> Bool {
        guard !Task.isCancelled, CookieJar.generation == generation,
              let verifiedIdentity, verifiedIdentity.generation == generation else { return false }
        let number = verifiedIdentity.value.studentNumber
        if studentId != number {
            let savedNumber = UserDefaults.standard.string(forKey: sidKey)
            studentName = savedNumber == number ? UserDefaults.standard.string(forKey: nameKey) : nil
            if savedNumber != number { UserDefaults.standard.removeObject(forKey: nameKey) }
        }
        studentId = number
        UserDefaults.standard.set(number, forKey: sidKey)
        return true
    }

    // MARK: 静默续期

    /// 带着 TGC 访问 caslogin，CAS 会自动发新 ticket 并回到教务系统
    func refresh() async {
        guard !isLoggingOut, phase != .loggedOut else { return }
        if let refreshTask { await refreshTask.value; return }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        guard !Task.isCancelled, !isLoggingOut else { return }
        let previous = phase
        let generation = CookieJar.generation
        // Keep the gate closed throughout CAS and WebKit injection: another
        // suspended loadProfile must not start a replacement prefetch meanwhile.
        await EcardTokenBridge.suspendPreparation()
        defer {
            EcardTokenBridge.resumePreparation()
            if CookieJar.generation == generation, !Task.isCancelled, !isLoggingOut,
               phase == .loggedIn, let account = studentId, !account.isEmpty {
                prepareEcardSession(account, WebStore.dataStore)
            }
        }
        guard CookieJar.generation == generation, !Task.isCancelled, !isLoggingOut else { return }
        // 启动验证结束前不展示 MainTabs，避免页面拿过期 Cookie 抢先加载。
        if previous != .checking { phase = .refreshing }
        lastError = nil

        do {
            let http = try await rawGet(URL(string: Self.serviceURL)!)
            guard let final = http.url, final.host == "tls.ccsut.cn",
                  !APIClient.isAuthenticationURL(final) else { throw APIError.notLoggedIn }
            try await verifySession()
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            guard publishVerifiedIdentity(generation: generation) else { return }
            phase = .loggedIn
            lastError = nil
            await injectToWebKit(allCookies())
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            await loadProfile()
        } catch {
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            lastError = error.localizedDescription
            // 冷启动无论哪种失败都回到可重试的登录页；已进入主界面时，
            // 仅暂时网络失败保留主界面，明确失效的认证则回到登录页。
            if let e = error as? APIError, case .notLoggedIn = e {
                phase = .loggedOut
            } else {
                phase = previous == .loggedIn ? .loggedIn : .loggedOut
            }
        }
    }

    /// TGC 剩余不足 3 天时主动续期
    func refreshIfNeeded() async {
        guard let days = tgcRemainingDays, days < 3 else { return }
        await refresh()
    }

    // MARK: 登录成功后接管

    /// 登录完成后接管 WebView 的 Cookie
    ///
    /// 关键：WKWebsiteDataStore 的 Cookie 写入是异步的，
    /// didFinish 回调的瞬间去读经常是空的，这里轮询等最多 2 秒。
    @discardableResult
    func adoptCookies() async -> Bool {
        guard !isLoggingOut else { return false }
        if let adoptionTask { return await adoptionTask.value }
        let task = Task { await performAdoption() }
        adoptionTask = task
        let result = await task.value
        adoptionTask = nil
        return result
    }

    func cancelLogin() { adoptionTask?.cancel() }

    private func performAdoption() async -> Bool {
        guard !Task.isCancelled, !isLoggingOut else { return false }
        var cookies: [HTTPCookie] = []
        let initialGeneration = CookieJar.generation

        // 注意：不能以「拿到任意一条 Cookie」为结束条件。
        // 打开 CAS 登录页的瞬间就会有一条 JSESSIONID，
        // 那时还停在登录页，必须等真正代表登录态的 Cookie 出现。
        var authenticated = false
        for attempt in 0..<24 {
            do {
                cookies = try await WebStore.dataStore.httpCookieStore.cookieSnapshot()
                    .filter { CookieJar.isSchoolCookie($0) && ($0.expiresDate ?? .distantFuture) > Date() }
            } catch {
                if !Task.isCancelled { lastError = "读取登录凭证失败，请重试" }
                return false
            }
            guard CookieJar.generation == initialGeneration, !Task.isCancelled else { return false }

            let keys = Set(cookies.map(\.name))
            authenticated = keys.contains("jw_uf")

            if authenticated { break }
            if attempt < 23 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        lastCookieCount = cookies.count

        guard !cookies.isEmpty else {
            lastError = "WebView 里没有任何 ccsut.cn 的 Cookie"
            return false
        }

        guard authenticated else {
            lastError = "登录还没有完成"
            return false
        }

        // 验证前仅替换内存；失败恢复旧凭证，成功再提交（含验证中轮换的值）。
        let previous = CookieJar.shared
        CookieJar.replace(cookies, persistChanges: false)
        let generation = CookieJar.generation

        // 真正验证一次：能不能取得当前身份的业务数据。
        guard await probe() else {
            if CookieJar.generation == generation { CookieJar.shared = previous }
            return false
        }
        guard CookieJar.generation == generation, !Task.isCancelled else { return false }
        CookieJar.commit(generation: generation)
        guard publishVerifiedIdentity(generation: generation) else { return false }
        phase = .loggedIn
        lastError = nil
        Task {
            guard CookieJar.generation == generation, !isLoggingOut else { return }
            await loadProfile()
        }
        return CookieJar.generation == generation && !Task.isCancelled
    }

    /// Publish independently verified identity first. Elective metadata is only
    /// optional name enrichment; campus identity supplies a read-only fallback
    /// when the elective channel is closed or omits the name.
    func loadProfile() async {
        guard !isLoggingOut, phase == .loggedIn || phase == .refreshing,
              !CookieJar.shared.isEmpty else { return }
        let generation = CookieJar.generation
        do {
            if verifiedIdentity?.generation != generation { try await verifySession() }
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            guard publishVerifiedIdentity(generation: generation), let account = studentId else { return }
            prepareEcardSession(account, WebStore.dataStore)

            var electiveName: String?
            if let initData = try? await api.electiveInit() {
                guard CookieJar.generation == generation, !Task.isCancelled else { return }
                // A repeated account is optional, but an explicit mismatch is
                // never allowed to enrich the currently authenticated account.
                guard initData.xsxh == nil || initData.xsxh == account else { return }
                if let name = initData.xsxm?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty {
                    electiveName = name
                }
            }

            guard CookieJar.generation == generation, !Task.isCancelled, studentId == account else { return }
            if let name = electiveName {
                studentName = name
                UserDefaults.standard.set(name, forKey: nameKey)
                return
            }

            // Preserve a same-account name already in memory or on disk. The
            // resolver is only needed when no usable optional name is known.
            guard studentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                  let studentNameResolver else { return }
            guard let resolved = await studentNameResolver(account, generation),
                  CookieJar.generation == generation, !Task.isCancelled,
                  studentId == account,
                  resolved.account == account, resolved.generation == generation,
                  studentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return }
            let name = resolved.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.rangeOfCharacter(from: .controlCharacters) == nil else { return }
            studentName = name
            UserDefaults.standard.set(name, forKey: nameKey)
        } catch {
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            lastError = "拉取学生信息失败：\(error.localizedDescription)"
        }
    }

    // MARK: Cookie 存取

    func allCookies() -> [HTTPCookie] {
        CookieJar.shared
    }

    private func restoreFromKeychain() -> [HTTPCookie] {
        guard let data = Keychain.load(cookieKey),
              let stored = try? JSONDecoder().decode([StoredCookie].self, from: data)
        else { return [] }
        return stored.compactMap(\.asHTTPCookie).filter { CookieJar.isSchoolCookie($0) && ($0.expiresDate ?? .distantFuture) > Date() }
    }

    private func injectToWebKit(_ cookies: [HTTPCookie]) async {
        do {
            try await WebStore.restoreCookies(cookies, to: WebStore.dataStore, policy: .replaceExisting)
        } catch is CancellationError {
            return
        } catch {
            // Native verification already succeeded; retain that login and let
            // payment startup retry the missing WebKit credentials separately.
            lastError = "恢复校园网页认证失败，请在缴费页重新加载"
        }
    }

    // MARK: 退出

    func logout() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        defer { isLoggingOut = false }
        refreshTask?.cancel()
        adoptionTask?.cancel()
        CookieJar.shared = []
        EcardTokenBridge.clearCachedToken()
        Keychain.delete(cookieKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: sidKey)
        UserDefaults.standard.removeObject(forKey: "ccsut.teachingWeek.v1")
        studentName = nil
        studentId = nil
        verifiedIdentity = nil
        lastError = nil
        lastCookieCount = 0
        // 等待所有可能写 WebKit 的任务结束，再做最终清理。
        // 登录页也在清理完成后才出现，避免它接管尚未删除的旧 Cookie。
        await refreshTask?.value
        _ = await adoptionTask?.value

        for c in HTTPCookieStorage.shared.cookies ?? [] where CookieJar.isSchoolCookie(c) {
            HTTPCookieStorage.shared.deleteCookie(c)
        }

        let store = WebStore.dataStore.httpCookieStore
        // 退出后新建的登录页使用全新的内存 Cookie Store。旧回调即使迟到，
        // 也只能写旧实例；Keychain 是跨启动保存凭证的唯一位置。
        WebStore.dataStore = .nonPersistent()
        do {
            for c in try await store.cookieSnapshot() where CookieJar.isSchoolCookie(c) {
                try await store.remove(c)
            }
        } catch {
            // 新登录已隔离到新 Store，旧实例回收后凭证一并丢弃。
        }

        CookieJar.shared = []
        phase = .loggedOut
    }
}

// MARK: - UA

enum UserAgent {
    static let mobile =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
}


// MARK: - WebKit 数据仓库
//
// 单独放全局：@MainActor 隔离的类里放 static let 会让 SwiftUI View 的
// init() 无法访问（init 不保证在 MainActor 上）。

/// 全局 Cookie 池
///
/// 为什么需要它：WebView 里的 Cookie 通过 HTTPCookieStorage.shared.setCookie
/// 注入给 URLSession 时会被静默拒绝一部分（实测 12 条只进去 3 条，
/// jw_uf / username / puid 全丢），导致 listV2 能过、listjxbDataV2 返回空。
/// 所以请求时直接从这个池子取，不依赖 HTTPCookieStorage。
/// 阻止 URLSession 自动跟随重定向，交给 rawGet 手动处理
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum CookieJar {
    struct RequestCookies {
        let hasCookies: Bool
        let header: String?
    }

    private static let lock = NSRecursiveLock()
    private nonisolated(unsafe) static var cookies: [HTTPCookie] = []
    private nonisolated(unsafe) static var revision: UInt64 = 0
    private nonisolated(unsafe) static var shouldPersist = true

    /// 只允许这里维护原生 Cookie；替换账号或退出时递增代数，丢弃迟到响应。
    static var shared: [HTTPCookie] {
        get {
            lock.lock(); defer { lock.unlock() }
            return cookies.filter { isSchoolCookie($0) && ($0.expiresDate ?? .distantFuture) > Date() }
        }
        set {
            replace(newValue)
        }
    }

    static func replace(_ value: [HTTPCookie], persistChanges: Bool = true) {
        lock.lock(); defer { lock.unlock() }
        revision &+= 1
        shouldPersist = persistChanges
        cookies = value.filter { isSchoolCookie($0) && ($0.expiresDate ?? .distantFuture) > Date() }
        if shouldPersist { persist() }
    }

    static func commit(generation: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard generation == revision else { return }
        shouldPersist = true
        persist()
    }

    static var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return revision
    }

    static func isSchoolCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
        return domain == "ccsut.cn" || domain.hasSuffix(".ccsut.cn")
    }

    static func header(for host: String) -> String? {
        guard let url = URL(string: "https://\(host)/") else { return nil }
        return header(for: url)
    }

    static func header(for url: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        return makeHeader(for: url, cookies: activeCookiesLocked)
    }

    /// Validates the generation and derives the matching Cookie header under one lock.
    /// A caller must never check `generation` separately from reading this header.
    static func requestCookies(for url: URL, expectedGeneration: UInt64) throws -> RequestCookies {
        lock.lock(); defer { lock.unlock() }
        guard expectedGeneration == revision else { throw CancellationError() }
        let activeCookies = activeCookiesLocked
        return RequestCookies(
            hasCookies: !activeCookies.isEmpty,
            header: makeHeader(for: url, cookies: activeCookies)
        )
    }

    static func header(for url: URL, expectedGeneration: UInt64) throws -> String? {
        try requestCookies(for: url, expectedGeneration: expectedGeneration).header
    }

    /// Keep scope metadata and validate ownership under the same lock for SSO overlays.
    static func scopedCookies(for url: URL, expectedGeneration: UInt64) throws -> [HTTPCookie] {
        lock.lock(); defer { lock.unlock() }
        guard expectedGeneration == revision else { throw CancellationError() }
        return matchingCookies(for: url, cookies: activeCookiesLocked)
    }

    private static var activeCookiesLocked: [HTTPCookie] {
        cookies.filter { isSchoolCookie($0) && ($0.expiresDate ?? .distantFuture) > Date() }
    }

    private static func makeHeader(for url: URL, cookies: [HTTPCookie]) -> String? {
        let matched = matchingCookies(for: url, cookies: cookies)
        guard !matched.isEmpty else { return nil }
        return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private static func matchingCookies(for url: URL, cookies: [HTTPCookie]) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        return cookies.filter { c in
            let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            let domainMatches = host == d || (c.domain.hasPrefix(".") && host.hasSuffix("." + d))
            let pathMatches = path == c.path || (path.hasPrefix(c.path) &&
                (c.path.hasSuffix("/") || path.dropFirst(c.path.count).hasPrefix("/")))
            return domainMatches && pathMatches && (!c.isSecure || url.scheme == "https")
        }.sorted { $0.path.count > $1.path.count }
    }

    static var names: [String] { shared.map(\.name).sorted() }

    /// 脱敏指纹：只露长度和首尾，用于对比是不是同一个值
    static func fingerprint(_ name: String) -> String {
        guard let c = shared.first(where: { $0.name == name }) else { return "缺失" }
        let v = c.value
        guard v.count > 8 else { return "\(v.count)字 \(v)" }
        return "\(v.count)字 \(v.prefix(4))…\(v.suffix(4))"
    }

    /// 按 (name, domain, path) 覆盖或追加。
    /// 服务端每次响应都可能轮换 jw_uf，不更新的话会一直用登录那一刻的旧值。
    static func upsert(_ cookie: HTTPCookie) {
        upsert([cookie])
    }

    static func upsert(_ incoming: [HTTPCookie], generation: UInt64? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let generation, generation != revision { return }
        let key: (HTTPCookie) -> String = {
            let domain = $0.domain.lowercased()
            let normalized = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            return "\($0.name)|\(normalized)|\($0.path)"
        }
        for cookie in incoming where isSchoolCookie(cookie) {
            cookies.removeAll { key($0) == key(cookie) }
            if (cookie.expiresDate ?? .distantFuture) > Date() { cookies.append(cookie) }
        }
        cookies.removeAll { ($0.expiresDate ?? .distantFuture) <= Date() }
        if !incoming.isEmpty, shouldPersist { persist() }
    }

    /// 在锁内落盘，退出和响应轮换不会交错写回旧凭证。
    private static func persist() {
        guard !cookies.isEmpty else { Keychain.delete("ccsut.cookies.v2"); return }
        guard let data = try? JSONEncoder().encode(cookies.map(StoredCookie.init)) else { return }
        Keychain.save(data, for: "ccsut.cookies.v2")
    }
}

enum WebStore {
    nonisolated(unsafe) static var dataStore: WKWebsiteDataStore = .nonPersistent()

    @MainActor static func restoreCookies(_ cookies: [HTTPCookie], to store: WKWebsiteDataStore,
                                         policy: WebSessionCookies.Policy) async throws {
        let generation = CookieJar.generation
        try await WebSessionCookies.restore(cookies, policy: policy,
            read: { try await store.httpCookieStore.cookieSnapshot() },
            write: { try await store.httpCookieStore.set($0) },
            isCurrent: { CookieJar.generation == generation })
    }
}
