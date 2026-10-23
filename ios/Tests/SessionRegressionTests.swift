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
        URLProtocol.registerClass(SchoolProtocol.self)
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        func cookie(_ name: String, _ value: String, expires: Date? = nil, httpOnly: Bool = false) -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: "tls.ccsut.cn", .path: "/", .secure: "TRUE"
            ]
            if let expires { properties[.expires] = expires }
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            return HTTPCookie(properties: properties)!
        }

        defer {
            Keychain.delete("ccsut.cookies.v2")
            URLProtocol.unregisterClass(SchoolProtocol.self)
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
            let data = try await APIClient.shared.electiveInit()
            check(data.xsxh == "jw_uf=native-only", "business requests use the authoritative Cookie jar")
        } catch { check(false, "business requests use the authoritative Cookie jar: \(error)") }

        SchoolProtocol.response = { (503, $0.url!, [:], "unavailable") }
        let unavailable = SessionStore()
        check(!(await unavailable.probe()), "HTTP 503 is not a valid session")

        SchoolProtocol.response = { _ in (200, URL(string: "https://auth.ccsut.cn/backstage/cas/login")!, [:], "login form") }
        let loginPage = SessionStore()
        check(!(await loginPage.probe()), "CAS login page with HTTP 200 is not a valid session")

        SchoolProtocol.response = { _ in throw URLError(.timedOut) }
        let coldStart = SessionStore()
        await coldStart.refresh()
        check(coldStart.phase == .loggedOut, "failed renewal exits checking state")
        check(coldStart.lastError != nil, "failed renewal retains a user-visible reason")

        CookieJar.shared = [cookie("jw_uf", "old")]
        SchoolProtocol.response = { (200, $0.url!, ["Set-Cookie": "jw_uf=rotated; Path=/; Secure; HttpOnly"],
                                     "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}") }
        _ = try? await APIClient.shared.electiveInit()
        let saved = Keychain.load("ccsut.cookies.v2").flatMap { try? JSONDecoder().decode([StoredCookie].self, from: $0) }
        check(saved?.contains(where: { $0.name == "jw_uf" && $0.value == "rotated" }) == true,
              "rotated response Cookie is persisted for the next launch")

        let loggedOut = SessionStore()
        await loggedOut.logout()
        check(CookieJar.shared.isEmpty, "logout clears the authoritative Cookie jar")
        check(Keychain.load("ccsut.cookies.v2") == nil, "logout removes persisted credentials")

        print("Session regression failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
