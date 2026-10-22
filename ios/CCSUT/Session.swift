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

    private let cookieKey = "ccsut.cookies.v2"

    // MARK: 冷启动

    func bootstrap() async {
        phase = .checking
        lastError = nil

        let restored = restoreFromKeychain()
        guard !restored.isEmpty else {
            phase = .loggedOut
            return
        }

        await injectToWebKit(restored)
        injectToURLSession(restored)

        if await probe() {
            phase = .loggedIn
            await refreshIfNeeded()
        } else if restored.contains(where: { $0.name == "TGC" }) {
            await refresh()
        } else {
            phase = .loggedOut
        }
    }

    // MARK: 探测

    /// GET /admin/ —— 被 303 到 /admin/login 就说明会话没了
    func probe() async -> Bool {
        var req = URLRequest(url: Self.jwBase.appending(path: "admin/"))
        req.timeoutInterval = 15
        req.setValue(UserAgent.mobile, forHTTPHeaderField: "User-Agent")

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let final = resp.url?.absoluteString ?? ""
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

        var req = URLRequest(url: URL(string: Self.serviceURL)!)
        req.timeoutInterval = 20
        req.setValue(UserAgent.mobile, forHTTPHeaderField: "User-Agent")

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let final = resp.url?.absoluteString ?? ""
            if final.contains("/admin/login") || final.contains("loginFailPage") {
                phase = .loggedOut
                return
            }
            persistCurrentCookies()
            phase = .loggedIn
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

    func adoptCookies() async {
        let cookies = await WebStore.dataStore.httpCookieStore.allCookies()
            .filter { $0.domain.contains("ccsut.cn") }
        guard !cookies.isEmpty else {
            lastError = "没有拿到 Cookie"
            return
        }

        persist(cookies)
        await injectToWebKit(cookies)
        injectToURLSession(cookies)
        phase = .loggedIn
        await loadProfile()
    }

    /// 顺手把姓名学号读出来（/admin/xsd/xk/listV2 里有）
    func loadProfile() async {
        do {
            let initData: ElectiveInit = try await APIClient.shared.electiveInit()
            studentName = initData.xsxm
            studentId = initData.xsxh
        } catch {
            // 拿不到不影响主流程
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

enum WebStore {
    static let dataStore: WKWebsiteDataStore = .default()
}
