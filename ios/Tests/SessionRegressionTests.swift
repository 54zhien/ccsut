import Foundation
import WebKit

// Runs the production Session.swift/API.swift/Models.swift on macOS without a device
// or school credentials. The only fake is the external HTTP boundary.
final class SchoolProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (URLRequest) throws -> (Int, URL, [String: String], String) = {
        (200, $0.url!, [:], "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\",\"xsxm\":\"Fixture\"}}")
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, url, headers, body) = try Self.response(request)
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
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
        for c in await webCookies.allCookies() { await webCookies.remove(c) }
        await webCookies.set(cookie("jw_uf", "unverified"))
        SchoolProtocol.response = { (503, $0.url!, [:], "unavailable") }
        let failedAdoption = SessionStore(api: api)
        check(!(await failedAdoption.adoptCookies()), "failed business probe rejects WebKit adoption")
        check(CookieJar.shared.first(where: { $0.name == "jw_uf" })?.value == "previous",
              "failed WebKit adoption preserves the previous credentials")
        let afterFailure = Keychain.load("ccsut.cookies.v2").flatMap { try? JSONDecoder().decode([StoredCookie].self, from: $0) }
        check(afterFailure?.first(where: { $0.name == "jw_uf" })?.value == "previous",
              "unverified WebKit credentials do not overwrite Keychain")

        CookieJar.shared = [cookie("jw_uf", "old"), cookie("TGC", "fixture-tgc", domain: "auth.ccsut.cn")]
        SchoolProtocol.response = { _ in throw URLError(.timedOut) }
        let bootstrap = SessionStore(api: api)
        await bootstrap.bootstrap()
        check(bootstrap.phase == .loggedOut, "actual cold bootstrap exits after probe and renewal timeouts")
        check(Keychain.load("ccsut.cookies.v2") != nil, "transient bootstrap failure retains credentials for retry")

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

        print("Session regression failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
