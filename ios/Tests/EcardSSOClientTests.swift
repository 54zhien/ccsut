import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct StubResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data
    let expectedPath: String
    let expectedMethod: String
    let expectedQuery: [String: String]
    let delayMilliseconds: UInt64
    let checkRequest: @Sendable (URLRequest) -> Bool

    init(
        _ status: Int,
        headers: [String: String] = [:],
        body: String = "",
        path: String,
        method: String = "GET",
        query: [String: String] = [:],
        delayMilliseconds: UInt64 = 0,
        checkRequest: @escaping @Sendable (URLRequest) -> Bool = { _ in true }
    ) {
        self.status = status
        self.headers = headers
        self.body = Data(body.utf8)
        self.expectedPath = path
        self.expectedMethod = method
        self.expectedQuery = query
        self.delayMilliseconds = delayMilliseconds
        self.checkRequest = checkRequest
    }
}

private actor ScriptedTransport: EcardSSOTransport {
    private var responses: [StubResponse]
    private var requests: [URLRequest] = []
    private var mismatch = false

    init(_ responses: [StubResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let response = responses.first, response.delayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(response.delayMilliseconds))
        }
        requests.append(request)
        guard !responses.isEmpty else {
            mismatch = true
            throw URLError(.badServerResponse)
        }
        let next = responses.removeFirst()
        guard let url = request.url else {
            mismatch = true
            throw URLError(.badURL)
        }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        if url.path != next.expectedPath || (request.httpMethod ?? "GET") != next.expectedMethod
            || next.expectedQuery.contains(where: { query[$0.key] != $0.value })
            || !next.checkRequest(request) {
            mismatch = true
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: next.status,
            httpVersion: "HTTP/1.1",
            headerFields: next.headers
        ) else {
            mismatch = true
            throw URLError(.badServerResponse)
        }
        return (next.body, response)
    }

    func outcome() -> (remaining: Int, requestCount: Int, mismatch: Bool, requests: [URLRequest]) {
        (responses.count, requests.count, mismatch, requests)
    }
}

private final class SyntheticCredentials: EcardSSOCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var generationValue: UInt64 = 7
    private var acceptedCookies: [HTTPCookie] = []
    private var acceptCount = 0

    init(initialCookies: [HTTPCookie] = []) {
        self.acceptedCookies = initialCookies
    }

    var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generationValue
    }

    func cookies(for url: URL, expectedGeneration: UInt64) throws -> [HTTPCookie] {
        lock.lock(); defer { lock.unlock() }
        guard generationValue == expectedGeneration else { throw EcardSSOError.identityMismatch }
        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookies = acceptedCookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            let path = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = requestPath == path || requestPath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
            return (url.host == domain || url.host?.hasSuffix("." + domain) == true)
                && pathMatches && (cookie.expiresDate ?? .distantFuture) > Date()
        }.sorted { $0.path.count > $1.path.count }
        if cookies.isEmpty && url.host == "ecard.ccsut.cn" {
            return [HTTPCookie(properties: [.domain: "ecard.ccsut.cn", .path: "/",
                                           .name: "TGC", .value: "fixture", .secure: "TRUE"])!]
        }
        return cookies
    }

    func accept(_ cookies: [HTTPCookie], generation: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard generationValue == generation else { return }
        acceptCount += 1
        for cookie in cookies {
            acceptedCookies.removeAll {
                $0.name == cookie.name
                    && Self.normalizedDomain($0.domain) == Self.normalizedDomain(cookie.domain)
                    && $0.path == cookie.path
            }
            if (cookie.expiresDate ?? .distantFuture) > Date() {
                acceptedCookies.append(cookie)
            }
        }
    }

    func switchIdentity() {
        lock.lock(); defer { lock.unlock() }
        generationValue &+= 1
    }

    func acceptedState() -> (cookies: [HTTPCookie], acceptCount: Int) {
        lock.lock(); defer { lock.unlock() }
        return (acceptedCookies, acceptCount)
    }

    private static func normalizedDomain(_ domain: String) -> String {
        let lowercased = domain.lowercased()
        return lowercased.hasPrefix(".") ? String(lowercased.dropFirst()) : lowercased
    }
}

@main
struct EcardSSOClientTests {
    static func main() async {
        var failures = 0

        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }

        let account = "2026123456"
        let token = jwt(account: account, expiresIn: 3_600)
        let transitTarget = "https://ecard.ccsut.cn/plat?name=loginTransit"
        let transit = URLComponents(string: "https://ecard.ccsut.cn/plat/")!
        var transitComponents = transit
        transitComponents.queryItems = [
            URLQueryItem(name: "name", value: "loginTransit"),
            URLQueryItem(name: "ticket", value: "fixture+ticket&part=2"),
            URLQueryItem(name: "targetUrl", value: transitTarget)
        ]
        let transitLocation = transitComponents.url!.absoluteString

        let directTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation, "Set-Cookie": "TGC=rotated; Domain=ecard.ccsut.cn; Path=/; Secure"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST",
                         checkRequest: { request in
                             let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                             let fields = URLComponents(string: "?" + body)?.queryItems ?? []
                             let values = Dictionary(fields.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
                             return body.contains("username=fixture%2Bticket%26part%3D2")
                                 && body.contains("password=fixture%2Bticket%26part%3D2")
                                 && values["username"] == "fixture+ticket&part=2"
                                 && values["password"] == "fixture+ticket&part=2"
                                 && values["grant_type"] == "password"
                                 && values["scope"] == "all"
                                 && values["loginFrom"] == "h5"
                                 && values["logintype"] == "sso"
                                 && values["device_token"] == "h5"
                                 && values["synAccessSource"] == "h5"
                                 && request.value(forHTTPHeaderField: "Authorization") == nil
                         }),
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/charge-app/?token=\(token)&name=pays&id=408"],
                         path: "/charge/feeitem/toAppitem", query: ["feeitemid": "408"],
                         checkRequest: {
                             $0.value(forHTTPHeaderField: "synjones-auth") == "bearer fixture-portal-token"
                                 && $0.value(forHTTPHeaderField: "Authorization") == nil
                         })
        ])
        let directCredentials = SyntheticCredentials()
        do {
            let client = EcardSSOClient(account: account, credentials: directCredentials, transport: directTransport, timeout: 2)
            let result = try await client.fetchPaymentToken()
            let outcome = await directTransport.outcome()
            check(result == token, "direct CAS session returns the validated payment JWT")
            check(outcome.remaining == 0 && outcome.requestCount == 3 && !outcome.mismatch,
                  "direct flow exchanges only the transit ticket and reads feeitem 408")
            check(outcome.requests[1].value(forHTTPHeaderField: "Cookie")?.contains("TGC=rotated") == true,
                  "rotated response cookie is used on the next same-host request")
            check(outcome.requests[1].value(forHTTPHeaderField: "Cookie") == "TGC=rotated",
                  "staged cookie rotation deterministically overrides the same-name persistent cookie")
            check(outcome.requests[2].value(forHTTPHeaderField: "Cookie")?.contains("TGC=rotated") == true,
                  "rotated response cookie remains scoped to later ecard requests")
            let committed = directCredentials.acceptedState()
            check(committed.acceptCount == 1 && committed.cookies.contains { $0.name == "TGC" && $0.value == "rotated" },
                  "validated payment token commits staged cookie rotation once")
            check(outcome.requests.allSatisfy { $0.url?.path != "/plat" && $0.url?.path != "/plat/" },
                  "transit ticket is intercepted without fetching the portal page")
        } catch {
            check(false, "direct CAS session returns the validated payment JWT: \(error.localizedDescription)")
        }

        // A deletion replaces only (name, normalized domain, path), not every
        // persistent cookie with the same name. Exercise real request assembly.
        let deletionScopes: [(label: String, survivorDomain: String, survivorPath: String,
                              deletedDomain: String, deletedPath: String)] = [
            ("narrow deletion preserves root", "ecard.ccsut.cn", "/", "ecard.ccsut.cn", "/berserker-auth"),
            ("root deletion preserves narrow", "ecard.ccsut.cn", "/berserker-auth", "ecard.ccsut.cn", "/"),
            ("host deletion preserves parent domain", ".ccsut.cn", "/", "ecard.ccsut.cn", "/"),
            ("parent deletion preserves host", "ecard.ccsut.cn", "/", ".ccsut.cn", "/"),
            ("unrelated path deletion preserves root", "ecard.ccsut.cn", "/", "ecard.ccsut.cn", "/charge"),
        ]
        for scope in deletionScopes {
            let survivor = HTTPCookie(properties: [.domain: scope.survivorDomain, .path: scope.survivorPath,
                                                   .name: "TGC", .value: "survivor", .secure: "TRUE"])!
            let deleted = HTTPCookie(properties: [.domain: scope.deletedDomain, .path: scope.deletedPath,
                                                 .name: "TGC", .value: "obsolete", .secure: "TRUE"])!
            let credentials = SyntheticCredentials(initialCookies: [survivor, deleted])
            let transport = ScriptedTransport([
                StubResponse(302, headers: ["Location": transitLocation,
                    "Set-Cookie": "TGC=; Domain=\(scope.deletedDomain); Path=\(scope.deletedPath); Expires=Wed, 21 Oct 2015 07:28:00 GMT; Secure"],
                    path: "/berserker-auth/cas/login/wisedu"),
                StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                    path: "/berserker-auth/oauth/token", method: "POST",
                    checkRequest: { $0.value(forHTTPHeaderField: "Cookie") == "TGC=survivor"
                        && credentials.acceptedState().acceptCount == 0 }),
                StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/charge-app/?token=\(token)&name=pays&id=408"],
                    path: "/charge/feeitem/toAppitem")
            ])
            do {
                _ = try await EcardSSOClient(account: account, credentials: credentials,
                    transport: transport, timeout: 2).fetchPaymentToken()
                let outcome = await transport.outcome()
                check(!outcome.mismatch && outcome.remaining == 0, "\(scope.label) during authentication")
                let state = credentials.acceptedState()
                check(state.acceptCount == 1 && state.cookies.count == 1 && state.cookies.first?.value == "survivor",
                      "\(scope.label) after successful commit")
            } catch { check(false, "\(scope.label): \(error.localizedDescription)") }
        }

        let staleCookie = HTTPCookie(properties: [
            .domain: "ecard.ccsut.cn", .path: "/", .name: "TGC", .value: "stale", .secure: "TRUE"
        ])!
        let tombstoneCredentials = SyntheticCredentials(initialCookies: [staleCookie])
        let tombstoneTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation,
                                        "Set-Cookie": "TGC=; Domain=ecard.ccsut.cn; Path=/; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Secure"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST",
                         checkRequest: { request in
                             request.value(forHTTPHeaderField: "Cookie") == nil
                                 && tombstoneCredentials.acceptedState().acceptCount == 0
                         }),
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/charge-app/?token=\(token)&name=pays&id=408"],
                         path: "/charge/feeitem/toAppitem", query: ["feeitemid": "408"])
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: tombstoneCredentials,
                                         transport: tombstoneTransport, timeout: 2).fetchPaymentToken()
            let state = tombstoneCredentials.acceptedState()
            let outcome = await tombstoneTransport.outcome()
            let tokenCookieHeader = outcome.requests.count > 1
                ? String(describing: outcome.requests[1].value(forHTTPHeaderField: "Cookie")) : "missing request"
            check(outcome.requestCount == 3 && !outcome.mismatch,
                  "cookie deletion completes without publishing before the token request succeeds")
            check(tokenCookieHeader == "nil",
                  "cookie deletion suppresses the stale persistent value on the token request")
            check(state.acceptCount == 1 && !state.cookies.contains { $0.name == "TGC" },
                  "successful cookie deletion commits its tombstone and removes the stale cookie")
        } catch {
            check(false, "cookie deletion tombstone flow: \(error.localizedDescription)")
        }

        let globalCookie = HTTPCookie(properties: [
            .domain: ".ecard.ccsut.cn", .path: "/", .name: "TGC", .value: "global-old", .secure: "TRUE"
        ])!
        let pathCookie = HTTPCookie(properties: [
            .domain: ".ecard.ccsut.cn", .path: "/berserker-auth", .name: "TGC", .value: "path-old", .secure: "TRUE"
        ])!
        let pathCredentials = SyntheticCredentials(initialCookies: [globalCookie, pathCookie])
        let pathTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation,
                                        "Set-Cookie": "TGC=path-new; Domain=ecard.ccsut.cn; Path=/berserker-auth; Secure"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST",
                         checkRequest: { request in
                             request.value(forHTTPHeaderField: "Cookie") == "TGC=path-new"
                                 && pathCredentials.acceptedState().acceptCount == 0
                         }),
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/charge-app/?token=\(token)&name=pays&id=408"],
                         path: "/charge/feeitem/toAppitem", query: ["feeitemid": "408"],
                         checkRequest: { $0.value(forHTTPHeaderField: "Cookie") == "TGC=global-old" })
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: pathCredentials,
                                         transport: pathTransport, timeout: 2).fetchPaymentToken()
            let state = pathCredentials.acceptedState()
            let outcome = await pathTransport.outcome()
            check(outcome.requestCount == 3 && !outcome.mismatch,
                  "path-specific staged cookie wins only on matching requests")
            check(state.cookies.contains { $0.path == "/" && $0.value == "global-old" }
                      && state.cookies.contains { $0.path == "/berserker-auth" && $0.value == "path-new" },
                  "successful commit preserves broader cookie and rotates the specific path cookie")
        } catch {
            check(false, "most-specific path cookie flow: \(error.localizedDescription)")
        }

        let casService = "https://zts.ccsut.cn/passport/v1/auth/cas"
        var ecardServiceComponents = URLComponents(string: "https://ecard.ccsut.cn/berserker-auth/cas/login/wisedu")!
        ecardServiceComponents.queryItems = [URLQueryItem(name: "targetUrl", value: transitTarget)]
        let ecardService = ecardServiceComponents.url!.absoluteString
        let casLocation = URLComponents(string: "https://auth.ccsut.cn/backstage/cas/login")!
        var gatewayCASLocation = casLocation
        gatewayCASLocation.queryItems = [URLQueryItem(name: "service", value: casService)]
        var ecardCASLocation = casLocation
        ecardCASLocation.queryItems = [URLQueryItem(name: "service", value: ecardService)]
        var ecardCallback = URLComponents(string: "https://ecard.ccsut.cn/berserker-auth/cas/login/wisedu")!
        ecardCallback.queryItems = [URLQueryItem(name: "targetUrl", value: transitTarget),
                                    URLQueryItem(name: "ticket", value: "fixture-ecard-cas-ticket")]
        let configJSON = #"{"code":0,"data":{"defaultDomain":"local","authServerInfoList":[{"authType":"auth/cas","loginDomain":"cas88719","loginUrl":"/passport/v1/public/casLogin?sfDomain=cas88719"}]}}"#
        let gatewayResponses = Self.gatewayPrefix(
            authCheckBody: #"{"code":0,"data":{"sidTicket":"fixture-sid-ticket","userName":"2026123456"}}"#
        ) + [
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/berserker-auth/cas/login/wisedu?sdpAppCode=da7ce743-45f0-46d0-9b9e-a3afa4f9b2bb&unitId=59f83d72-4fef-48c4-8859-44f786e145e6"],
                         path: "/controller/v1/public/verify", query: ["t": "fixture-verify"]),
            StubResponse(200, body: "<html>deployment established</html>",
                         path: "/berserker-auth/cas/login/wisedu",
                         query: ["sdpAppCode": "da7ce743-45f0-46d0-9b9e-a3afa4f9b2bb", "unitId": "59f83d72-4fef-48c4-8859-44f786e145e6"]),
            StubResponse(302, headers: ["Location": ecardCASLocation.url!.absoluteString],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(302, headers: ["Location": ecardCallback.url!.absoluteString], path: "/backstage/cas/login"),
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/berserker-auth/cas/login/wisedu?targetUrl=https%3A%2F%2Fecard.ccsut.cn%2Fplat%3Fname%3DloginTransit"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget, "ticket": "fixture-ecard-cas-ticket"]),
            StubResponse(302, headers: ["Location": transitLocation], path: "/berserker-auth/cas/login/wisedu",
                         query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST",
                         checkRequest: { $0.value(forHTTPHeaderField: "Authorization") == "Synthetic token header" }),
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/charge-app/?token=\(token)&name=pays&id=408"],
                         path: "/charge/feeitem/toAppitem", query: ["feeitemid": "408"],
                         checkRequest: {
                             $0.value(forHTTPHeaderField: "synjones-auth") == "bearer fixture-portal-token"
                                 && $0.value(forHTTPHeaderField: "Authorization") == "Synthetic feeitem header"
                         })
        ]
        let gatewayTransport = ScriptedTransport(gatewayResponses)
        do {
            let result = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                                 transport: gatewayTransport, timeout: 2,
                                                 tokenAuthorization: "Synthetic token header",
                                                 feeItemAuthorization: "Synthetic feeitem header").fetchPaymentToken()
            let outcome = await gatewayTransport.outcome()
            check(result == token && outcome.remaining == 0 && !outcome.mismatch,
                  "gateway CAS authentication retries verification and completes the ecard CAS cycle")
            check(outcome.requests.filter { $0.url?.path == "/passport/v1/public/casLogin" }.count == 1,
                  "gateway auth configuration chooses its explicit CAS login domain instead of local default")
            check(outcome.requests[15].value(forHTTPHeaderField: "Authorization") == "Synthetic token header"
                      && outcome.requests[16].value(forHTTPHeaderField: "Authorization") == "Synthetic feeitem header"
                      && outcome.requests[..<15].allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil },
                  "optional authorization headers are sent only to their configured endpoints")
        } catch {
            let outcome = await gatewayTransport.outcome()
            let paths = outcome.requests.compactMap { $0.url?.path }.joined(separator: " -> ")
            check(false, "gateway CAS synthetic flow: \(error.localizedDescription) [\(paths)]")
        }


        for port in [nil, 80] as [Int?] {
            // Only change the outer address; encoded service/targetUrl/tickets stay byte-for-byte intact.
            let responses = gatewayResponses.map { response -> StubResponse in
                var headers = response.headers
                if let location = headers["Location"], var url = URLComponents(string: location), url.scheme == "https" {
                    url.scheme = "http"; url.port = port
                    headers["Location"] = url.url!.absoluteString
                }
                var body = String(data: response.body, encoding: .utf8)!
                if response.expectedPath == "/passport/v1/public/authConfig" {
                    let authority = port == nil ? "zts.ccsut.cn" : "zts.ccsut.cn:80"
                    body = body.replacingOccurrences(of: "\"loginUrl\":\"/", with: "\"loginUrl\":\"http://\(authority)/")
                }
                return StubResponse(response.status, headers: headers, body: body, path: response.expectedPath,
                    method: response.expectedMethod, query: response.expectedQuery, checkRequest: response.checkRequest)
            }
            let transport = ScriptedTransport(responses)
            do {
                let result = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                    transport: transport, timeout: 2, tokenAuthorization: "Synthetic token header",
                    feeItemAuthorization: "Synthetic feeitem header").fetchPaymentToken()
                let outcome = await transport.outcome()
                check(result == token && outcome.remaining == 0 && !outcome.mismatch
                      && outcome.requests.allSatisfy { $0.url?.scheme == "https" && ($0.url?.port == nil || $0.url?.port == 443) },
                      "HTTP outer SSO redirects and config upgrade safely (port \(String(describing: port)))")
                let exchange = outcome.requests.first { $0.url?.path == "/berserker-auth/oauth/token" }
                let form = String(data: exchange?.httpBody ?? Data(), encoding: .utf8) ?? ""
                check(form.contains("username=fixture%2Bticket%26part%3D2")
                      && outcome.requests.filter { $0.url?.host == "auth.ccsut.cn" }.allSatisfy {
                          $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "synjones-auth") == nil
                      }, "HTTP upgrade preserves ticket bytes and keeps token authorization off CAS")
            } catch { check(false, "HTTP outer SSO redirects and config upgrade safely (port \(String(describing: port))): \(error)") }
        }

        let rejectedHTTP = [
            "http://attacker.invalid/controller/v1/public/verify?t=fixture",
            "http://zts.ccsut.cn.attacker.invalid/controller/v1/public/verify?t=fixture",
            "http://unknown.ccsut.cn/controller/v1/public/verify?t=fixture",
            "http://zts.ccsut.cn:8080/controller/v1/public/verify?t=fixture",
            "http://user:pass@zts.ccsut.cn/controller/v1/public/verify?t=fixture",
            "http://zts.ccsut.cn/controller/v1/public/verify?t=fixture#fragment",
            "http://zts.ccsut.cn/not-allowed?t=fixture",
            "http://zts.ccsut.cn/controller/v1/public/verify?t=one&t=two",
            "http://zts.ccsut.cn/controller/v1/public/verify?t=fixture&extra=1",
            "http://auth.ccsut.cn/backstage/cas/login?service=http%3A%2F%2Fzts.ccsut.cn%2Fpassport%2Fv1%2Fauth%2Fcas",
            "http://ecard.ccsut.cn/plat?name=loginTransit&ticket=fixture&targetUrl=http%3A%2F%2Fecard.ccsut.cn%2Fplat%3Fname%3DloginTransit",
        ]
        for (index, location) in rejectedHTTP.enumerated() {
            let transport = ScriptedTransport([StubResponse(302, headers: ["Location": location,
                "Set-Cookie":"TGC=uncommitted; Domain=ecard.ccsut.cn; Path=/; Secure"], path: "/berserker-auth/cas/login/wisedu")])
            let credentials = SyntheticCredentials()
            do {
                _ = try await EcardSSOClient(account: account, credentials: credentials, transport: transport, timeout: 2).fetchPaymentToken()
                check(false, "HTTP SSO rejection boundary \(index)")
            } catch let error as EcardSSOError {
                let outcome = await transport.outcome()
                check(error == .untrustedRedirect && outcome.requestCount == 1 && credentials.acceptedState().acceptCount == 0,
                      "HTTP SSO rejection boundary \(index) sends no further request or cookie commit")
            } catch { check(false, "HTTP SSO rejection boundary \(index): wrong error") }
        }

        let badRedirectTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": "https://attacker.invalid/collect?ticket=fixture",
                                        "Set-Cookie": "TGC=untrusted-flow; Domain=ecard.ccsut.cn; Path=/; Secure"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget])
        ])
        let badRedirectCredentials = SyntheticCredentials()
        do {
            _ = try await EcardSSOClient(account: account, credentials: badRedirectCredentials,
                                         transport: badRedirectTransport, timeout: 2).fetchPaymentToken()
            check(false, "off-host redirect is rejected")
        } catch let error as EcardSSOError {
            let state = badRedirectCredentials.acceptedState()
            check(error == .untrustedRedirect && state.acceptCount == 0 && state.cookies.isEmpty,
                  "off-host redirect rejects the flow without publishing staged cookies")
        } catch {
            check(false, "off-host redirect has a fixed SSO error")
        }

        let maliciousTarget = URLComponents(string: "https://ecard.ccsut.cn/plat/")!
        var maliciousTargetComponents = maliciousTarget
        maliciousTargetComponents.queryItems = [
            URLQueryItem(name: "name", value: "loginTransit"),
            URLQueryItem(name: "ticket", value: "fixture-transit-ticket"),
            URLQueryItem(name: "targetUrl", value: "https://attacker.invalid/collect")
        ]
        let maliciousNestedTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": maliciousTargetComponents.url!.absoluteString],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget])
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: maliciousNestedTransport, timeout: 2).fetchPaymentToken()
            check(false, "unsafe nested transit target is rejected")
        } catch let error as EcardSSOError {
            check(error == .untrustedRedirect, "unsafe nested transit target is rejected")
        } catch {
            check(false, "unsafe nested target has a fixed SSO error")
        }

        let wrongSNOTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation,
                                        "Set-Cookie": "TGC=wrong-account-flow; Domain=ecard.ccsut.cn; Path=/; Secure"],
                         path: "/berserker-auth/cas/login/wisedu",
                         query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"9999999999"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST")
        ])
        let wrongSNOCredentials = SyntheticCredentials()
        do {
            _ = try await EcardSSOClient(account: account, credentials: wrongSNOCredentials,
                                         transport: wrongSNOTransport, timeout: 2).fetchPaymentToken()
            check(false, "portal token bound to another account is rejected")
        } catch let error as EcardSSOError {
            let state = wrongSNOCredentials.acceptedState()
            check(error == .identityMismatch && state.acceptCount == 0 && state.cookies.isEmpty,
                  "wrong-account token rejects the flow without publishing staged cookies")
        } catch {
            check(false, "account mismatch has a fixed SSO error")
        }

        let wrongGatewayIdentityTransport = ScriptedTransport(Self.gatewayPrefix(
            authCheckBody: #"{"code":0,"data":{"sidTicket":"fixture-sid-ticket","userName":"9999999999"}}"#
        ))
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: wrongGatewayIdentityTransport, timeout: 2).fetchPaymentToken()
            check(false, "gateway identity mismatch is terminal")
        } catch let error as EcardSSOError {
            check(error == .identityMismatch, "gateway identity mismatch is terminal")
        } catch {
            check(false, "gateway identity mismatch has a fixed SSO error")
        }

        let anonymousGatewayTransport = ScriptedTransport(Self.gatewayPrefix(
            authCheckBody: #"{"code":0,"data":{"time":1,"currentService":"fixture","nextService":"fixture"}}"#
        ))
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: anonymousGatewayTransport, timeout: 2).fetchPaymentToken()
            check(false, "HTTP 200 anonymous authCheck still requires interaction")
        } catch let error as EcardSSOError {
            check(error == .requiresInteraction, "HTTP 200 anonymous authCheck still requires interaction")
        } catch {
            check(false, "anonymous gateway check has a fixed SSO error")
        }

        var hostileServiceLocation = URLComponents(string: "https://auth.ccsut.cn/backstage/cas/login")!
        hostileServiceLocation.queryItems = [URLQueryItem(name: "service", value: "https://attacker.invalid/callback")]
        let hostileServiceTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": "https://zts.ccsut.cn/controller/v1/public/verify?t=fixture-verify"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(302, headers: ["Location": "https://zts.ccsut.cn/portal/shortcut.html"],
                         path: "/controller/v1/public/verify", query: ["t": "fixture-verify"]),
            StubResponse(200, body: "<html>fixture shortcut</html>", path: "/portal/shortcut.html"),
            StubResponse(200, body: configJSON, path: "/passport/v1/public/authConfig",
                         query: ["clientType": "SDPBrowserClient", "platform": "iOS", "lang": "zh-CN", "needTicket": "1"]),
            StubResponse(302, headers: ["Location": hostileServiceLocation.url!.absoluteString],
                         path: "/passport/v1/public/casLogin", query: ["sfDomain": "cas88719"])
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: hostileServiceTransport, timeout: 2).fetchPaymentToken()
            check(false, "nested CAS service URL is restricted to observed school endpoints")
        } catch let error as EcardSSOError {
            check(error == .untrustedRedirect, "nested CAS service URL is restricted to observed school endpoints")
        } catch {
            check(false, "unsafe nested service has a fixed SSO error")
        }

        let unsafePortalTokenTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation], path: "/berserker-auth/cas/login/wisedu",
                         query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture\r\nInjected: yes","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST")
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: unsafePortalTokenTransport, timeout: 2).fetchPaymentToken()
            check(false, "unsafe portal token cannot enter an HTTP header")
        } catch let error as EcardSSOError {
            let outcome = await unsafePortalTokenTransport.outcome()
            check(error == .invalidResponse && outcome.requestCount == 2,
                  "unsafe portal token cannot enter an HTTP header")
        } catch {
            check(false, "malformed portal token has a fixed SSO error")
        }

        let redirectedTokenPostTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/charge/feeitem/toAppitem?feeitemid=408"],
                         path: "/berserker-auth/oauth/token", method: "POST")
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: redirectedTokenPostTransport, timeout: 2,
                                         tokenAuthorization: "Synthetic token header").fetchPaymentToken()
            check(false, "token POST redirect is rejected without forwarding its authorization")
        } catch let error as EcardSSOError {
            let outcome = await redirectedTokenPostTransport.outcome()
            check(error == .untrustedRedirect && outcome.requestCount == 2,
                  "token POST redirect is rejected without forwarding its authorization")
        } catch {
            check(false, "token POST redirect has a fixed SSO error")
        }

        let wrongJWTTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation], path: "/berserker-auth/cas/login/wisedu",
                         query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST"),
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/charge-app/?token=\(jwt(account: "9999999999", expiresIn: 3_600))&name=pays&id=408"],
                         path: "/charge/feeitem/toAppitem", query: ["feeitemid": "408"])
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: wrongJWTTransport, timeout: 2).fetchPaymentToken()
            check(false, "payment JWT bound to another account is rejected")
        } catch let error as EcardSSOError {
            check(error == .identityMismatch, "payment JWT bound to another account is rejected")
        } catch {
            check(false, "payment JWT mismatch has a fixed SSO error")
        }

        let unauthorizedTransport = ScriptedTransport([
            StubResponse(401, path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget])
        ])
        let unauthorizedClient = EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                                transport: unauthorizedTransport, timeout: 2)
        do {
            _ = try await unauthorizedClient.fetchPaymentToken()
            check(false, "HTTP 401 maps to service unavailable")
        } catch let error as EcardSSOError {
            check(error == .serviceUnavailable, "HTTP 401 maps to service unavailable")
        } catch {
            check(false, "HTTP 401 has a fixed SSO error")
        }
        check(await unauthorizedClient.lastFailure == EcardSSODiagnostic(stage: .portal, reason: .serviceUnavailable),
              "native failure retains only its fixed stage and error classification")

        let failedExchangeTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(503, body: "https://untrusted.invalid/?ticket=private-fixture-value",
                         path: "/berserker-auth/oauth/token", method: "POST")
        ])
        let failedExchangeClient = EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                                  transport: failedExchangeTransport, timeout: 2)
        do { _ = try await failedExchangeClient.fetchPaymentToken(); check(false, "failed token exchange must fail") }
        catch {
            check(await failedExchangeClient.lastFailure == EcardSSODiagnostic(stage: .ticketExchange, reason: .serviceUnavailable),
                  "token exchange failure records the exchange stage without response content")
        }

        let loopTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/berserker-auth/cas/login/wisedu?targetUrl=https%3A%2F%2Fecard.ccsut.cn%2Fplat%3Fname%3DloginTransit"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget])
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: loopTransport, timeout: 2).fetchPaymentToken()
            check(false, "repeated SSO redirect terminates with a bounded error")
        } catch let error as EcardSSOError {
            let outcome = await loopTransport.outcome()
            check(error == .serviceUnavailable && outcome.requestCount <= 2,
                  "repeated SSO redirect terminates with a bounded error (\(error), \(outcome.requestCount))")
        } catch {
            check(false, "redirect loop has a fixed SSO error")
        }

        let interactionTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": "https://zts.ccsut.cn/controller/v1/public/verify?t=fixture-verify"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(302, headers: ["Location": "https://zts.ccsut.cn/portal/shortcut.html"], path: "/controller/v1/public/verify"),
            StubResponse(200, body: "<html>fixture shortcut</html>", path: "/portal/shortcut.html"),
            StubResponse(200, body: configJSON, path: "/passport/v1/public/authConfig",
                         query: ["clientType": "SDPBrowserClient", "platform": "iOS", "lang": "zh-CN", "needTicket": "1"]),
            StubResponse(302, headers: ["Location": gatewayCASLocation.url!.absoluteString],
                         path: "/passport/v1/public/casLogin", query: ["sfDomain": "cas88719"]),
            StubResponse(200, body: "<html><input type=\"password\"></html>", path: "/backstage/cas/login")
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: interactionTransport, timeout: 2).fetchPaymentToken()
            check(false, "CAS login page requests explicit interaction")
        } catch let error as EcardSSOError {
            check(error == .requiresInteraction, "CAS login page requests explicit interaction (\(error))")
        } catch {
            check(false, "interaction requirement has a fixed SSO error")
        }

        let switchedCredentials = SyntheticCredentials()
        let switchedTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation,
                                       "Set-Cookie": "TGC=rotated; Domain=ecard.ccsut.cn; Path=/; Secure"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST",
                         checkRequest: { _ in switchedCredentials.switchIdentity(); return true })
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: switchedCredentials,
                                         transport: switchedTransport, timeout: 2).fetchPaymentToken()
            check(false, "account generation change rejects late SSO response")
        } catch let error as EcardSSOError {
            let state = switchedCredentials.acceptedState()
            check(error == .identityMismatch && state.acceptCount == 0 && state.cookies.isEmpty,
                  "account generation change rejects response without publishing staged cookies")
        } catch {
            check(false, "account switch has a fixed SSO error")
        }

        let canceledCredentials = SyntheticCredentials()
        let canceledTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation,
                                        "Set-Cookie": "TGC=canceled-flow; Domain=ecard.ccsut.cn; Path=/; Secure"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST", delayMilliseconds: 1_000)
        ])
        let canceledClient = EcardSSOClient(account: account, credentials: canceledCredentials,
                                            transport: canceledTransport, timeout: 2)
        let canceledTask = Task { try await canceledClient.fetchPaymentToken() }
        try? await Task.sleep(for: .milliseconds(30))
        canceledTask.cancel()
        do {
            _ = try await canceledTask.value
            check(false, "caller cancellation remains cancellation")
        } catch is CancellationError {
            let state = canceledCredentials.acceptedState()
            check(state.acceptCount == 0 && state.cookies.isEmpty,
                  "caller cancellation remains cancellation without publishing staged cookies")
        } catch {
            check(false, "caller cancellation remains cancellation")
        }

        let timedOutTransport = ScriptedTransport([
            StubResponse(200, path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": transitTarget],
                         delayMilliseconds: 500)
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: timedOutTransport, timeout: 0.03).fetchPaymentToken()
            check(false, "request timeout is bounded")
        } catch let error as EcardSSOError {
            check(error == .serviceUnavailable, "request timeout is bounded")
        } catch {
            check(false, "timeout has a fixed SSO error")
        }

        let expiredToken = jwt(account: account, expiresIn: 0)
        let expiredTransport = ScriptedTransport([
            StubResponse(302, headers: ["Location": transitLocation], path: "/berserker-auth/cas/login/wisedu",
                         query: ["targetUrl": transitTarget]),
            StubResponse(200, body: #"{"access_token":"fixture-portal-token","token_type":"bearer","expires_in":3600,"sno":"2026123456"}"#,
                         path: "/berserker-auth/oauth/token", method: "POST"),
            StubResponse(302, headers: ["Location": "https://ecard.ccsut.cn/charge-app/?token=\(expiredToken)&name=pays&id=408"],
                         path: "/charge/feeitem/toAppitem", query: ["feeitemid": "408"])
        ])
        do {
            _ = try await EcardSSOClient(account: account, credentials: SyntheticCredentials(),
                                         transport: expiredTransport, timeout: 2).fetchPaymentToken()
            check(false, "expired payment JWT is rejected")
        } catch let error as EcardSSOError {
            check(error == .invalidResponse, "expired payment JWT is rejected")
        } catch {
            check(false, "expired payment JWT has a fixed SSO error")
        }

        if failures > 0 { exit(EXIT_FAILURE) }
    }

    private static func gatewayPrefix(authCheckBody: String) -> [StubResponse] {
        let target = "https://ecard.ccsut.cn/plat?name=loginTransit"
        let casService = "https://zts.ccsut.cn/passport/v1/auth/cas"
        var gatewayCASLocation = URLComponents(string: "https://auth.ccsut.cn/backstage/cas/login")!
        gatewayCASLocation.queryItems = [URLQueryItem(name: "service", value: casService)]
        let config = #"{"code":0,"data":{"defaultDomain":"local","authServerInfoList":[{"authType":"auth/cas","loginDomain":"cas88719","loginUrl":"/passport/v1/public/casLogin?sfDomain=cas88719"}]}}"#
        return [
            StubResponse(302, headers: ["Location": "https://zts.ccsut.cn/controller/v1/public/verify?t=fixture-verify"],
                         path: "/berserker-auth/cas/login/wisedu", query: ["targetUrl": target]),
            StubResponse(302, headers: ["Location": "https://zts.ccsut.cn/portal/shortcut.html"],
                         path: "/controller/v1/public/verify", query: ["t": "fixture-verify"]),
            StubResponse(200, body: "<html>fixture shortcut</html>", path: "/portal/shortcut.html"),
            StubResponse(200, body: config, path: "/passport/v1/public/authConfig",
                         query: ["clientType": "SDPBrowserClient", "platform": "iOS", "lang": "zh-CN", "needTicket": "1"]),
            StubResponse(302, headers: ["Location": gatewayCASLocation.url!.absoluteString],
                         path: "/passport/v1/public/casLogin", query: ["sfDomain": "cas88719"]),
            StubResponse(302, headers: ["Location": casService], path: "/backstage/cas/login"),
            StubResponse(302, headers: ["Location": "https://zts.ccsut.cn/portal/shortcut.html"],
                         path: "/passport/v1/auth/cas"),
            StubResponse(200, body: "<html>gateway portal</html>", path: "/portal/shortcut.html"),
            StubResponse(200, body: authCheckBody, path: "/passport/v1/auth/authCheck",
                         query: ["clientType": "SDPBrowserClient", "platform": "iOS", "lang": "zh-CN"])
        ]
    }

    private static func jwt(account: String, expiresIn: TimeInterval) -> String {
        let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8).base64URL
        let payload = Data(#"{"sno":"\#(account)","exp":\#(Int(Date().timeIntervalSince1970 + expiresIn))}"#.utf8).base64URL
        return "\(header).\(payload).fixture-signature"
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
