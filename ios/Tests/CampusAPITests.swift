import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FixtureCredentials: CampusSessionCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 1
    private var receivedCookies = 0
    private var switchOnHeader = false
    var generation: UInt64 { lock.lock(); defer { lock.unlock() }; return revision }
    func replaceAccount() { lock.lock(); defer { lock.unlock() }; revision += 1 }
    func armAccountSwitch() { lock.lock(); defer { lock.unlock() }; switchOnHeader = true }
    func header(for url: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        if switchOnHeader { switchOnHeader = false; revision += 1 }
        return url.host == "auth.ccsut.cn" ? "TGC=fixture-tgc" : "ehall=fixture-session"
    }
    func header(for url: URL, expectedGeneration: UInt64) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if switchOnHeader { switchOnHeader = false; revision += 1 }
        guard expectedGeneration == revision else { throw CancellationError() }
        return url.host == "auth.ccsut.cn" ? "TGC=fixture-tgc" : "ehall=fixture-session"
    }
    func accept(_ cookies: [HTTPCookie], generation: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if generation == revision { receivedCookies += cookies.count }
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
    static let identity = #"{"errcode":2000,"account":"fixture-account","userId":"fixture-user-id"}"#
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

        let retried = FixtureCampusTransport { req, index in
            if req.url!.path.hasSuffix("validate_full") { return (200, [:], identity) }
            return index == 2 ? (401, [:], "") : (200, [:], emptyPage)
        }
        _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: retried).leaveRecords(page: 1, size: 20)
        check(await retried.requests.count == 4, "401 revalidates and retries once")

        let always401 = FixtureCampusTransport { req, _ in
            req.url!.path.hasSuffix("validate_full") ? (200, [:], identity) : (401, [:], "")
        }
        do {
            _ = try await CampusClient(account: "fixture-account", credentials: credentials, transport: always401).leaveRecords(page: 1, size: 20)
            check(false, "repeated401 fails")
        } catch {
            let count = await always401.requests.count
            check(error as? CampusError == .authentication && count == 4, "second401 ends without infinite retry")
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
