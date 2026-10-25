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
            do {
                _ = try await CampusClient(account: "fixture-account", credentials: FixtureCredentials(), transport: incompleteRenewal).leaveRecords()
                check(false, "failed renewal cannot resume a business read")
            } catch {
                let sent = await incompleteRenewal.requests
                check(error as? CampusError == (wrongAccountAfterRenewal ? .identityMismatch : .authentication) &&
                      sent.filter { $0.httpMethod == "POST" }.count == 1 && sent.count == 4,
                      "interactive or mismatched renewal stops before replaying the read")
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
        if failures > 0 { exit(1) }
    }
}
