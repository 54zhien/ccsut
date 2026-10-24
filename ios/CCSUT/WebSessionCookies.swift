import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Credential synchronization only; never logs cookie names, values or URLs.
@MainActor enum WebSessionCookies {
    enum Policy { case replaceExisting, fillMissing }
    enum SyncError: Error { case incomplete }

    static func restore(_ cookies: [HTTPCookie], policy: Policy,
                        read: () async throws -> [HTTPCookie],
                        write: (HTTPCookie) async throws -> Void,
                        isCurrent: () -> Bool) async throws {
        func checkCurrent() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }
        func key(_ cookie: HTTPCookie) -> String {
            let domain = cookie.domain.lowercased()
            let normalizedDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            return "\(cookie.name)|\(normalizedDomain)|\(cookie.path)"
        }
        var expected: [HTTPCookie]?
        for attempt in 0..<2 {
            try checkCurrent()
            do {
                if expected == nil {
                    if policy == .fillMissing {
                        let existing = try await read()
                        try checkCurrent()
                        let keys = Set(existing.filter { ($0.expiresDate ?? .distantFuture) > Date() }.map(key))
                        expected = cookies.filter { !keys.contains(key($0)) }
                    } else {
                        expected = cookies
                    }
                }
                for cookie in expected ?? [] {
                    try checkCurrent()
                    try await write(cookie)
                    try checkCurrent()
                }
                let actual = try await read()
                try checkCurrent()
                guard (expected ?? []).allSatisfy({ cookie in
                    actual.contains { key($0) == key(cookie) && $0.value == cookie.value &&
                        ($0.expiresDate ?? .distantFuture) > Date() }
                }) else { throw SyncError.incomplete }
                return
            } catch {
                try checkCurrent()
                if error is CancellationError { throw error }
                if attempt == 1 { throw SyncError.incomplete }
            }
        }
    }
}

/// Fixed labels only. Never retain a URL containing a CAS ticket or JWT.
enum EcardAuthenticationStage: Sendable {
    case starting, cas, gateway, portal, payment, unknown

    init(url: URL?) {
        guard let url else { self = .starting; return }
        guard url.scheme?.lowercased() == "https", url.port == nil || url.port == 443 else {
            self = .unknown; return
        }
        switch url.host?.lowercased() {
        case "auth.ccsut.cn": self = .cas
        case "zts.ccsut.cn": self = .gateway
        case "ecard.ccsut.cn":
            if url.path == "/plat" || url.path.hasPrefix("/plat/") { self = .portal }
            else if url.path == "/charge-app" || url.path.hasPrefix("/charge-app/") { self = .payment }
            else { self = .unknown }
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .starting: "连接一卡通"
        case .cas: "学校统一认证"
        case .gateway: "学校访问网关"
        case .portal: "一卡通门户"
        case .payment: "缴费凭证获取"
        case .unknown: "校园认证跳转"
        }
    }
}
