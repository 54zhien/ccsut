import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class CookieStoreProbe {
    var cookies: [HTTPCookie] = []
    var writes = 0
    var reads = 0
    var writeFailures = 0
    var readFailures = 0
    var dropWrites = false
    var current = true
    var afterWrite: (() -> Void)?

    private func identity(_ cookie: HTTPCookie) -> String {
        let domain = cookie.domain.lowercased()
        let normalizedDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return "\(cookie.name)|\(normalizedDomain)|\(cookie.path)"
    }

    func read() throws -> [HTTPCookie] {
        reads += 1
        if readFailures > 0 { readFailures -= 1; throw URLError(.timedOut) }
        return cookies
    }
    func write(_ cookie: HTTPCookie) throws {
        writes += 1
        if writeFailures > 0 { writeFailures -= 1; throw URLError(.timedOut) }
        if !dropWrites {
            cookies.removeAll { identity($0) == identity(cookie) }
            cookies.append(cookie)
        }
        afterWrite?()
    }
}

@main struct WebSessionCookieTests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        func cookie(_ name: String = "TGC", value: String = "fixture", expires: Date? = nil,
                    domain: String = "auth.ccsut.cn") -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE"
            ]
            if let expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)!
        }
        func restore(_ cookies: [HTTPCookie], _ store: CookieStoreProbe,
                     _ policy: WebSessionCookies.Policy = .replaceExisting) async throws {
            try await WebSessionCookies.restore(cookies, policy: policy,
                read: { try store.read() }, write: { try store.write($0) }, isCurrent: { store.current })
        }

        let sessionCookie = cookie()
        let empty = CookieStoreProbe()
        try await restore([sessionCookie], empty)
        check(empty.cookies.first?.value == "fixture" && empty.cookies.first?.expiresDate == nil,
              "session-only TGC is restored without treating missing expiry as expiration")

        let transient = CookieStoreProbe(); transient.writeFailures = 1
        try await restore([sessionCookie], transient)
        check(transient.writes == 2 && transient.cookies.count == 1, "one failed write is retried and verified")

        let transientRead = CookieStoreProbe(); transientRead.readFailures = 1
        try await restore([sessionCookie], transientRead, .fillMissing)
        check(transientRead.cookies.count == 1, "one failed snapshot is retried")

        let dropped = CookieStoreProbe(); dropped.dropWrites = true
        do { try await restore([sessionCookie], dropped); check(false, "silently dropped writes must fail") }
        catch { check(error is WebSessionCookies.SyncError && dropped.writes == 2, "silently dropped writes fail after one retry") }

        let permanent = CookieStoreProbe(); permanent.writeFailures = 10
        do { try await restore([sessionCookie], permanent); check(false, "permanent failure must propagate") }
        catch { check(error is WebSessionCookies.SyncError && permanent.writes == 2, "permanent failure is bounded and retryable") }

        let newer = CookieStoreProbe(); newer.cookies = [cookie(value: "rotated-in-webkit")]
        try await restore([sessionCookie, cookie("gateway")], newer, .fillMissing)
        check(newer.cookies.first(where: { $0.name == "TGC" })?.value == "rotated-in-webkit" && newer.writes == 1,
              "payment startup fills missing credentials without overwriting newer WebKit cookies")

        let normalizedDomain = CookieStoreProbe()
        normalizedDomain.cookies = [cookie(value: "rotated-in-webkit", domain: ".AUTH.CCSUT.CN")]
        try await restore([sessionCookie], normalizedDomain, .fillMissing)
        check(normalizedDomain.cookies.first?.value == "rotated-in-webkit" && normalizedDomain.writes == 0,
              "fillMissing preserves a live cookie when WebKit normalizes its domain identity")

        try await restore([sessionCookie], newer)
        check(newer.cookies.first(where: { $0.name == "TGC" })?.value == "fixture", "bootstrap replaces stale WebKit credentials")

        let expired = CookieStoreProbe(); expired.cookies = [cookie(value: "expired", expires: Date(timeIntervalSinceNow: -60))]
        try await restore([sessionCookie], expired, .fillMissing)
        check(expired.cookies.first?.value == "fixture", "expired WebKit cookie does not block restoration")

        let switched = CookieStoreProbe(); switched.afterWrite = { switched.current = false }
        do { try await restore([sessionCookie, cookie("gateway")], switched); check(false, "account switch must cancel") }
        catch { check(error is CancellationError && switched.writes == 1, "account switch stops subsequent writes and retries") }

        let cancelled = CookieStoreProbe()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await restore([sessionCookie], cancelled)
        }
        do { try await task.value; check(false, "task cancellation must stop restoration") }
        catch { check(error is CancellationError && cancelled.writes == 0, "cancelled task never writes credentials") }

        for (url, expected) in [
            ("https://auth.ccsut.cn/backstage/cas/login?ticket=fixture#secret", EcardAuthenticationStage.cas),
            ("https://zts.ccsut.cn/path?token=fixture", .gateway),
            ("https://ecard.ccsut.cn/plat/login", .portal),
            ("https://ecard.ccsut.cn/charge-app/?token=fixture", .payment),
            ("https://ecard.ccsut.cn.attacker.invalid/plat/login?token=fixture", .unknown),
            ("https://ecard.ccsut.cn:444/plat/login", .unknown),
            ("http://auth.ccsut.cn/", .unknown)
        ] {
            let stage = EcardAuthenticationStage(url: URL(string: url))
            check(stage == expected && !stage.label.contains("fixture"), "timeout classification exposes only a fixed stage label")
        }
        check(EcardAuthenticationStage(url: nil) == .starting, "no navigation is reported as the initial stage")
        print("Web session cookie failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
