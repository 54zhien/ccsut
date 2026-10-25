import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FixtureCredentials: CampusSessionCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 1
    private var receivedCookies = 0
    private var switchOnHeader = false
    private var sessionValue = "fixture-session"
    var generation: UInt64 { lock.lock(); defer { lock.unlock() }; return revision }
    func replaceAccount() { lock.lock(); defer { lock.unlock() }; revision += 1 }
    func armAccountSwitch() { lock.lock(); defer { lock.unlock() }; switchOnHeader = true }
    func header(for url: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        if switchOnHeader { switchOnHeader = false; revision += 1 }
        return url.host == "auth.ccsut.cn" ? "TGC=fixture-tgc" : "ehall=\(sessionValue)"
    }
    func header(for url: URL, expectedGeneration: UInt64) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if switchOnHeader { switchOnHeader = false; revision += 1 }
        guard expectedGeneration == revision else { throw CancellationError() }
        return url.host == "auth.ccsut.cn" ? "TGC=fixture-tgc" : "ehall=\(sessionValue)"
    }
    func accept(_ cookies: [HTTPCookie], generation: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if generation == revision {
            receivedCookies += cookies.count
            if let session = cookies.last(where: { $0.name == "ehall" }) { sessionValue = session.value }
        }
    }
    var accepted: Int { lock.lock(); defer { lock.unlock() }; return receivedCookies }
    func scopedCookies(for url: URL, expectedGeneration: UInt64) throws -> [HTTPCookie] {
        guard let header = try header(for: url, expectedGeneration: expectedGeneration),
              let separator = header.firstIndex(of: "=") else { return [] }
        return [HTTPCookie(properties: [.name: String(header[..<separator]), .value: String(header[header.index(after: separator)...]),
                                      .domain: url.host!, .path: "/", .secure: "TRUE"])!]
    }
}

/// Retains real cookie scope and tombstones at the credentials boundary.
final class ScopedCampusCredentials: CampusSessionCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 1
    private var cookies: [HTTPCookie] = [
        HTTPCookie(properties: [.name: "ehall", .value: "original-root", .domain: "ehall.ccsut.cn", .path: "/"])!,
        HTTPCookie(properties: [.name: "ehall", .value: "original-narrow", .domain: "ehall.ccsut.cn", .path: "/backstage"])!,
        HTTPCookie(properties: [.name: "ehall", .value: "original-auth", .domain: "auth.ccsut.cn", .path: "/"])!
    ]
    private var publications = 0
    var generation: UInt64 { lock.lock(); defer { lock.unlock() }; return revision }
    var accepted: Int { lock.lock(); defer { lock.unlock() }; return publications }
    func replaceAccount() { lock.lock(); defer { lock.unlock() }; revision += 1 }
    func scopedCookies(for url: URL, expectedGeneration: UInt64) throws -> [HTTPCookie] {
        lock.lock(); defer { lock.unlock() }
        guard revision == expectedGeneration else { throw CancellationError() }
        return cookies.filter { cookie in
            let path = url.path.isEmpty ? "/" : url.path
            return cookie.domain == url.host && (path == cookie.path || path.hasPrefix(cookie.path.hasSuffix("/") ? cookie.path : cookie.path + "/"))
        }.sorted { $0.path.count > $1.path.count }
    }
    func header(for url: URL, expectedGeneration: UInt64) throws -> String? {
        let matched = try scopedCookies(for: url, expectedGeneration: expectedGeneration)
        return matched.isEmpty ? nil : matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
    func accept(_ incoming: [HTTPCookie], generation: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard revision == generation else { return }
        if !incoming.isEmpty { publications += 1 }
        for cookie in incoming {
            cookies.removeAll { $0.name == cookie.name && $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) && $0.path == cookie.path }
            if (cookie.expiresDate ?? .distantFuture) > Date() { cookies.append(cookie) }
        }
    }
}

final class RotatingCASCookieCredentials: CampusSessionCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 1
    private var cookies = [
        HTTPCookie(properties: [.name: "TGC", .value: "old-tgc", .domain: ".ccsut.cn", .path: "/", .secure: "TRUE"])!,
        HTTPCookie(properties: [.name: "ehall", .value: "old-session", .domain: "ehall.ccsut.cn", .path: "/", .secure: "TRUE"])!
    ]
    var generation: UInt64 { lock.lock(); defer { lock.unlock() }; return revision }

    func replaceAccount() {
        lock.lock(); defer { lock.unlock() }
        revision += 1
    }

    func rotateTGC(to value: String) {
        accept([HTTPCookie(properties: [.name: "TGC", .value: value, .domain: ".ccsut.cn", .path: "/", .secure: "TRUE"])!], generation: generation)
    }

    func scopedCookies(for url: URL, expectedGeneration: UInt64) throws -> [HTTPCookie] {
        lock.lock(); defer { lock.unlock() }
        guard expectedGeneration == revision else { throw CancellationError() }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.isEmpty ? "/" : url.path
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let normalized = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let domainMatches = host == normalized || (domain.hasPrefix(".") && host.hasSuffix("." + normalized))
            let pathMatches = path == cookie.path || path.hasPrefix(cookie.path.hasSuffix("/") ? cookie.path : cookie.path + "/")
            return domainMatches && pathMatches && (!cookie.isSecure || url.scheme == "https") &&
                (cookie.expiresDate ?? .distantFuture) > Date()
        }
    }

    func header(for url: URL, expectedGeneration: UInt64) throws -> String? {
        let matched = try scopedCookies(for: url, expectedGeneration: expectedGeneration)
        return matched.isEmpty ? nil : matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func accept(_ incoming: [HTTPCookie], generation: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard generation == revision else { return }
        for cookie in incoming {
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            cookies.removeAll {
                $0.name == cookie.name &&
                    $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == domain &&
                    $0.path == cookie.path
            }
            if (cookie.expiresDate ?? .distantFuture) > Date() { cookies.append(cookie) }
        }
    }
}

actor CampusFixtureBarrier {
    private var blocked = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?
    func suspend() async {
        blocked = true
        arrival?.resume(); arrival = nil
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilBlocked() async {
        if !blocked { await withCheckedContinuation { arrival = $0 } }
    }
    func release() { continuation?.resume(); continuation = nil }
}

actor FixtureCampusTransport: CampusTransport {
    typealias Handler = @Sendable (URLRequest, Int) async throws -> (Int, [String: String], String)
    let handler: Handler
    var requests: [URLRequest] = []
    init(_ handler: @escaping Handler) { self.handler = handler }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, headers, body) = try await handler(request, requests.count)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
    }
}

@main
struct CampusAPITests {
    static let identity = #"{"errcode":2000,"account":"fixture-account","userId":"fixture-user-id","data":{"access_token":"fixture-access-token","token_type":"bearer"}}"#
    static let emptyPage = #"{"data":{"list":[],"pageNum":1,"pageSize":20,"total":0,"hasNextPage":false}}"#

    static func main() async throws {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "https://ehall.ccsut.cn/backstage/page"), targetIsMainFrame: true
        ) == .allow, "official portal navigation remains allowed")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "https://auth.ccsut.cn/backstage/cas/login"), targetIsMainFrame: true
        ) == .allow, "official CAS navigation remains allowed")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "http://ehall.ccsut.cn/backstage/page"), targetIsMainFrame: true
        ) == .upgrade(URL(string: "https://ehall.ccsut.cn/backstage/page")!), "official HTTP navigation upgrades to HTTPS")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "http://ehall.ccsut.cn:80/backstage/page"), targetIsMainFrame: true
        ) == .upgrade(URL(string: "https://ehall.ccsut.cn/backstage/page")!), "default HTTP port is removed when upgrading")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "http://ehall.ccsut.cn/backstage/page"), targetIsMainFrame: false
        ) == .blocked(reportFailure: false), "HTTP subframe is cancelled without replacing the official page")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "about:blank"), targetIsMainFrame: true
        ) == .allow, "blank WebKit document remains allowed")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "https://outside.invalid/login"), targetIsMainFrame: true
        ) == .blocked(reportFailure: true), "off-domain main-frame navigation is still rejected visibly")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "https://outside.invalid/frame"), targetIsMainFrame: false
        ) == .blocked(reportFailure: false), "off-domain subframe rejection cannot fail the whole official page")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "https://outside.invalid/popup"), targetIsMainFrame: nil
        ) == .blocked(reportFailure: false), "off-domain popup is cancelled without failing the visible page")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "http://ehall.ccsut.cn:8080/backstage/page"), targetIsMainFrame: true
        ) == .blocked(reportFailure: true), "nondefault HTTP port remains rejected")
        check(CampusOfficialNavigationPolicy.decision(
            for: URL(string: "https://auth.ccsut.cn:8443/backstage/cas/login"), targetIsMainFrame: true
        ) == .blocked(reportFailure: true), "nondefault HTTPS port remains rejected")

        let credentials = FixtureCredentials()
        let success = FixtureCampusTransport { req, _ in
            if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
            return (200, [:], req.url!.path.contains("leaveadmin") ? emptyPage : #"{"code":"2000","data":[]}"#)
        }
        let client = CampusClient(account: "fixture-account", credentials: credentials, transport: success)
        _ = try await client.leaveRecords(page: 1, size: 20)
        _ = try await client.leaveRecords(page: 1, size: 20)
        _ = try await client.travelRecords(kind: .departure)
        _ = try await client.travelRecords(kind: .returning)
        let requests = await success.requests
        check(requests.filter { $0.url!.path.hasSuffix("validate_full") }.count == 2, "each subsystem validates before reading and caches identity")
        let validation = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!
        check(validation.queryItems!.first { $0.name == "callback" }!.value!.contains("leaveadmin"), "validate callback belongs to requested subsystem")
        let body = try JSONSerialization.jsonObject(with: requests[1].httpBody!) as! [String: Any]
        check((body["pageParam"] as? [String: String])?["userId"] == "fixture-user-id", "leave uses validated userId rather than account")
        let travel = requests.filter { $0.httpMethod == "POST" && $0.url!.path.contains("returnschool") }
        let travelBodies = try travel.map { try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: String] }
        check(travelBodies.allSatisfy { $0["studentId"] == "fixture-user-id" }, "both travel requests use userId as studentId")
        check(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData }, "requests do not use response cache")
        check(requests.filter { $0.httpMethod == "POST" }.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token"
        }, "all three read-only endpoints send the validated bearer token")
        check(requests.filter { $0.httpMethod != "POST" }.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == nil
        }, "validation and CAS never receive business bearer tokens")

        // A successful HTTP response can still reject the business bearer.
        for code in ["401", "\"401\""] {
            for isLeave in [true, false] {
                let rejected = "{\"code\":\(code),\"success\":false,\"errorMessage\":\"expired fixture\"}"
                let businessExpired = FixtureCampusTransport { req, index in
                    if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
                    if req.url!.path.hasSuffix("redirect") { return (200, [:], "official landing") }
                    if index == 2 { return (200, [:], rejected) }
                    return (200, [:], isLeave ? emptyPage : #"{"code":"2000","data":[]}"#)
                }
                do {
                    let c = CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: businessExpired)
                    if isLeave { _ = try await c.leaveRecords() }
                    else { _ = try await c.travelRecords(kind: .departure) }
                    let sent = await businessExpired.requests
                    check(sent.count == 5 && sent.filter { $0.httpMethod == "POST" }.count == 2,
                          "HTTP 200 business 401 renews CAS once for \(isLeave ? "leave" : "travel")")
                } catch { check(false, "HTTP 200 business 401 recovers for \(isLeave ? "leave" : "travel")") }
            }
        }
        for code in [401, 403] {
            let rejected = FixtureCampusTransport { req, _ in
                if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
                if req.url!.path.hasSuffix("redirect") { return (200, [:], "official landing") }
                return (200, [:], "{\"code\":\(code)}")
            }
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: rejected).leaveRecords()
                check(false, "permanent business rejection must fail")
            } catch {
                let sent = await rejected.requests
                check(error as? CampusError == (code == 401 ? .authentication : .forbidden) &&
                      sent.count == (code == 401 ? 5 : 2),
                      "business \(code) has bounded recovery and preserves forbidden errors")
            }
        }

        let rotated = FixtureCampusTransport { req, index in
            if req.url!.path.hasSuffix("validate_full") {
                return (200, [:], index == 1 ? identity : identity.replacingOccurrences(of: "fixture-access-token", with: "fixture-new-token"))
            }
            return index == 2 ? (401, [:], "") : (200, [:], emptyPage)
        }
        _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: rotated).leaveRecords()
        let rotatedRequests = await rotated.requests
        check(rotatedRequests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-new-token",
              "401 retry replaces the stale bearer token with revalidated credentials")

        // CAS proxy validation and the business token have independent lifetimes:
        // validate_full may still return a token which the business service rejects.
        let expiredCredentials = FixtureCredentials()
        let expired = FixtureCampusTransport { req, _ in
            let url = req.url!
            if url.path.hasSuffix("validate_full") {
                let renewed = req.value(forHTTPHeaderField: "Cookie") == "ehall=renewed-session"
                return (200, [:], renewed ? identity.replacingOccurrences(of: "fixture-access-token", with: "renewed-token") : identity)
            }
            if url.host == "auth.ccsut.cn" {
                return (302, ["Location": "https://ehall.ccsut.cn/backstage/cas-proxy/app/redirect?ticket=fixture-ticket"], "")
            }
            if url.path.hasSuffix("redirect") {
                if url.query?.contains("ticket=") == true {
                    return (200, ["Set-Cookie": "ehall=renewed-session; Secure; Path=/"], "official landing")
                }
                return (302, ["Location": "https://auth.ccsut.cn/backstage/cas/login?service=fixture"], "")
            }
            return req.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-token" ? (200, [:], emptyPage) : (401, [:], "")
        }
        do {
            let page = try await CampusClient(account: "fixture-account", credentials: expiredCredentials, transport: expired).leaveRecords()
            let sent = await expired.requests
            check(page.page == 1 && sent.last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-token",
                  "business 401 renews CAS even when validation still accepts the rejected token")
            check(sent.filter { $0.url?.host == "auth.ccsut.cn" }.count == 1 &&
                  sent.filter { $0.httpMethod == "POST" }.count == 2 &&
                  sent.filter { $0.url?.host == "auth.ccsut.cn" }.allSatisfy { $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == nil },
                  "expired read follows CAS once without forwarding its business POST or bearer")
        } catch {
            check(false, "business 401 renews CAS even when validation still accepts the rejected token")
        }

        let rotatingCredentials = RotatingCASCookieCredentials()
        let rotationDuringRenewal = FixtureCampusTransport { req, index in
            if req.url!.path.hasSuffix("validate_full") {
                let cookie = req.value(forHTTPHeaderField: "Cookie") ?? ""
                if cookie.contains("TGC=rotated-tgc") { return (200, [:], identity) }
                if cookie.contains("TGC=stale-transaction") || cookie.contains("TGC=old-tgc") {
                    let headers = index == 1
                        ? ["Set-Cookie": "TGC=stale-transaction; Domain=.ccsut.cn; Secure; Path=/"]
                        : [:]
                    return (200, headers, #"{"errcode":2001,"msg":"not authenticated"}"#)
                }
                return (200, [:], #"{"errcode":2001,"msg":"not authenticated"}"#)
            }
            if req.url!.path.hasSuffix("redirect") {
                rotatingCredentials.rotateTGC(to: "rotated-tgc")
                return (302, ["Location": "https://auth.ccsut.cn/backstage/cas/login?service=fixture"], "")
            }
            if req.url?.host == "auth.ccsut.cn" { return (200, [:], "CAS login fixture") }
            return (200, [:], emptyPage)
        }
        do {
            let rotationClient = CampusClient(account: "fixture-account", credentials: rotatingCredentials,
                                              transport: rotationDuringRenewal)
            _ = try await rotationClient.leaveRecords()
            let sent = await rotationDuringRenewal.requests
            let staleCASRequest = sent.first { $0.url?.host == "auth.ccsut.cn" }
            let freshValidation = sent.first {
                $0.url?.path.hasSuffix("validate_full") == true &&
                    $0.value(forHTTPHeaderField: "Cookie")?.contains("TGC=rotated-tgc") == true
            }
            let currentCASHeader = try rotatingCredentials.header(
                for: URL(string: "https://auth.ccsut.cn/backstage/cas/login")!, expectedGeneration: 1
            )
            let diagnostic = await rotationClient.authenticationDiagnostic
            check(sent.count == 6 && sent.filter { $0.httpMethod == "POST" }.count == 1 &&
                  sent.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token",
                  "same-account CAS cookie rotation restarts one read-auth transaction")
            check(staleCASRequest?.value(forHTTPHeaderField: "Cookie")?.contains("TGC=stale-transaction") == true &&
                  freshValidation != nil && currentCASHeader?.contains("TGC=rotated-tgc") == true &&
                  currentCASHeader?.contains("TGC=stale-transaction") == false,
                  "CAS retry discards the stale transaction overlay and reads the rotated CookieJar value")
            check(diagnostic.stage == .authenticated && diagnostic.outcome == .accepted &&
                  diagnostic.casCookiesChangedDuringAttempt,
                  "CAS diagnostic retains only a fixed stage, outcome and rotation flag")
        } catch {
            check(false, "same-account CAS cookie rotation restarts one read-auth transaction")
            check(false, "CAS retry discards the stale transaction overlay and reads the rotated CookieJar value")
            check(false, "CAS diagnostic retains only a fixed stage, outcome and rotation flag")
        }

        let twiceRotatedCredentials = RotatingCASCookieCredentials()
        let twiceRotated = FixtureCampusTransport { req, index in
            if req.url!.path.hasSuffix("validate_full") {
                if index == 1 {
                    return (200, ["Set-Cookie": "TGC=stale-one; Domain=.ccsut.cn; Secure; Path=/"],
                            #"{"errcode":2001,"msg":"not authenticated"}"#)
                }
                if index == 5 {
                    return (200, ["Set-Cookie": "TGC=stale-two; Domain=.ccsut.cn; Secure; Path=/"],
                            #"{"errcode":2001,"msg":"not authenticated"}"#)
                }
                return (200, [:], #"{"errcode":2001,"msg":"not authenticated"}"#)
            }
            if req.url!.path.hasSuffix("redirect") {
                twiceRotatedCredentials.rotateTGC(to: index == 2 ? "rotated-once" : "rotated-twice")
                return (302, ["Location": "https://auth.ccsut.cn/backstage/cas/login?service=fixture"], "")
            }
            if req.url?.host == "auth.ccsut.cn" { return (200, [:], "CAS login fixture") }
            return (200, [:], emptyPage)
        }
        let twiceRotatedClient = CampusClient(account: "fixture-account", credentials: twiceRotatedCredentials,
                                              transport: twiceRotated)
        do {
            _ = try await twiceRotatedClient.leaveRecords()
            check(false, "a second CAS-cookie rotation cannot start a third auth transaction")
        } catch {
            let sent = await twiceRotated.requests
            let currentCASHeader = try twiceRotatedCredentials.header(
                for: URL(string: "https://auth.ccsut.cn/backstage/cas/login")!, expectedGeneration: 1
            )
            let diagnostic = await twiceRotatedClient.authenticationDiagnostic
            check(error as? CampusError == .authentication && sent.count == 8 &&
                  sent.filter { $0.httpMethod == "POST" }.isEmpty &&
                  sent.filter { $0.url?.host == "auth.ccsut.cn" }.count == 2,
                  "a second CAS-cookie rotation cannot start a third auth transaction")
            check(currentCASHeader?.contains("TGC=rotated-twice") == true &&
                  currentCASHeader?.contains("TGC=stale-one") == false &&
                  currentCASHeader?.contains("TGC=stale-two") == false &&
                  diagnostic.stage == .renewedValidation && diagnostic.outcome == .rejected &&
                  diagnostic.casCookiesChangedDuringAttempt,
                  "failed bounded retry discards both stale overlays and records only the rotation flag")
        }

        let replacedDuringRetryCredentials = RotatingCASCookieCredentials()
        let replacedDuringRetry = FixtureCampusTransport { req, index in
            if req.url!.path.hasSuffix("validate_full") {
                if index == 1 {
                    return (200, ["Set-Cookie": "TGC=stale-before-retry; Domain=.ccsut.cn; Secure; Path=/"],
                            #"{"errcode":2001,"msg":"not authenticated"}"#)
                }
                if index == 5 {
                    replacedDuringRetryCredentials.replaceAccount()
                    return (200, [:], identity)
                }
                return (200, [:], #"{"errcode":2001,"msg":"not authenticated"}"#)
            }
            if req.url!.path.hasSuffix("redirect") {
                replacedDuringRetryCredentials.rotateTGC(to: "rotated-before-retry")
                return (302, ["Location": "https://auth.ccsut.cn/backstage/cas/login?service=fixture"], "")
            }
            if req.url?.host == "auth.ccsut.cn" { return (200, [:], "CAS login fixture") }
            return (200, [:], emptyPage)
        }
        let replacedDuringRetryClient = CampusClient(account: "fixture-account", credentials: replacedDuringRetryCredentials,
                                                     transport: replacedDuringRetry)
        do {
            _ = try await replacedDuringRetryClient.leaveRecords()
            check(false, "account replacement during bounded retry stops before publishing cookies or reading")
        } catch {
            let sent = await replacedDuringRetry.requests
            let currentCASHeader = try replacedDuringRetryCredentials.header(
                for: URL(string: "https://auth.ccsut.cn/backstage/cas/login")!, expectedGeneration: 2
            )
            let diagnostic = await replacedDuringRetryClient.authenticationDiagnostic
            check(error is CancellationError && sent.count == 5 && sent.filter { $0.httpMethod == "POST" }.isEmpty,
                  "account replacement during bounded retry stops before publishing cookies or reading")
            check(currentCASHeader?.contains("TGC=rotated-before-retry") == true &&
                  currentCASHeader?.contains("TGC=stale-before-retry") == false &&
                  diagnostic.stage == .initialValidation && diagnostic.outcome == .failed &&
                  diagnostic.casCookiesChangedDuringAttempt,
                  "account replacement does not commit a prior transaction overlay")
        }

        let forcedRotationCredentials = RotatingCASCookieCredentials()
        let rejectedIdentity = identity.replacingOccurrences(of: "fixture-access-token", with: "rejected-access-token")
        let freshIdentity = identity.replacingOccurrences(of: "fixture-access-token", with: "fresh-access-token")
        let forcedRotation = FixtureCampusTransport { req, index in
            let url = req.url!
            if url.path.hasSuffix("validate_full") {
                let cookie = req.value(forHTTPHeaderField: "Cookie") ?? ""
                if index == 1 { return (200, [:], rejectedIdentity) }
                if cookie.contains("TGC=stale-forced") { return (200, [:], #"{"errcode":2001,"msg":"not authenticated"}"#) }
                if cookie.contains("ehall=fresh-session") { return (200, [:], freshIdentity) }
                return (200, [:], rejectedIdentity)
            }
            if url.path.hasSuffix("redirect") {
                if url.query?.contains("ticket=") == true {
                    return (200, ["Set-Cookie": "ehall=fresh-session; Secure; Path=/"], "official landing")
                }
                if index == 3 {
                    forcedRotationCredentials.rotateTGC(to: "rotated-forced")
                    return (302, [
                        "Set-Cookie": "TGC=stale-forced; Domain=.ccsut.cn; Secure; Path=/",
                        "Location": "https://auth.ccsut.cn/backstage/cas/login?service=fixture"
                    ], "")
                }
                return (302, ["Location": "https://auth.ccsut.cn/backstage/cas/login?service=fixture"], "")
            }
            if url.host == "auth.ccsut.cn" {
                if req.value(forHTTPHeaderField: "Cookie")?.contains("TGC=rotated-forced") == true {
                    return (302, ["Location": "https://ehall.ccsut.cn/backstage/cas-proxy/app/redirect?ticket=fixture"], "")
                }
                return (200, [:], "CAS login fixture")
            }
            if req.httpMethod == "POST" {
                return req.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access-token"
                    ? (200, [:], emptyPage) : (401, [:], "")
            }
            return (200, [:], emptyPage)
        }
        let forcedRotationClient = CampusClient(account: "fixture-account", credentials: forcedRotationCredentials,
                                                transport: forcedRotation)
        do {
            _ = try await forcedRotationClient.leaveRecords()
            let sent = await forcedRotation.requests
            let validations = sent.filter { $0.url?.path.hasSuffix("validate_full") == true }
            let casRequests = sent.filter { $0.url?.host == "auth.ccsut.cn" }
            let reads = sent.filter { $0.httpMethod == "POST" }
            check(sent.count == 10 && validations.count == 3 && casRequests.count == 2 && reads.count == 2 &&
                  reads.first?.value(forHTTPHeaderField: "Authorization") == "Bearer rejected-access-token" &&
                  reads.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access-token",
                  "forced recovery after a rejected bearer renews again after concurrent CAS-cookie rotation")
            check(sent[5].url?.path.hasSuffix("redirect") == true &&
                  casRequests.first?.value(forHTTPHeaderField: "Cookie")?.contains("TGC=stale-forced") == true &&
                  casRequests.last?.value(forHTTPHeaderField: "Cookie")?.contains("TGC=rotated-forced") == true,
                  "forced rotation retry skips validation-only reuse and starts a fresh CAS redirect")
        } catch {
            check(false, "forced recovery after a rejected bearer renews again after concurrent CAS-cookie rotation")
            check(false, "forced rotation retry skips validation-only reuse and starts a fresh CAS redirect")
        }

        for loginLocation in ["https://auth.ccsut.cn/backstage/cas/login?service=fixture",
                              "/backstage/cas-proxy/app/redirect?serverName=https%3A%2F%2Fehall.ccsut.cn"] {
            let loginRedirect = FixtureCampusTransport { req, index in
                if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
                if req.url!.path.hasSuffix("redirect") { return (200, [:], "official landing") }
                return index == 2 ? (302, ["Location": loginLocation], "") : (200, [:], emptyPage)
            }
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: loginRedirect).leaveRecords()
                let sent = await loginRedirect.requests
                check(sent.filter { $0.httpMethod == "POST" }.count == 2 && sent.count == 5 &&
                      sent.allSatisfy { $0.url?.host == "ehall.ccsut.cn" },
                      "official read-login redirect renews separately and retries only the original read")
            } catch { check(false, "official read-login redirect renews separately and retries only the original read") }
        }

        for destination in ["https://outside.invalid/collect", "https://ehall.ccsut.cn/unrelated"] {
            let unsafeRedirect = FixtureCampusTransport { req, _ in
                req.url!.path.hasSuffix("validate_full") ? (200, [:], identity) : (302, ["Location": destination], "")
            }
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: unsafeRedirect).leaveRecords()
                check(false, "unrecognized read redirect is not an authentication retry")
            } catch {
                check(await unsafeRedirect.requests.count == 2, "unrecognized read redirect is not an authentication retry")
            }
        }

        let repeatedLogin = FixtureCampusTransport { req, _ in
            if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
            if req.url!.path.hasSuffix("redirect") { return (200, [:], "official landing") }
            return (302, ["Location": "https://auth.ccsut.cn/backstage/cas/login"], "")
        }
        do {
            _ = try await CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: repeatedLogin).leaveRecords()
            check(false, "repeated login redirect stops after one recovery")
        } catch {
            let sent = await repeatedLogin.requests
            check(error as? CampusError == .authentication && sent.count == 5,
                  "repeated login redirect stops after one recovery")
        }

        for wrongAccountAfterRenewal in [false, true] {
            let incompleteRenewal = FixtureCampusTransport { req, index in
                if req.url!.path.hasSuffix("validate_full") {
                    if index == 1 { return (200, [:], identity) }
                    return (200, [:], wrongAccountAfterRenewal
                        ? identity.replacingOccurrences(of: "fixture-account", with: "different-account")
                        : #"{"errcode":2001,"msg":"not authenticated"}"#)
                }
                if req.url!.path.hasSuffix("redirect") { return (200, [:], "interactive login page") }
                return (401, [:], "")
            }
            let incompleteClient = CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: incompleteRenewal)
            do {
                _ = try await incompleteClient.leaveRecords()
                check(false, "failed renewal cannot resume a business read")
            } catch {
                let sent = await incompleteRenewal.requests
                let diagnostic = await incompleteClient.authenticationDiagnostic
                check(error as? CampusError == (wrongAccountAfterRenewal ? .identityMismatch : .authentication) &&
                      sent.filter { $0.httpMethod == "POST" }.count == 1 && sent.count == 4,
                      "interactive or mismatched renewal stops before replaying the read")
                check(!diagnostic.casCookiesChangedDuringAttempt,
                      "unchanged CAS CookieJar does not permit another auth transaction")
            }
        }

        let renewingCredentials = FixtureCredentials()
        let replacedDuringRenewal = FixtureCampusTransport { req, _ in
            if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
            if req.url!.path.hasSuffix("redirect") {
                renewingCredentials.replaceAccount()
                return (200, ["Set-Cookie": "ehall=late-session; Secure; Path=/"], "official landing")
            }
            return (401, [:], "")
        }
        do {
            _ = try await CampusClient(account: "fixture-account", credentials: renewingCredentials, transport: replacedDuringRenewal).leaveRecords()
            check(false, "account replacement during CAS cancels recovery")
        } catch {
            let sent = await replacedDuringRenewal.requests
            check(error is CancellationError && sent.count == 3 && renewingCredentials.accepted == 0,
                  "account replacement during CAS discards late cookies and stops the read")
        }

        for invalidToken in ["", "fixture\r\nInjected: value"] {
            let malformed = FixtureCampusTransport { _, _ in
                let data: [String: Any] = ["errcode": 2000, "account": "fixture-account", "userId": "fixture-user-id",
                                          "data": ["access_token": invalidToken, "token_type": "bearer"]]
                return (200, [:], String(data: try JSONSerialization.data(withJSONObject: data), encoding: .utf8)!)
            }
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: malformed).leaveRecords()
                check(false, "malformed token rejected")
            } catch {
                let count = await malformed.requests.count
                check(error as? CampusError == .invalidResponse && count == 1,
                      "empty or header-injecting token cannot issue a business request")
            }
        }

        let retried = FixtureCampusTransport { req, index in
            if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
            return index == 2 ? (401, [:], "") : (200, [:], emptyPage)
        }
        _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: retried).leaveRecords(page: 1, size: 20)
        check(await retried.requests.count == 5, "401 renews CAS, revalidates and retries once")

        let always401 = FixtureCampusTransport { req, _ in
            if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
            if req.url!.path.hasSuffix("redirect") { return (200, [:], "official landing") }
            return (401, [:], "")
        }
        do {
            _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: always401).leaveRecords(page: 1, size: 20)
            check(false, "repeated401 fails")
        } catch {
            let count = await always401.requests.count
            check(error as? CampusError == .authentication && count == 5, "second401 ends without infinite retry")
        }

        for (status, expected) in [(403, CampusError.forbidden), (500, CampusError.http(500))] {
            let denied = FixtureCampusTransport { req, _ in
                req.url!.path.hasSuffix("validate_full") ? (200, [:], identity) : (status, [:], "private fixture body")
            }
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: denied).leaveRecords(page: 1, size: 20)
                check(false, "HTTP failure is surfaced")
            } catch {
                let count = await denied.requests.count
                check(error as? CampusError == expected && count == 2, "HTTP failure is safe and not retried")
            }
        }
        let wrongAccount = FixtureCampusTransport { _, _ in
            (200, [:], #"{"errcode":2000,"account":"another-account","userId":"another-id"}"#)
        }
        do {
            _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: wrongAccount).leaveRecords(page: 1, size: 20)
            check(false, "account mismatch is rejected")
        } catch {
            let count = await wrongAccount.requests.count
            check(error as? CampusError == .identityMismatch && count == 1, "different validated account never issues query")
        }

        let redirects = FixtureCampusTransport { req, index in
            switch index {
            case 1: return (200, [:], "null")
            case 2: return (302, ["Location":"http://auth.ccsut.cn/backstage/cas/login?service=fixture"], "")
            case 3: return (302, ["Location":"http://ehall.ccsut.cn/backstage/cas-proxy/app/redirect?ticket=fixture", "Set-Cookie":"CAS=fixture; Secure; Path=/"], "")
            case 4: return (200, [:], "official landing")
            case 5: return (200, [:], identity)
            default: return (200, [:], emptyPage)
            }
        }
        _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: redirects).leaveRecords(page: 1, size: 20)
        let chain = await redirects.requests
        check(chain.allSatisfy { $0.url!.scheme == "https" }, "school HTTP redirects are upgraded before sending")
        check(chain[2].value(forHTTPHeaderField: "Cookie") == "TGC=fixture-tgc" && chain[3].value(forHTTPHeaderField: "Cookie") == "ehall=fixture-session", "redirects rematch Cookie by target domain")
        check(credentials.accepted == 1, "authentication response Cookies handed to session store")

        let foreign = FixtureCampusTransport { _, index in index == 1 ? (200, [:], "null") : (302, ["Location":"https://outside.invalid/collect"], "") }
        do {
            _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: foreign).leaveRecords(page: 1, size: 20)
            check(false, "foreign auth redirect blocked")
        } catch { check(await foreign.requests.count == 2, "no request or Cookie sent to foreign redirect") }

        let changed = FixtureCredentials()
        let late = FixtureCampusTransport { _, _ in
            changed.replaceAccount()
            return (200, ["Set-Cookie":"late=fixture; Secure; Path=/"], identity)
        }
        do {
            _ = try await CampusClient(account: "fixture-account", credentials: changed, transport: late).leaveRecords(page: 1, size: 20)
            check(false, "late account response rejected")
        } catch { check(error is CancellationError && changed.accepted == 0, "account change discards response before accepting Cookies") }
        let cancelled = Task {
            try await Task.sleep(for: .milliseconds(5))
            return try await client.leaveRecords(page: 1, size: 20)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; check(false, "cancelled request rejected") }
        catch { check(error is CancellationError, "cancelled query stops without publishing") }
        let racingCredentials = FixtureCredentials()
        let raceTransport = FixtureCampusTransport { _, _ in (200, [:], identity) }
        let racingClient = CampusClient(account: "fixture-account", credentials: racingCredentials, transport: raceTransport)
        racingCredentials.armAccountSwitch()
        do { _ = try await racingClient.leaveRecords(page: 1, size: 20) } catch { }
        check(await raceTransport.requests.isEmpty, "account change during Cookie read prevents outbound request")
        let webCredentials = FixtureCredentials()
        let handoff = CampusOfficialCookieHandoff(account: "fixture-account", credentials: webCredentials)
        let sessionCookie = HTTPCookie(properties: [.name:"YZSESSIONID2", .value:"fixture", .domain:"ehall.ccsut.cn", .path:"/", .secure:"TRUE"])!
        let casCookie = HTTPCookie(properties: [.name:"TGC", .value:"fixture", .domain:"auth.ccsut.cn", .path:"/", .secure:"TRUE"])!
        do {
            try handoff.accept(identity: Data(#"{"errcode":2000,"account":"another-account"}"#.utf8), cookies: [sessionCookie, casCookie])
            check(false, "different official account rejected")
        } catch { check(error as? CampusError == .identityMismatch && webCredentials.accepted == 0, "official account mismatch cannot import any Cookies") }
        try handoff.accept(identity: Data(identity.utf8), cookies: [sessionCookie, casCookie])
        check(webCredentials.accepted == 1, "verified handoff imports ehall session only, never CAS identity")
        webCredentials.replaceAccount()
        do {
            try handoff.accept(identity: Data(identity.utf8), cookies: [sessionCookie])
            check(false, "late official handoff rejected")
        } catch { check(error is CancellationError && webCredentials.accepted == 1, "late official handoff cannot restore prior credentials") }
        await cookieTransactionRegressions(check)
        if failures > 0 { exit(1) }
    }

    @MainActor
    static func cookieTransactionRegressions(_ check: @MainActor (Bool, String) -> Void) async {
        // A mismatched identity, invalid token, or failed follow-up must never
        // publish the cookies returned before the rejection.
        for rejection in ["wrong-account", "invalid-token", "failed-validation", "transport-failure"] {
            let credentials = ScopedCampusCredentials()
            let transport = FixtureCampusTransport { req, index in
                if index == 1 {
                    if rejection == "wrong-account" {
                        return (200, ["Set-Cookie": "ehall=other-account; Path=/"], identity.replacingOccurrences(of: "fixture-account", with: "other-account"))
                    }
                    if rejection == "invalid-token" {
                        return (200, ["Set-Cookie": "ehall=invalid-token; Path=/"], identity.replacingOccurrences(of: "fixture-access-token", with: ""))
                    }
                    return (200, ["Set-Cookie": "ehall=unverified-first; Path=/"], "null")
                }
                if req.url!.path.hasSuffix("redirect") { return (200, ["Set-Cookie": "ehall=unverified-renewal; Path=/"], "landing") }
                if rejection == "transport-failure" { throw URLError(.timedOut) }
                return (200, ["Set-Cookie": "ehall=unverified-last; Path=/"], "null")
            }
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: transport).leaveRecords()
                check(false, "rejected \(rejection) authentication discards its cookie transaction")
            } catch {
                let header = try? credentials.header(for: URL(string: "https://ehall.ccsut.cn/backstage/read")!, expectedGeneration: 1)
                check(credentials.accepted == 0 && header == "ehall=original-narrow; ehall=original-root",
                      "rejected \(rejection) authentication discards its cookie transaction")
            }
        }

        let credentials = ScopedCampusCredentials()
        let staged = FixtureCampusTransport { req, index in
            switch index {
            case 1: return (200, ["Set-Cookie": "ehall=initial-stage; Path=/"], "null")
            case 2: return (302, ["Location": "http://auth.ccsut.cn:80/backstage/cas/login?service=a%2Fb%2Bc"], "")
            case 3: return (302, ["Set-Cookie": "CAS=cas-stage; Path=/", "Location": "https://auth.ccsut.cn/continue"], "")
            case 4: return (302, ["Set-Cookie": "ehall=auth-stage; Path=/", "Location": "https://ehall.ccsut.cn/backstage/delete"], "")
            case 5: return (302, ["Set-Cookie": "ehall=; Max-Age=0; Path=/backstage", "Location": "https://ehall.ccsut.cn/backstage/finish"], "")
            case 6: return (200, ["Set-Cookie": "ehall=verified-stage; Path=/"], "landing")
            case 7:
                // The shared jar must still belong entirely to its old session.
                guard credentials.accepted == 0 else { return (500, [:], "premature publication") }
                return (200, ["Set-Cookie": "validated=yes; Path=/"], identity)
            default: return (200, ["Set-Cookie": "ehall=business-rotation; Path=/"], emptyPage)
            }
        }
        do {
            _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: staged).leaveRecords()
            let sent = await staged.requests
            check(sent.count == 8 && sent[1].value(forHTTPHeaderField: "Cookie") == "ehall=original-narrow; ehall=initial-stage" &&
                  sent[3].value(forHTTPHeaderField: "Cookie")?.contains("CAS=cas-stage") == true &&
                  sent[4].value(forHTTPHeaderField: "Cookie") == "ehall=original-narrow; ehall=initial-stage" &&
                  sent[5].value(forHTTPHeaderField: "Cookie") == "ehall=initial-stage" &&
                  sent[6].value(forHTTPHeaderField: "Cookie") == "ehall=verified-stage",
                  "staged CAS rotation and scoped deletion reach later hops and final validation")
            let finalHeader = try credentials.header(for: URL(string: "https://ehall.ccsut.cn/backstage/read")!, expectedGeneration: 1) ?? ""
            let authHeader = try credentials.header(for: URL(string: "https://auth.ccsut.cn/")!, expectedGeneration: 1) ?? ""
            check(credentials.accepted == 2 && finalHeader.contains("ehall=business-rotation") && finalHeader.contains("validated=yes") &&
                  finalHeader.components(separatedBy: "ehall=").count == 2 && !finalHeader.contains("auth-stage") && authHeader.contains("ehall=auth-stage"),
                  "validated transaction commits all scopes once and preserves business cookie rotation")
            check(sent[2].url?.absoluteString == "https://auth.ccsut.cn/backstage/cas/login?service=a%2Fb%2Bc",
                  "explicit HTTP port 80 upgrades to default HTTPS with encoded query intact")
        } catch {
            check(false, "staged CAS rotation and scoped deletion reach later hops and final validation")
            check(false, "validated transaction commits all scopes once and preserves business cookie rotation")
            check(false, "explicit HTTP port 80 upgrades to default HTTPS with encoded query intact")
        }

        for invalidation in ["cancel", "generation"] {
            let credentials = ScopedCampusCredentials()
            let barrier = CampusFixtureBarrier()
            let transport = FixtureCampusTransport { _, index in
                if index == 1 { return (200, ["Set-Cookie": "ehall=staged-before-invalidation; Path=/"], "null") }
                await barrier.suspend()
                return (200, ["Set-Cookie": "ehall=late; Path=/"], "landing")
            }
            let client = CampusClient(account: "fixture-account", credentials: credentials, transport: transport)
            let task = Task { try await client.leaveRecords() }
            await barrier.waitUntilBlocked()
            if invalidation == "cancel" { task.cancel() } else { credentials.replaceAccount() }
            await barrier.release()
            do { _ = try await task.value; check(false, "\(invalidation) discards cookies staged by earlier authentication hops") }
            catch { check(error is CancellationError && credentials.accepted == 0, "\(invalidation) discards cookies staged by earlier authentication hops") }
        }

        // Actor reentrancy permits a different subsystem to authenticate while
        // this rejected account's response is suspended.
        let concurrentCredentials = ScopedCampusCredentials()
        let barrier = CampusFixtureBarrier()
        let concurrentTransport = FixtureCampusTransport { req, index in
            if index == 1 { return (200, ["Set-Cookie": "leaked=wrong-account; Path=/"], "null") }
            if req.url!.path.hasSuffix("redirect") {
                await barrier.suspend()
                return (200, [:], "landing")
            }
            if req.url!.path.hasSuffix("validate_full") {
                if req.url!.query?.contains("leaveadmin") == true {
                    return (200, [:], identity.replacingOccurrences(of: "fixture-account", with: "wrong-account"))
                }
                return (200, ["Set-Cookie": "travel=verified; Path=/"], identity)
            }
            return (200, [:], #"{"code":"2000","data":[]}"#)
        }
        let concurrentClient = CampusClient(account: "fixture-account", credentials: concurrentCredentials, transport: concurrentTransport)
        let leave = Task { try await concurrentClient.leaveRecords() }
        await barrier.waitUntilBlocked()
        do { _ = try await concurrentClient.travelRecords(kind: .departure) }
        catch { check(false, "parallel subsystem authenticates independently") }
        await barrier.release()
        do { _ = try await leave.value } catch { }
        let concurrentHeader = try? concurrentCredentials.header(for: URL(string: "https://ehall.ccsut.cn/backstage/read")!, expectedGeneration: 1)
        check(concurrentHeader?.contains("travel=verified") == true && concurrentHeader?.contains("leaked=") == false && concurrentCredentials.accepted == 1,
              "parallel subsystem commits only its own validated cookie transaction")

        for (destination, expected) in [
            ("http://auth.ccsut.cn/backstage/cas/log%69n?service=a%2Fb%2Bc&x=%252f", "https://auth.ccsut.cn/backstage/cas/log%69n?service=a%2Fb%2Bc&x=%252f"),
            ("http://auth.ccsut.cn:80/login", "https://auth.ccsut.cn/login"),
            ("https://auth.ccsut.cn/login", "https://auth.ccsut.cn/login"),
            ("https://auth.ccsut.cn:443/login", "https://auth.ccsut.cn:443/login")
        ] {
            let transport = FixtureCampusTransport { _, index in
                switch index {
                case 1: return (200, [:], "null")
                case 2: return (302, ["Location": destination], "")
                case 3: return (200, [:], "landing")
                case 4: return (200, [:], identity)
                default: return (200, [:], emptyPage)
                }
            }
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: transport).leaveRecords()
                let sent = await transport.requests
                check(sent.count == 5 && sent[2].url?.absoluteString == expected,
                      "allowed authentication URL preserves encoded path and query: \(destination)")
            } catch { check(false, "allowed authentication URL preserves encoded path and query: \(destination)") }
        }

        for destination in ["http://auth.ccsut.cn:443/login", "http://auth.ccsut.cn:81/login", "https://auth.ccsut.cn:80/login",
                            "https://auth.ccsut.cn:444/login", "https://auth.ccsut.cn/login#fragment", "https://user:secret@auth.ccsut.cn/login",
                            "https://outside.invalid/login"] {
            let transport = FixtureCampusTransport { _, index in
                index == 1 ? (200, [:], "null") : (302, ["Location": destination], "")
            }
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: transport).leaveRecords()
                check(false, "abnormal authentication destination rejected: \(destination)")
            } catch {
                check(await transport.requests.count == 2, "abnormal authentication destination rejected: \(destination)")
            }
        }
    }
}
