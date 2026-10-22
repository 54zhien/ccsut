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
        SecItemDelete(base as CFDictionary)

        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
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
        return HTTPCookie(properties: p)
    }
}

// MARK: - WKHTTPCookieStore async 包装

extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { c in getAllCookies { c.resume(returning: $0) } }
    }

    func set(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            setCookie(cookie) { c.resume() }
        }
    }

    /// deleteCookie 在新 SDK 里已改名为 delete，这里换个名字避免递归
    func remove(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            delete(cookie) { c.resume() }
        }
    }
}

// MARK: - SessionStore

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

    /// Cookie 数据仓库统一从 WebStore 取（见文件底部）

    /// 专用 session：关闭自动 Cookie 管理，Cookie 全部由 CookieJar 手写
    private static let rawSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg,
                          delegate: NoRedirect(),
                          delegateQueue: nil)
    }()

    private let cookieKey = "ccsut.cookies.v2"
    private let nameKey = "ccsut.student.name"
    private let sidKey = "ccsut.student.id"

    // MARK: 冷启动

    func bootstrap() async {
        phase = .checking
        lastError = nil

        let restored = restoreFromKeychain()
        if !restored.isEmpty { CookieJar.shared = restored }
        guard !restored.isEmpty else {
            phase = .loggedOut
            return
        }

        await injectToWebKit(restored)
        injectToURLSession(restored)

        if await probe() {
            phase = .loggedIn
            await loadProfile()
            await refreshIfNeeded()
        } else if restored.contains(where: { $0.name == "TGC" }) {
            await refresh()
        } else {
            phase = .loggedOut
        }
    }

    // MARK: 探测

    /// 发一个带 CookieJar 的请求，手动跟随重定向。
    ///
    /// 为什么要手动跟：续期要从 tls.ccsut.cn 跳到 auth.ccsut.cn 再跳回来，
    /// 而 TGC 属于 auth.ccsut.cn 域。关闭 URLSession 自动 Cookie 后，
    /// 自动重定向不会按新 host 补 Cookie，TGC 就永远发不出去。
    private func rawGet(_ url: URL, timeout: TimeInterval = 20, maxHops: Int = 8) async throws -> HTTPURLResponse {
        var current = url
        var last: HTTPURLResponse?

        for _ in 0..<maxHops {
            var req = URLRequest(url: current)
            req.timeoutInterval = timeout
            req.setValue(UserAgent.mobile, forHTTPHeaderField: "User-Agent")
            req.setValue("https://tls.ccsut.cn/frontend/views/student/xkPage/index.html",
                         forHTTPHeaderField: "Referer")

            // 按当前这一跳的 host 取 Cookie —— TGC 在 auth.ccsut.cn，jw_uf 在 tls.ccsut.cn
            if let host = current.host, let cookie = CookieJar.header(for: host) {
                req.setValue(cookie, forHTTPHeaderField: "Cookie")
            }

            let (_, resp) = try await Self.rawSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.http(-1) }
            last = http

            // 收 Set-Cookie
            if let fields = http.allHeaderFields as? [String: String] {
                let fresh = HTTPCookie.cookies(withResponseHeaderFields: fields, for: current)
                if !fresh.isEmpty { CookieJar.upsert(fresh) }
            }

            // 3xx → 下一跳
            if (300..<400).contains(http.statusCode),
               let loc = http.value(forHTTPHeaderField: "Location"),
               let next = URL(string: loc, relativeTo: current) {
                current = next
                continue
            }
            return http
        }
        guard let last else { throw APIError.http(-1) }
        return last
    }

    /// GET /admin/ —— 被 303 到 /admin/login 就说明会话没了
    func probe() async -> Bool {
        do {
            let http = try await rawGet(Self.jwBase.appending(path: "admin/"), timeout: 15)
            let final = http.url?.absoluteString ?? ""
            let ok = !final.contains("/admin/login") && !final.contains("loginFailPage")
            if ok { persistCurrentCookies() }
            return ok
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: 静默续期

    /// 带着 TGC 访问 caslogin，CAS 会自动发新 ticket 并回到教务系统
    func refresh() async {
        guard phase != .refreshing else { return }
        let previous = phase
        phase = .refreshing

        do {
            let http = try await rawGet(URL(string: Self.serviceURL)!)
            let final = http.url?.absoluteString ?? ""
            if final.contains("/admin/login") || final.contains("loginFailPage") {
                phase = .loggedOut
                return
            }
            persistCurrentCookies()
            phase = .loggedIn
            await loadProfile()
        } catch {
            lastError = error.localizedDescription
            phase = previous == .refreshing ? .loggedOut : previous
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
        var cookies: [HTTPCookie] = []

        // 注意：不能以「拿到任意一条 Cookie」为结束条件。
        // 打开 CAS 登录页的瞬间就会有一条 JSESSIONID，
        // 那时还停在登录页，必须等真正代表登录态的 Cookie 出现。
        var authenticated = false
        for attempt in 0..<24 {
            cookies = await WebStore.dataStore.httpCookieStore.allCookies()
                .filter { $0.domain.contains("ccsut.cn") }

            let keys = Set(cookies.map(\.name))
            authenticated = keys.contains("jw_uf")
                || keys.contains("puid")
                || keys.contains("username")

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

        CookieJar.shared = cookies

        // 先只注入到内存，验证通过才落盘。
        // 否则一条残缺的 JSESSIONID 会把 Keychain 里完整的 Cookie 覆盖掉。
        await injectToWebKit(cookies)
        injectToURLSession(cookies)

        // 真正验证一次：能不能访问 /admin/
        guard await probe() else {
            lastError = "Cookie 只有 \(cookies.count) 条（\(cookies.map(\.name).joined(separator: ","))），没有登录态"
            return false
        }

        persist(cookies)
        CookieJar.shared = cookies
        phase = .loggedIn
        lastError = nil
        await loadProfile()
        return true
    }

    /// 顺手把姓名学号读出来（/admin/xsd/xk/listV2 里有）
    func loadProfile() async {
        // 先用缓存顶上，避免冷启动时「我的」页空白
        if studentName == nil { studentName = UserDefaults.standard.string(forKey: nameKey) }
        if studentId == nil { studentId = UserDefaults.standard.string(forKey: sidKey) }

        do {
            let initData: ElectiveInit = try await APIClient.shared.electiveInit()
            if let name = initData.xsxm, !name.isEmpty {
                studentName = name
                UserDefaults.standard.set(name, forKey: nameKey)
            }
            if let sid = initData.xsxh, !sid.isEmpty {
                studentId = sid
                UserDefaults.standard.set(sid, forKey: sidKey)
            }
        } catch {
            lastError = "拉取学生信息失败：\(error.localizedDescription)"
        }
    }

    // MARK: Cookie 存取

    func allCookies() -> [HTTPCookie] {
        (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.contains("ccsut.cn") }
    }

    private func persist(_ cookies: [HTTPCookie]) {
        guard let data = try? JSONEncoder().encode(cookies.map(StoredCookie.init)) else { return }
        Keychain.save(data, for: cookieKey)
    }

    private func persistCurrentCookies() {
        let fresh = allCookies()
        guard !fresh.isEmpty else { return }
        persist(fresh)
    }

    private func restoreFromKeychain() -> [HTTPCookie] {
        guard let data = Keychain.load(cookieKey),
              let stored = try? JSONDecoder().decode([StoredCookie].self, from: data)
        else { return [] }
        return stored.compactMap(\.asHTTPCookie)
    }

    private func injectToWebKit(_ cookies: [HTTPCookie]) async {
        for c in cookies {
            await WebStore.dataStore.httpCookieStore.set(c)
        }
    }

    private func injectToURLSession(_ cookies: [HTTPCookie]) {
        for host in ["https://tls.ccsut.cn", "https://auth.ccsut.cn"] {
            guard let url = URL(string: host) else { continue }
            HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: nil)
        }
    }

    // MARK: 退出

    func logout() async {
        Keychain.delete(cookieKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: sidKey)
        studentName = nil
        studentId = nil

        for c in HTTPCookieStorage.shared.cookies ?? [] where c.domain.contains("ccsut.cn") {
            HTTPCookieStorage.shared.deleteCookie(c)
        }

        let store = WebStore.dataStore.httpCookieStore
        for c in await store.allCookies() where c.domain.contains("ccsut.cn") {
            await store.remove(c)
        }

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
    nonisolated(unsafe) static var shared: [HTTPCookie] = []

    static func header(for host: String) -> String? {
        let matched = shared.filter { c in
            let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            return host == d || host.hasSuffix("." + d)
        }
        guard !matched.isEmpty else { return nil }
        return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    static var names: [String] { shared.map(\.name).sorted() }

    /// 按 (name, domain, path) 覆盖或追加。
    /// 服务端每次响应都可能轮换 jw_uf，不更新的话会一直用登录那一刻的旧值。
    static func upsert(_ cookie: HTTPCookie) {
        let key: (HTTPCookie) -> String = { "\($0.name)|\($0.domain)|\($0.path)" }
        let k = key(cookie)
        if let idx = shared.firstIndex(where: { key($0) == k }) {
            shared[idx] = cookie
        } else {
            shared.append(cookie)
        }
    }

    static func upsert(_ cookies: [HTTPCookie]) {
        for c in cookies { upsert(c) }
    }
}

enum WebStore {
    static let dataStore: WKWebsiteDataStore = .default()
}
