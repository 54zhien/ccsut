import Foundation
import WebKit

// Runs the production Session.swift/API.swift/APIResponse.swift/Models.swift on macOS without a device
// or school credentials. The only fake is the external HTTP boundary.
final class SchoolProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var requestPaths: [String] = []
    nonisolated(unsafe) static var response: (URLRequest) throws -> (Int, URL, [String: String], String) = {
        (200, $0.url!, [:], "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\",\"xsxm\":\"Fixture\"}}")
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        Self.requestPaths.append(request.url?.path ?? "")
        do {
            let (status, url, headers, body) = try Self.response(request)
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    static func bodyText(_ request: URLRequest) -> String? {
        if let data = request.httpBody { return String(data: data, encoding: .utf8) }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return String(data: data, encoding: .utf8)
    }
}

@main
struct SessionRegressionTests {
    @MainActor static func main() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SchoolProtocol.self]
        let api = APIClient(configuration: configuration)
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        func cookie(_ name: String, _ value: String, expires: Date? = nil, httpOnly: Bool = false,
                    domain: String = "tls.ccsut.cn", path: String = "/") -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"
            ]
            if let expires { properties[.expires] = expires }
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            return HTTPCookie(properties: properties)!
        }

        defer {
            Keychain.delete("ccsut.cookies.v2")
        }
        CookieJar.shared = [cookie("jw_uf", "expired", expires: Date(timeIntervalSinceNow: -60))]
        check(CookieJar.header(for: "tls.ccsut.cn") == nil, "expired authentication Cookie is never sent")

        let protected = cookie("jw_uf", "protected", httpOnly: true)
        check(protected.isHTTPOnly && StoredCookie(protected).asHTTPCookie?.isHTTPOnly == true,
              "Keychain roundtrip preserves HttpOnly")

        CookieJar.shared = [cookie("jw_uf", "native-only")]
        for c in HTTPCookieStorage.shared.cookies ?? [] { HTTPCookieStorage.shared.deleteCookie(c) }
        SchoolProtocol.response = { req in
            let sent = req.value(forHTTPHeaderField: "Cookie") ?? ""
            return (200, req.url!, [:], "{\"ret\":0,\"data\":{\"xsxh\":\"\(sent)\"}}")
        }
        do {
            let data = try await api.electiveInit()
            check(data.xsxh == "jw_uf=native-only", "business requests use the authoritative Cookie jar")
        } catch { check(false, "business requests use the authoritative Cookie jar: \(error)") }

        CookieJar.shared = [cookie("jw_uf", "before-redirect")]
        SchoolProtocol.response = { req in
            if req.url!.path == "/admin/xsd/xk/listV2" {
                return (302, req.url!, ["Location": "/redirected", "Set-Cookie": "jw_uf=redirected; Path=/; Secure"], "")
            }
            let sent = req.value(forHTTPHeaderField: "Cookie") ?? ""
            return (200, req.url!, [:], "{\"ret\":0,\"data\":{\"xsxh\":\"\(sent)\"}}")
        }
        do {
            let data = try await api.electiveInit()
            check(data.xsxh == "jw_uf=redirected", "redirect response rotation is used on the next hop")
        } catch { check(false, "redirect response rotation is used on the next hop: \(error)") }

        SchoolProtocol.response = { (503, $0.url!, [:], "unavailable") }
        let unavailable = SessionStore(api: api)
        check(!(await unavailable.probe()), "HTTP 503 is not a valid session")

        SchoolProtocol.response = { _ in (200, URL(string: "https://auth.ccsut.cn/backstage/cas/login")!, [:], "login form") }
        let loginPage = SessionStore(api: api)
        check(!(await loginPage.probe()), "CAS login page with HTTP 200 is not a valid session")

        SchoolProtocol.response = { (200, $0.url!, [:], "{\"ret\":-1,\"msg\":\"rejected\",\"data\":{\"xsxh\":\"fixture-student\"}}") }
        let rejected = SessionStore(api: api)
        check(!(await rejected.probe()), "authentication rejects a nonzero result even with identity data")

        SchoolProtocol.response = { _ in throw URLError(.timedOut) }
        let coldStart = SessionStore(api: api)
        await coldStart.refresh()
        check(coldStart.phase == .loggedOut, "failed renewal exits checking state")
        check(coldStart.lastError != nil, "failed renewal retains a user-visible reason")

        CookieJar.shared = [cookie("jw_uf", "old")]
        SchoolProtocol.response = { (200, $0.url!, ["Set-Cookie": "jw_uf=rotated; Path=/; Secure; HttpOnly"],
                                     "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}") }
        _ = try? await api.electiveInit()
        let saved = Keychain.load("ccsut.cookies.v2").flatMap { try? JSONDecoder().decode([StoredCookie].self, from: $0) }
        check(saved?.contains(where: { $0.name == "jw_uf" && $0.value == "rotated" }) == true,
              "rotated response Cookie is persisted for the next launch")

        CookieJar.shared = [cookie("jw_uf", "previous")]
        let webCookies = WebStore.dataStore.httpCookieStore
        for c in (try? await webCookies.cookieSnapshot()) ?? [] { try? await webCookies.remove(c) }
        try? await webCookies.set(cookie("jw_uf", "unverified"))
        SchoolProtocol.response = { (503, $0.url!, [:], "unavailable") }
        let failedAdoption = SessionStore(api: api)
        check(!(await failedAdoption.adoptCookies()), "failed business probe rejects WebKit adoption")
        check(CookieJar.shared.first(where: { $0.name == "jw_uf" })?.value == "previous",
              "failed WebKit adoption preserves the previous credentials")
        let afterFailure = Keychain.load("ccsut.cookies.v2").flatMap { try? JSONDecoder().decode([StoredCookie].self, from: $0) }
        check(afterFailure?.first(where: { $0.name == "jw_uf" })?.value == "previous",
              "unverified WebKit credentials do not overwrite Keychain")

        SchoolProtocol.response = { (200, $0.url!, ["Set-Cookie": "jw_uf=verified; Path=/; Secure; HttpOnly"],
                                     "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}") }
        let validAdoption = SessionStore(api: api)
        check(await validAdoption.adoptCookies(), "verified WebKit adoption succeeds")
        check(CookieJar.header(for: "tls.ccsut.cn") == "jw_uf=verified",
              "successful adoption keeps the probe's rotated Cookie")

        CookieJar.shared = [cookie("jw_uf", "old"), cookie("TGC", "fixture-tgc", domain: "auth.ccsut.cn")]
        var offlineCASRequests = 0
        SchoolProtocol.response = { request in
            if request.url?.path == "/admin/caslogin" { offlineCASRequests += 1 }
            throw URLError(.timedOut)
        }
        let bootstrap = SessionStore(api: api)
        await bootstrap.bootstrap()
        check(bootstrap.phase == .loggedOut, "actual cold bootstrap exits after probe and renewal timeouts")
        check(Keychain.load("ccsut.cookies.v2") != nil, "transient bootstrap failure retains credentials for retry")
        check(offlineCASRequests == 0, "offline bootstrap does not retry a doomed CAS request")

        CookieJar.shared = [cookie("jw_uf", "old"), cookie("TGC", "fixture-tgc", domain: "auth.ccsut.cn")]
        var casStarts = 0
        var correctAuthCookies = false
        SchoolProtocol.response = { req in
            let url = req.url!
            if url.host == "auth.ccsut.cn" {
                correctAuthCookies = req.value(forHTTPHeaderField: "Cookie") == "TGC=fixture-tgc"
                return (302, url, ["Location": "https://tls.ccsut.cn/admin/caslogin?ticket=fixture"], "")
            }
            if url.path == "/admin/caslogin" {
                if url.query == nil {
                    casStarts += 1
                    return (302, url, ["Location": "https://auth.ccsut.cn/backstage/cas/login"], "")
                }
                return (302, url, ["Location": "/frontend/student", "Set-Cookie": "jw_uf=renewed; Path=/; Secure; HttpOnly"], "")
            }
            return (200, url, [:], "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}")
        }
        let renewal = SessionStore(api: api)
        async let one: Void = renewal.refresh()
        async let two: Void = renewal.refresh()
        _ = await (one, two)
        check(renewal.phase == .loggedIn, "CAS cross-host redirect chain establishes a verified session")
        check(correctAuthCookies, "CAS receives its TGC without leaking the teaching-system Cookie")
        check(casStarts == 1, "concurrent renewal callers share one CAS request")
        check(CookieJar.header(for: "tls.ccsut.cn") == "jw_uf=renewed", "CAS callback rotation is retained")

        CookieJar.shared = [cookie("TGC", "tgc-only", domain: "auth.ccsut.cn")]
        let tgcOnlyGeneration = CookieJar.generation
        SchoolProtocol.requestCount = 0
        SchoolProtocol.requestPaths = []
        var initialTLSCookie: String? = "unexpected"
        var tgcOnlyAuthCookie: String?
        SchoolProtocol.response = { request in
            let url = request.url!
            if url.host == "tls.ccsut.cn" && url.path == "/admin/caslogin" && url.query == nil {
                initialTLSCookie = request.value(forHTTPHeaderField: "Cookie")
                return (302, url, ["Location": "https://auth.ccsut.cn/backstage/cas/login"], "")
            }
            if url.host == "auth.ccsut.cn" {
                tgcOnlyAuthCookie = request.value(forHTTPHeaderField: "Cookie")
                return (302, url, ["Location": "https://tls.ccsut.cn/admin/caslogin?ticket=fixture"], "")
            }
            return (200, url, [:], "callback")
        }
        do {
            let request = URLRequest(url: URL(string: "https://tls.ccsut.cn/admin/caslogin")!)
            let (_, response) = try await api.response(
                for: request,
                allowAuthenticationRedirects: true,
                expectedGeneration: tgcOnlyGeneration
            )
            check(response.statusCode == 200, "TGC-only renewal follows the initial TLS redirect")
        } catch {
            check(false, "TGC-only renewal follows the initial TLS redirect: \(error)")
        }
        check(initialTLSCookie == nil, "TGC-only renewal sends no unmatched Cookie on the initial TLS hop")
        check(tgcOnlyAuthCookie == "TGC=tgc-only", "TGC-only renewal sends TGC only to the auth host")
        check(SchoolProtocol.requestPaths == ["/admin/caslogin", "/backstage/cas/login", "/admin/caslogin"],
              "TGC-only renewal completes all three fake-network hops")

        CookieJar.shared = [cookie("scoped", "yes", path: "/admin"), cookie("TGC", "private", domain: "auth.ccsut.cn")]
        check(CookieJar.header(for: URL(string: "https://tls.ccsut.cn/admin/courses")!) == "scoped=yes",
              "path-scoped Cookie reaches its permitted endpoint")
        check(CookieJar.header(for: URL(string: "https://tls.ccsut.cn/administrator")!) == nil,
              "Cookie path boundary prevents accidental prefix matches")
        check(CookieJar.header(for: URL(string: "http://tls.ccsut.cn/admin")!) == nil,
              "Secure Cookies are not sent over HTTP")
        SchoolProtocol.response = { (302, $0.url!, ["Location": "/loop"], "") }
        do { _ = try await api.html("/loop"); check(false, "redirect loops terminate") }
        catch { check((error as? URLError)?.code == .httpTooManyRedirects, "redirect loops terminate") }

        // Hold a real request at the HTTP boundary, invalidate credentials, then release
        // a successful response with Set-Cookie. Its stale generation must be rejected.
        CookieJar.shared = [cookie("jw_uf", "before-logout")]
        let gate = DispatchSemaphore(value: 0)
        let (started, continuation) = AsyncStream<Void>.makeStream()
        SchoolProtocol.response = { req in
            continuation.yield(())
            _ = gate.wait(timeout: .now() + 5)
            return (200, req.url!, ["Set-Cookie": "jw_uf=late; Path=/; Secure"], "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}")
        }
        let late = Task { try await api.electiveInit() }
        for await _ in started { break }
        CookieJar.shared = []
        gate.signal()
        do { _ = try await late.value; check(false, "late response after logout is cancelled") }
        catch { check(error is CancellationError, "late response after logout is cancelled") }
        continuation.finish()
        check(CookieJar.shared.isEmpty && Keychain.load("ccsut.cookies.v2") == nil,
              "late response cannot restore logged-out credentials")

        let loggedOut = SessionStore(api: api)
        await loggedOut.logout()
        check(CookieJar.shared.isEmpty, "logout clears the authoritative Cookie jar")
        check(Keychain.load("ccsut.cookies.v2") == nil, "logout removes persisted credentials")
        await loggedOut.loadProfile()
        check(loggedOut.lastError == nil && loggedOut.studentName == nil && loggedOut.studentId == nil,
              "late profile work cannot repopulate logged-out state")
        check(((try? await WebStore.dataStore.httpCookieStore.cookieSnapshot()) ?? []).isEmpty,
              "logout exposes a fresh empty WebKit Cookie store")

        do {
            let _: Int = try await CookieCallback.wait(timeout: .milliseconds(10)) { _ in }
            check(false, "missing WebKit callback times out")
        } catch { check((error as? URLError)?.code == .timedOut, "missing WebKit callback times out") }
        let waiting = Task {
            let _: Int = try await CookieCallback.wait { _ in }
        }
        waiting.cancel()
        do { try await waiting.value; check(false, "cancelled WebKit wait terminates") }
        catch { check(error is CancellationError, "cancelled WebKit wait terminates") }
        do {
            let first: Int = try await CookieCallback.wait { complete in complete(7); complete(9) }
            check(first == 7, "duplicate WebKit callback completes exactly once")
        } catch { check(false, "duplicate WebKit callback completes exactly once") }

        func listCount(_ name: String) async throws -> Int {
            switch name {
            case "exam": return try await api.examList(xnxq: "fixture-term").count
            case "teaching":
                let page = try await api.teachingClasses()
                return page.initData?.count ?? -1
            case "score": return try await api.scoreList().count
            default: throw APIError.decoding("未知测试端点")
            }
        }

        func resetProtocolRequests() {
            SchoolProtocol.requestCount = 0
            SchoolProtocol.requestPaths = []
        }

        func runMutation(_ name: String, expectedGeneration: UInt64) async throws {
            if name == "enroll" {
                _ = try await api.enroll(jxbid: "fixture-class", pcid: "fixture-batch",
                                         expectedGeneration: expectedGeneration)
            } else {
                _ = try await api.dropClass(jxbid: "fixture-class", pcid: "fixture-batch",
                                            expectedGeneration: expectedGeneration)
            }
        }

        let listFixtures: [(name: String, path: String, missing: String, empty: String, rejected: String)] = [
            (
                "exam",
                "/admin/xsd/kwglXsdKscx/getXsKsxx",
                "{\"ret\":0,\"data\":{}}",
                "{\"ret\":0,\"data\":{\"list\":[]}}",
                "{\"ret\":-23,\"msg\":\"fixture rejection\",\"data\":{\"list\":[]}}"
            ),
            (
                "teaching",
                "/admin/xsd/xk/listjxbDataV2",
                "{\"ret\":0,\"data\":{}}",
                "{\"ret\":0,\"data\":{\"initData\":[]}}",
                "{\"ret\":-23,\"msg\":\"fixture rejection\",\"data\":{\"initData\":[]}}"
            ),
            (
                "score",
                "/admin/ydd/inf/getXscjJson",
                "{\"ret\":0,\"data\":{}}",
                "{\"ret\":0,\"data\":{\"xscjList\":[]}}",
                "{\"ret\":-23,\"msg\":\"fixture rejection\",\"data\":{\"xscjList\":[]}}"
            ),
        ]

        CookieJar.shared = [cookie("jw_uf", "protocol-fixture")]
        for fixture in listFixtures {
            let missingBody = fixture.missing
            resetProtocolRequests()
            SchoolProtocol.response = { request in (200, request.url!, [:], missingBody) }
            do {
                _ = try await listCount(fixture.name)
                check(false, "\(fixture.name) missing list container fails")
            } catch is APIError {
                check(true, "\(fixture.name) missing list container fails")
            } catch {
                check(false, "\(fixture.name) missing list container fails with API error")
            }
            check(SchoolProtocol.requestPaths == [fixture.path], "\(fixture.name) missing-list fixture reaches the production endpoint")

            let emptyBody = fixture.empty
            resetProtocolRequests()
            SchoolProtocol.response = { request in (200, request.url!, [:], emptyBody) }
            do {
                let count = try await listCount(fixture.name)
                check(count == 0, "\(fixture.name) explicit empty list succeeds")
            } catch {
                check(false, "\(fixture.name) explicit empty list succeeds: \(error)")
            }
            check(SchoolProtocol.requestPaths == [fixture.path], "\(fixture.name) empty-list fixture reaches the production endpoint")

            let rejectedBody = fixture.rejected
            resetProtocolRequests()
            SchoolProtocol.response = { request in (200, request.url!, [:], rejectedBody) }
            do {
                _ = try await listCount(fixture.name)
                check(false, "\(fixture.name) nonzero ret with valid data is rejected")
            } catch APIError.business(let code, _) {
                check(code == -23, "\(fixture.name) nonzero ret with valid data is rejected")
            } catch {
                check(false, "\(fixture.name) nonzero ret with valid data is rejected as business error")
            }
            check(SchoolProtocol.requestPaths == [fixture.path], "\(fixture.name) rejected fixture reaches the production endpoint")
        }

        let requestURL = URL(string: "https://tls.ccsut.cn/admin/xsd/xk/xsdXkV2")!
        CookieJar.shared = [cookie("jw_uf", "account-a")]
        let accountAGeneration = CookieJar.generation
        do {
            let header = try CookieJar.header(for: requestURL, expectedGeneration: accountAGeneration)
            check(header == "jw_uf=account-a", "Cookie header is read for its verified generation")
        } catch {
            check(false, "Cookie header is read for its verified generation")
        }
        CookieJar.shared = [cookie("jw_uf", "account-b")]
        do {
            _ = try CookieJar.header(for: requestURL, expectedGeneration: accountAGeneration)
            check(false, "Cookie header rejects a stale generation")
        } catch is CancellationError {
            check(true, "Cookie header rejects a stale generation")
        } catch {
            check(false, "Cookie header rejects a stale generation with cancellation")
        }

        let staleMutations: [(name: String, path: String)] = [
            ("enroll", "/admin/xsd/xk/xsdXkV2"),
            ("dropClass", "/admin/xsd/xk/xsdTkV2"),
        ]
        for mutation in staleMutations {
            CookieJar.shared = [cookie("jw_uf", "account-a")]
            let expectedGeneration = CookieJar.generation
            CookieJar.shared = [cookie("jw_uf", "account-b")]
            resetProtocolRequests()
            SchoolProtocol.response = { request in
                (200, request.url!, [:], "{\"ret\":0,\"msg\":\"fixture success\"}")
            }
            do {
                try await runMutation(mutation.name, expectedGeneration: expectedGeneration)
                check(false, "\(mutation.name) confirmed for account A cancels after switching to B")
            } catch is CancellationError {
                check(true, "\(mutation.name) confirmed for account A cancels after switching to B")
            } catch {
                check(false, "\(mutation.name) stale generation is rejected with cancellation")
            }
            check(SchoolProtocol.requestCount == 0 && SchoolProtocol.requestPaths.isEmpty,
                  "\(mutation.name) stale confirmation sends no request")
        }

        let mutations: [(name: String, path: String)] = [
            ("enroll", "/admin/xsd/xk/xsdXkV2"),
            ("dropClass", "/admin/xsd/xk/xsdTkV2"),
        ]
        for mutation in mutations {
            CookieJar.shared = [cookie("jw_uf", "protocol-fixture")]
            let expectedGeneration = CookieJar.generation
            resetProtocolRequests()
            SchoolProtocol.response = { request in
                (200, request.url!, [:], "{\"ret\":-1,\"msg\":\"session expired\"}")
            }
            do {
                try await runMutation(mutation.name, expectedGeneration: expectedGeneration)
                check(false, "\(mutation.name) session expiry is not reported as success")
            } catch let error as APIError {
                if case .notLoggedIn = error {
                    check(true, "\(mutation.name) session expiry maps to notLoggedIn")
                } else {
                    check(false, "\(mutation.name) session expiry maps to notLoggedIn")
                }
            } catch {
                check(false, "\(mutation.name) session expiry maps to notLoggedIn")
            }
            check(SchoolProtocol.requestCount == 1, "\(mutation.name) session expiry is never retried")
            check(SchoolProtocol.requestPaths == [mutation.path], "\(mutation.name) uses its single production endpoint")
        }

        CookieJar.shared = [cookie("jw_uf", "protocol-fixture")]
        let quotaGeneration = CookieJar.generation
        resetProtocolRequests()
        SchoolProtocol.response = { request in
            (200, request.url!, [:], "{\"ret\":-1,\"msg\":\"当前批次已选门数超过【4门】\"}")
        }
        do {
            _ = try await api.enroll(jxbid: "fixture-class", pcid: "fixture-batch",
                                     expectedGeneration: quotaGeneration)
            check(false, "enrollment quota rejection remains a readable business error")
        } catch APIError.business(let code, let message) {
            check(code == -1 && message == "当前批次已选门数超过【4门】", "enrollment quota rejection remains a readable business error")
        } catch {
            check(false, "enrollment quota rejection remains a readable business error")
        }
        check(SchoolProtocol.requestCount == 1 && SchoolProtocol.requestPaths == ["/admin/xsd/xk/xsdXkV2"],
              "enrollment quota rejection sends exactly one request")

        // Real API/discovery/snapshot path, with only the HTTP boundary replaced.
        // The mobile semester controls match the captured official kslist page.
        CookieJar.shared = [cookie("jw_uf", "exam-fixture")]
        resetProtocolRequests()
        let examTerms = ["2026-2027-1", "2025-2026-2", "2025-2026-1", "2024-2025-2", "2024-2025-1"]
        SchoolProtocol.response = { request in
            if request.url!.path == "/admin/xsd/kwglXsdKscx/kslist" {
                let controls = examTerms.map { "<a onclick=\"loadKspc('\($0)');\">\($0)</a>" }.joined()
                return (200, request.url!, [:], "<html><div id=\"xueqi_pop\">\(controls)</div></html>")
            }
            guard request.url!.path == "/admin/xsd/kwglXsdKscx/getXsKsxx",
                  request.httpMethod == "POST",
                  let body = SchoolProtocol.bodyText(request),
                  let term = body.removingPercentEncoding?.split(separator: "=").last.map(String.init),
                  examTerms.contains(term) else { throw URLError(.badServerResponse) }
            return (200, request.url!, [:], "{\"ret\":0,\"data\":{\"list\":[{\"id\":\"\(term)\",\"kcmc\":\"fixture\"}]}}")
        }
        do {
            let discovered = try await api.availableExamTerms()
            check(discovered == examTerms, "mobile exam discovery reads every captured semester control")
            let snapshot = try await ExamSnapshotLoader.load(terms: discovered) { try await api.examList(xnxq: $0) }
            check(Set(snapshot.map(\.id)) == Set(examTerms), "mobile exam discovery reaches the production exam endpoint for every term")
            check(snapshot.allSatisfy { $0.id == $0.term }, "complete exam snapshot retains the requested semester attribution")
            check(SchoolProtocol.requestCount == 6, "exam recovery performs one discovery and five read requests without retries")
        } catch {
            check(false, "mobile exam page loads through real API boundary: \(error)")
        }

        print("Session regression failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
