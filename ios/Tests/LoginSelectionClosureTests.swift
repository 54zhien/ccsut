import Foundation
import WebKit

/// Every request stays in this local protocol. No school login or network is used.
final class LoginClosureProtocol: URLProtocol {
    enum Mode { case authenticated, loggedOut, publicPage, foreignRedirect, otherAccount, replacedDuringRead }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var mode: Mode = .authenticated
    nonisolated(unsafe) private static var paths: [String] = []
    static let number = "fixture-student"
    static let landing = "https://tls.ccsut.cn/frontend/views/student/xkPage/index.html?username=fixture-student&enc=fixture-proof&dbname=fixture"
    static func reset(_ value: Mode) { lock.lock(); defer { lock.unlock() }; mode = value; paths = [] }
    static var requestedPaths: [String] { lock.lock(); defer { lock.unlock() }; return paths }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let mode = Self.mode
        Self.paths.append(request.url!.path)
        Self.lock.unlock()
        let path = request.url!.path
        var status = 200
        var headers: [String: String] = [:]
        var body = "<html>public static landing</html>"
        if path == "/admin/xsd/xk/listV2" {
            body = #"{"ret":-1,"msg":"没有可选的教学班"}"#
        } else if path == "/admin/" || path == "/admin" {
            switch mode {
            case .authenticated, .replacedDuringRead: status = 303; headers["Location"] = Self.landing
            case .otherAccount: status = 303; headers["Location"] = Self.landing.replacingOccurrences(of: Self.number, with: "fixture-other")
            case .loggedOut: status = 303; headers["Location"] = "/admin/login"
            case .publicPage: break
            case .foreignRedirect: status = 303; headers["Location"] = "https://attacker.invalid/?username=fixture-student&enc=fixture"
            }
        }
        if mode == .replacedDuringRead { CookieJar.shared = [] }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct LoginSelectionClosureTests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ result: Bool, _ name: String) {
            print("\(result ? "PASS" : "FAIL") \(name)")
            if !result { failures += 1 }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LoginClosureProtocol.self]
        let api = APIClient(configuration: config)
        func store() -> SessionStore { SessionStore(api: api, prepareEcardSession: { _, _ in }) }
        let cookie = HTTPCookie(properties: [.name:"jw_uf", .value:"fixture-only", .domain:"tls.ccsut.cn", .path:"/", .secure:"TRUE"])!
        CookieJar.shared = [cookie]
        defer { CookieJar.shared = [] }

        LoginClosureProtocol.reset(.authenticated)
        check(await store().probe(), "closed elective channel must not reject an authenticated portal session")
        check(!LoginClosureProtocol.requestedPaths.contains("/admin/xsd/xk/listV2"), "authentication does not call elective initialization")

        WebStore.dataStore = .nonPersistent()
        try? await WebStore.dataStore.httpCookieStore.set(cookie)
        let adopted = store()
        check(await adopted.adoptCookies(), "fresh WebKit login is adopted while the elective channel is closed")
        check(adopted.studentId == LoginClosureProtocol.number,
              "verified account is published before the logged-in UI is exposed")
        await adopted.loadProfile()
        check(adopted.phase == .loggedIn && adopted.studentId == LoginClosureProtocol.number,
              "verified account remains available to campus and electricity pages")
        check(adopted.lastError == nil, "optional name enrichment cannot surface elective closure as a login error")

        LoginClosureProtocol.reset(.otherAccount)
        check(!(await adopted.probe()), "silent verification rejects a different server account")
        check(adopted.studentId == LoginClosureProtocol.number, "a rejected server account does not replace visible identity")

        LoginClosureProtocol.reset(.authenticated)
        CookieJar.shared = [cookie]
        let cold = store()
        await cold.bootstrap()
        check(cold.phase == .loggedIn && cold.studentId == LoginClosureProtocol.number,
              "cold launch also succeeds independently of elective availability")

        for (mode, label) in [(LoginClosureProtocol.Mode.loggedOut,"login redirect"), (.publicPage,"anonymous HTTP 200 page"), (.foreignRedirect,"foreign identity redirect")] {
            CookieJar.shared = [cookie]
            LoginClosureProtocol.reset(mode)
            check(!(await store().probe()), "rejects \(label)")
            check(LoginClosureProtocol.requestedPaths.count == 1, "does not follow \(label) or forward credentials")
        }
        CookieJar.shared = [cookie]
        LoginClosureProtocol.reset(.replacedDuringRead)
        check(!(await store().probe()), "late redirect cannot authenticate after cookie generation changes")
        check(CookieJar.shared.isEmpty, "late redirect does not restore cleared credentials")
        CookieJar.shared = [HTTPCookie(properties: [.name:"TGC", .value:"fixture-cas", .domain:"auth.ccsut.cn", .path:"/", .secure:"TRUE"])!]
        LoginClosureProtocol.reset(.authenticated)
        check(!(await store().probe()) && LoginClosureProtocol.requestedPaths.isEmpty,
              "no TLS-matching cookie means no anonymous identity request")
        print("Login closure regression failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
