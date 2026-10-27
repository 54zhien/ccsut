import Foundation
import WebKit

/// Captures the fallback entry without making a real school request.
@MainActor private final class InertEcardWebView: WKWebView {
    var loadedRequests: [URLRequest] = []
    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return nil
    }
}

/// Render local HTML in real WebKit; the base URL supplies the origin, without school requests.
@MainActor private final class ScriptedEcardWebView: WKWebView {
    var fixtureURL = URL(string: "https://auth.ccsut.cn/backstage/cas/login")!
    private(set) var fixtureNavigation: WKNavigation?
    override func load(_ request: URLRequest) -> WKNavigation? {
        let content = fixtureURL.host == "auth.ccsut.cn"
            ? "<input type='password' style='display:block;width:200px;height:40px'>"
            : "<button onclick='window.fixtureCASClicks=(window.fixtureCASClicks||0)+1'>智林CAS</button>"
        fixtureNavigation = super.loadHTMLString("<html><body>\(content)</body></html>", baseURL: fixtureURL)
        return fixtureNavigation
    }
}

// Runs the production Session.swift/API.swift/APIResponse.swift/Models.swift on macOS without a device
// or school credentials. The only fake is the external HTTP boundary.
final class SchoolProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var requestPaths: [String] = []
    nonisolated(unsafe) static var response: (URLRequest) throws -> (Int, URL, [String: String], String) = { request in
        if ["/admin/", "/admin"].contains(request.url?.path ?? "") {
            return try SchoolProtocol.verifiedPortalResponse(for: request)
        }
        return (200, request.url!, [:], "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\",\"xsxm\":\"Fixture\"}}")
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

    static func verifiedPortalResponse(
        for request: URLRequest,
        studentNumber: String = "fixture-student",
        headers: [String: String] = [:]
    ) throws -> (Int, URL, [String: String], String) {
        guard let url = request.url,
              url.scheme == "https", url.host == "tls.ccsut.cn", ["/admin/", "/admin"].contains(url.path),
              url.query == nil, url.fragment == nil,
              studentNumber.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil
        else { throw URLError(.badServerResponse) }

        var responseHeaders = headers
        responseHeaders["Location"] = "/frontend/views/student/xkPage/index.html?username=\(studentNumber)&enc=fixture&dbname=fixture"
        return (303, url, responseHeaders, "")
    }
}

@main
struct SessionRegressionTests {
    @MainActor static func main() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SchoolProtocol.self]
        let api = APIClient(configuration: configuration)
        func sessionStore() -> SessionStore {
            SessionStore(api: api, prepareEcardSession: { _, _ in })
        }
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

        CookieJar.shared = [cookie("TGC", "fixture-old", domain: "auth.ccsut.cn")]
        CookieJar.upsert([cookie("TGC", "fixture-new", domain: ".auth.ccsut.cn")], generation: CookieJar.generation)
        check(CookieJar.shared.count == 1 && CookieJar.shared.first?.value == "fixture-new",
              "native cookie rotation replaces the normalized domain identity")
        CookieJar.upsert([cookie("TGC", "", expires: Date(timeIntervalSinceNow: -60), domain: "auth.ccsut.cn")],
                         generation: CookieJar.generation)
        check(CookieJar.shared.isEmpty, "native cookie deletion removes the normalized domain identity")

        // The SSO boundary must carry scope metadata, not flatten it into a header.
        CookieJar.shared = [
            cookie("TGC", "root", domain: "ecard.ccsut.cn"),
            cookie("TGC", "narrow", domain: "ecard.ccsut.cn", path: "/berserker-auth"),
            cookie("TGC", "other-host", domain: "auth.ccsut.cn"),
            cookie("TGC", "expired", expires: Date(timeIntervalSinceNow: -60), domain: "ecard.ccsut.cn", path: "/berserker-auth/oauth")
        ]
        let ssoCredentials = EcardCookieCredentials()
        let ssoGeneration = ssoCredentials.generation
        let tokenURL = URL(string: "https://ecard.ccsut.cn/berserker-auth/oauth/token")!
        do {
            let scoped = try ssoCredentials.cookies(for: tokenURL, expectedGeneration: ssoGeneration)
            check(scoped.count == 2 && Set(scoped.map(\.path)) == Set(["/", "/berserker-auth"])
                    && Set(scoped.map(\.value)) == Set(["root", "narrow"]),
                  "real SSO credentials retain both cookie identities and exclude expired or unrelated cookies")
            let boundary = try ssoCredentials.cookies(for: URL(string: "https://ecard.ccsut.cn/berserker-authentication")!,
                                                     expectedGeneration: ssoGeneration)
            check(boundary.count == 1 && boundary.first?.value == "root", "SSO snapshot respects cookie path boundaries")
            let insecure = try ssoCredentials.cookies(for: URL(string: "http://ecard.ccsut.cn/berserker-auth/oauth/token")!,
                                                     expectedGeneration: ssoGeneration)
            check(insecure.isEmpty, "SSO snapshot excludes Secure cookies on HTTP")
            CookieJar.shared = [cookie("TGC", "next-account", domain: "ecard.ccsut.cn")]
            do {
                _ = try ssoCredentials.cookies(for: tokenURL, expectedGeneration: ssoGeneration)
                check(false, "SSO snapshot rejects the previous account generation")
            } catch is CancellationError { check(true, "SSO snapshot rejects the previous account generation") }
            catch { check(false, "SSO snapshot rejects the previous account generation with cancellation") }
        } catch { check(false, "real SSO credential scope snapshot succeeds") }

        let protected = cookie("jw_uf", "protected", httpOnly: true)
        check(protected.isHTTPOnly && StoredCookie(protected).asHTTPCookie?.isHTTPOnly == true,
              "Keychain roundtrip preserves HttpOnly")

        let restoredTGC = cookie("TGC", "fixture-restored", httpOnly: true, domain: "auth.ccsut.cn")
        let persistedTGC = try? JSONEncoder().encode([StoredCookie(restoredTGC)])
        let decodedTGC = persistedTGC.flatMap { try? JSONDecoder().decode([StoredCookie].self, from: $0) }?.first?.asHTTPCookie
        check(decodedTGC?.value == "fixture-restored" && decodedTGC?.expiresDate == nil,
              "Keychain roundtrip retains a session-only TGC")

        CookieJar.shared = [cookie("jw_uf", "cold-start"), restoredTGC]
        WebStore.dataStore = .nonPersistent()
        SchoolProtocol.response = { request in
            if ["/admin/", "/admin"].contains(request.url?.path ?? "") {
                return try SchoolProtocol.verifiedPortalResponse(
                    for: request,
                    studentNumber: "fixture",
                    headers: ["Set-Cookie": "jw_uf=cold-rotated; Path=/; Secure; HttpOnly"]
                )
            }
            // Elective metadata is intentionally empty; it is optional enrichment only.
            return (200, request.url!, [:], "{\"ret\":0,\"data\":{}}")
        }
        let restoredSession = sessionStore()
        await restoredSession.bootstrap()
        let restoredWebCookies = (try? await WebStore.dataStore.httpCookieStore.cookieSnapshot()) ?? []
        check(restoredSession.phase == .loggedIn, "cold bootstrap retains the verified native login")
        check(restoredWebCookies.contains(where: { $0.name == "TGC" && $0.value == "fixture-restored" }),
              "cold bootstrap restores a session-only TGC into the non-persistent WebStore")
        check(restoredWebCookies.contains(where: { $0.name == "jw_uf" && $0.value == "cold-rotated" }),
              "cold bootstrap injects the validation response's rotated credentials")

        func normalizedCookieDomain(_ domain: String) -> String {
            let lowercased = domain.lowercased()
            return lowercased.hasPrefix(".") ? String(lowercased.dropFirst()) : lowercased
        }
        func sameCookieIdentity(_ lhs: HTTPCookie, _ rhs: HTTPCookie) -> Bool {
            lhs.name == rhs.name && lhs.path == rhs.path &&
                normalizedCookieDomain(lhs.domain) == normalizedCookieDomain(rhs.domain)
        }
        do {
            // A server-side value rotation preserves the existing HttpOnly attribute.
            let replacement = cookie("TGC", "new-web-value", httpOnly: true, domain: "auth.ccsut.cn")
            let beforeReplacement = try await WebStore.dataStore.httpCookieStore.cookieSnapshot()
            let priorCookie = beforeReplacement.first(where: { sameCookieIdentity($0, replacement) })
            try await WebStore.dataStore.httpCookieStore.set(replacement)
            let afterReplacement = try await WebStore.dataStore.httpCookieStore.cookieSnapshot()
            let exactReplacementVisible = afterReplacement.contains {
                sameCookieIdentity($0, replacement) && $0.domain == replacement.domain && $0.value == replacement.value
            }
            let normalizedReplacementVisible = afterReplacement.contains {
                sameCookieIdentity($0, replacement) && $0.value == replacement.value
            }
            let storedCookie = afterReplacement.first(where: { sameCookieIdentity($0, replacement) })
            print("WebKit cookie setup metadata: exactReplacement=\(exactReplacementVisible), " +
                  "normalizedReplacement=\(normalizedReplacementVisible), " +
                  "priorHTTPOnly=\(priorCookie?.isHTTPOnly ?? false), " +
                  "incomingHTTPOnly=\(replacement.isHTTPOnly), " +
                  "storedHTTPOnly=\(storedCookie?.isHTTPOnly ?? false), " +
                  "cookiesBefore=\(beforeReplacement.count), cookiesAfter=\(afterReplacement.count)")
            check(normalizedReplacementVisible, "WebKit replacement setup succeeds before fillMissing")
            if normalizedReplacementVisible {
                try await WebStore.restoreCookies(CookieJar.shared, to: WebStore.dataStore, policy: .fillMissing)
                let currentCookies = try await WebStore.dataStore.httpCookieStore.cookieSnapshot()
                check(currentCookies.contains {
                    sameCookieIdentity($0, replacement) && $0.value == replacement.value
                }, "payment restoration preserves a newer live WebKit credential")
            }
        } catch { check(false, "payment restoration test completes using the real WebKit cookie store") }

        func fixtureJWT(_ account: String) -> String {
            let claims: [String: Any] = ["sno": account, "exp": Date().addingTimeInterval(3600).timeIntervalSince1970]
            let body = try! JSONSerialization.data(withJSONObject: claims)
            let encoded = body.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return "e30.\(encoded).fixture-signature"
        }
        func inertWebView() -> InertEcardWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            return InertEcardWebView(frame: .zero, configuration: configuration)
        }
        EcardTokenBridge.clearCachedToken()
        let expectedNativeToken = fixtureJWT("fixture-native")
        let nativeWebView = inertWebView()
        let nativeBridge = EcardTokenBridge(webView: nativeWebView, nativeTokenProvider: { _, _ in expectedNativeToken })
        do {
            let actualToken = try await nativeBridge.fetchToken(forAccount: "fixture-native")
            check(actualToken == expectedNativeToken && nativeBridge.usesNativeCookies && nativeWebView.loadedRequests.isEmpty,
                  "native SSO succeeds without loading any WebView page")
            check(EcardTokenBridge.cachedTokenUsesNativeCookies(forAccount: "fixture-native"),
                  "cached native token retains its authoritative cookie source")
        } catch { check(false, "native SSO result is accepted") }

        EcardTokenBridge.clearCachedToken()
        let fallbackWebView = inertWebView()
        let fallbackBridge = EcardTokenBridge(timeout: 0.01, webView: fallbackWebView, nativeTokenProvider: { _, _ in
            throw EcardSSOError.requiresInteraction
        })
        do { _ = try await fallbackBridge.fetchToken(forAccount: "fixture-native"); check(false, "inert fallback must terminate") }
        catch {
            check(fallbackWebView.loadedRequests.count == 1 &&
                  fallbackWebView.loadedRequests.first?.url == URL(string: "https://ecard.ccsut.cn/plat/login") &&
                  !fallbackBridge.usesNativeCookies, "native interaction requirement falls back to the official WebView entry")
            check(EcardTokenBridge.lastNativeSSOFailure?.reason == .requiresInteraction,
                  "WebView fallback preserves the classified native failure in memory")
        }

        let recoveredBridge = EcardTokenBridge(webView: inertWebView(), nativeTokenProvider: { _, _ in expectedNativeToken })
        do {
            _ = try await recoveredBridge.fetchToken(forAccount: "fixture-native")
            check(EcardTokenBridge.lastNativeSSOFailure == nil, "native recovery clears the previous failure diagnosis")
        } catch { check(false, "native recovery completes") }

        EcardTokenBridge.clearCachedToken()
        let diagnosticBridge = EcardTokenBridge(timeout: 0.01, webView: inertWebView(), nativeTokenProvider: { _, _ in
            throw EcardSSODiagnostic(stage: .ticketExchange, reason: .serviceUnavailable)
        })
        do { _ = try await diagnosticBridge.fetchToken(forAccount: "fixture-native"); check(false, "diagnostic fallback must terminate") }
        catch {
            check(EcardTokenBridge.lastNativeSSOFailure == EcardSSODiagnostic(stage: .ticketExchange, reason: .serviceUnavailable),
                  "protocol stage survives the bridge and failed WebView fallback")
        }

        EcardTokenBridge.clearCachedToken()
        check(EcardTokenBridge.lastNativeSSOFailure == nil, "session invalidation clears native failure diagnostics")
        let classifiedMismatchWebView = inertWebView()
        let classifiedMismatchBridge = EcardTokenBridge(webView: classifiedMismatchWebView, nativeTokenProvider: { _, _ in
            throw EcardSSODiagnostic(stage: .gatewayVerification, reason: .identityMismatch)
        })
        do { _ = try await classifiedMismatchBridge.fetchToken(forAccount: "fixture-native"); check(false, "classified account mismatch must fail") }
        catch {
            check(error as? EcardSSOError == .identityMismatch && classifiedMismatchWebView.loadedRequests.isEmpty,
                  "classified native identity mismatch stays terminal without WebView fallback")
        }

        EcardTokenBridge.clearCachedToken()
        let mismatchWebView = inertWebView()
        let mismatchBridge = EcardTokenBridge(webView: mismatchWebView, nativeTokenProvider: { _, _ in
            throw EcardSSOError.identityMismatch
        })
        do { _ = try await mismatchBridge.fetchToken(forAccount: "fixture-native"); check(false, "wrong-account native response must fail") }
        catch { check(error as? EcardSSOError == .identityMismatch && mismatchWebView.loadedRequests.isEmpty,
                      "native account mismatch never launches a fallback login") }

        EcardTokenBridge.clearCachedToken()
        let wrongTokenWebView = inertWebView()
        let wrongTokenBridge = EcardTokenBridge(webView: wrongTokenWebView, nativeTokenProvider: { _, _ in
            fixtureJWT("fixture-other")
        })
        do { _ = try await wrongTokenBridge.fetchToken(forAccount: "fixture-native"); check(false, "wrong-account JWT must fail") }
        catch { check(error as? EcardSSOError == .identityMismatch && wrongTokenWebView.loadedRequests.isEmpty &&
                      EcardTokenBridge.cachedToken(forAccount: "fixture-other") == nil,
                      "returned wrong-account JWT is terminal and never cached") }

        EcardTokenBridge.clearCachedToken()
        let untrustedWebView = inertWebView()
        let untrustedBridge = EcardTokenBridge(webView: untrustedWebView, nativeTokenProvider: { _, _ in
            throw EcardSSOError.untrustedRedirect
        })
        do { _ = try await untrustedBridge.fetchToken(forAccount: "fixture-native"); check(false, "untrusted native redirect must fail") }
        catch { check(error as? EcardSSOError == .untrustedRedirect && untrustedWebView.loadedRequests.isEmpty,
                      "untrusted native redirect never launches a fallback login") }

        EcardTokenBridge.clearCachedToken()
        let clearedWebView = inertWebView()
        let clearedBridge = EcardTokenBridge(webView: clearedWebView, nativeTokenProvider: { _, _ in
            EcardTokenBridge.clearCachedToken()
            return expectedNativeToken
        })
        do { _ = try await clearedBridge.fetchToken(forAccount: "fixture-native"); check(false, "late native result after cache clear must fail") }
        catch { check(clearedWebView.loadedRequests.isEmpty && EcardTokenBridge.cachedToken(forAccount: "fixture-native") == nil,
                      "cache clear discards a late native result without fallback or caching") }
        check(EcardTokenBridge.lastNativeSSOFailure == nil, "late result cannot republish a diagnosis after session invalidation")

        EcardTokenBridge.clearCachedToken()
        let canceledWebView = inertWebView()
        let canceledBridge = EcardTokenBridge(webView: canceledWebView, nativeTokenProvider: { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return expectedNativeToken
        })
        let canceledFetch = Task { @MainActor in try await canceledBridge.fetchToken(forAccount: "fixture-native") }
        do { _ = try await canceledFetch.value; check(false, "canceled native request must fail") }
        catch { check(canceledWebView.loadedRequests.isEmpty && EcardTokenBridge.cachedToken(forAccount: "fixture-native") == nil,
                      "caller cancellation discards a late native token without fallback or caching") }
        check(EcardTokenBridge.lastNativeSSOFailure == nil, "cancellation never publishes a failure diagnosis")

        EcardTokenBridge.clearCachedToken()
        let staleFailureWebView = inertWebView()
        let staleFailureBridge = EcardTokenBridge(webView: staleFailureWebView, nativeTokenProvider: { _, _ in
            CookieJar.shared = []
            throw EcardSSODiagnostic(stage: .ticketExchange, reason: .serviceUnavailable)
        })
        do { _ = try await staleFailureBridge.fetchToken(forAccount: "fixture-native"); check(false, "stale native failure must fail") }
        catch {
            check(staleFailureWebView.loadedRequests.isEmpty && EcardTokenBridge.lastNativeSSOFailure == nil,
                  "account switch discards a late failure diagnosis without fallback")
        }

        EcardTokenBridge.clearCachedToken()
        let switchedWebView = inertWebView()
        let switchedBridge = EcardTokenBridge(webView: switchedWebView, nativeTokenProvider: { _, _ in
            CookieJar.shared = []
            return expectedNativeToken
        })
        do { _ = try await switchedBridge.fetchToken(forAccount: "fixture-native"); check(false, "late native result after account change must fail") }
        catch { check(switchedWebView.loadedRequests.isEmpty && EcardTokenBridge.cachedToken(forAccount: "fixture-native") == nil,
                      "account change discards a late native token without fallback or caching") }
        EcardTokenBridge.clearCachedToken()

        func waitForFixture(_ ready: () -> Bool) async {
            for _ in 0..<300 {
                if ready() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        func fixtureScript(_ view: WKWebView, _ script: String) async -> Any? {
            try? await withCheckedThrowingContinuation { (result: CheckedContinuation<Any?, Error>) in
                view.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) {
                    switch $0 {
                    case .success(let value): result.resume(returning: value)
                    case .failure(let error): result.resume(throwing: error)
                    }
                }
            }
        }
        let interactionView = ScriptedEcardWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: WKWebViewConfiguration())
        let interactionBridge = EcardTokenBridge(timeout: 10, webView: interactionView, nativeTokenProvider: { _, _ in
            throw EcardSSOError.requiresInteraction
        })
        var interactionReports = 0
        interactionBridge.onNeedsInteraction = { interactionReports += 1 }
        let interactionFetch = Task { @MainActor in try await interactionBridge.fetchToken(forAccount: "fixture-native") }
        await waitForFixture { interactionView.fixtureNavigation != nil && !interactionView.isLoading }
        let localOrigin = await fixtureScript(interactionView, "return location.origin;") as? String
        check(localOrigin == "https://auth.ccsut.cn", "local WebKit fixture has the expected authentication origin")
        await waitForFixture { interactionReports == 1 }
        check(interactionReports == 1,
              "fallback consumes the WebKit boolean result and reports real login interaction")
        interactionBridge.webView(interactionView, didFinish: interactionView.fixtureNavigation)
        try? await Task.sleep(for: .milliseconds(50))
        check(interactionReports == 1, "the same fallback login is reported only once")
        interactionFetch.cancel()
        _ = try? await interactionFetch.value
        EcardTokenBridge.clearCachedToken()

        let portalView = ScriptedEcardWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: WKWebViewConfiguration())
        portalView.fixtureURL = URL(string: "https://ecard.ccsut.cn/plat/login")!
        let portalBridge = EcardTokenBridge(timeout: 10, webView: portalView, nativeTokenProvider: { _, _ in
            throw EcardSSOError.requiresInteraction
        })
        let portalFetch = Task { @MainActor in try await portalBridge.fetchToken(forAccount: "fixture-native") }
        await waitForFixture { portalView.fixtureNavigation != nil && !portalView.isLoading }
        var initialClicks = 0
        for _ in 0..<100 {
            initialClicks = (await fixtureScript(portalView, "return window.fixtureCASClicks || 0;") as? NSNumber)?.intValue ?? 0
            if initialClicks == 1 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        check(initialClicks == 1, "local WebKit portal fixture activates the observed CAS entry")
        portalBridge.webView(portalView, didFinish: portalView.fixtureNavigation)
        try? await Task.sleep(for: .milliseconds(300))
        let finalClicks = (await fixtureScript(portalView, "return window.fixtureCASClicks || 0;") as? NSNumber)?.intValue
        check(finalClicks == 1,
              "fallback consumes the portal action result and does not repeat the CAS entry")
        portalFetch.cancel()
        _ = try? await portalFetch.value
        EcardTokenBridge.clearCachedToken()

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
        let unavailable = sessionStore()
        check(!(await unavailable.probe()), "HTTP 503 is not a valid session")

        SchoolProtocol.response = { _ in (200, URL(string: "https://auth.ccsut.cn/backstage/cas/login")!, [:], "login form") }
        let loginPage = sessionStore()
        check(!(await loginPage.probe()), "CAS login page with HTTP 200 is not a valid session")

        SchoolProtocol.response = { (200, $0.url!, [:], "{\"ret\":-1,\"msg\":\"rejected\",\"data\":{\"xsxh\":\"fixture-student\"}}") }
        let rejected = sessionStore()
        check(!(await rejected.probe()), "authentication rejects a nonzero result even with identity data")

        SchoolProtocol.response = { _ in throw URLError(.timedOut) }
        let coldStart = sessionStore()
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
        let failedAdoption = sessionStore()
        check(!(await failedAdoption.adoptCookies()), "failed business probe rejects WebKit adoption")
        check(CookieJar.shared.first(where: { $0.name == "jw_uf" })?.value == "previous",
              "failed WebKit adoption preserves the previous credentials")
        let afterFailure = Keychain.load("ccsut.cookies.v2").flatMap { try? JSONDecoder().decode([StoredCookie].self, from: $0) }
        check(afterFailure?.first(where: { $0.name == "jw_uf" })?.value == "previous",
              "unverified WebKit credentials do not overwrite Keychain")

        SchoolProtocol.response = { request in
            if ["/admin/", "/admin"].contains(request.url?.path ?? "") {
                return try SchoolProtocol.verifiedPortalResponse(
                    for: request,
                    headers: ["Set-Cookie": "jw_uf=verified; Path=/; Secure; HttpOnly"]
                )
            }
            return (200, request.url!, ["Set-Cookie": "jw_uf=verified; Path=/; Secure; HttpOnly"],
                    "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}")
        }
        let validAdoption = sessionStore()
        check(await validAdoption.adoptCookies(), "verified WebKit adoption succeeds")
        check(CookieJar.header(for: "tls.ccsut.cn") == "jw_uf=verified",
              "successful adoption keeps the probe's rotated Cookie")

        CookieJar.shared = [cookie("jw_uf", "old"), cookie("TGC", "fixture-tgc", domain: "auth.ccsut.cn")]
        var offlineCASRequests = 0
        SchoolProtocol.response = { request in
            if request.url?.path == "/admin/caslogin" { offlineCASRequests += 1 }
            throw URLError(.timedOut)
        }
        let bootstrap = sessionStore()
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
            if ["/admin/", "/admin"].contains(url.path) { return try SchoolProtocol.verifiedPortalResponse(for: req) }
            return (200, url, [:], "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}")
        }
        let renewal = sessionStore()
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

        for port in ["", ":80"] {
            CookieJar.shared = [cookie("TGC", "http-fixture", domain: "auth.ccsut.cn")]
            var allHTTPS = true
            var correctScopedCookies = true
            var preservedTicket = false
            SchoolProtocol.response = { request in
                let url = request.url!
                allHTTPS = allHTTPS && url.scheme == "https" && (url.port == nil || url.port == 443)
                if url.host == "auth.ccsut.cn" {
                    correctScopedCookies = correctScopedCookies && request.value(forHTTPHeaderField: "Cookie") == "TGC=http-fixture"
                    return (302, url, ["Location":"http://tls.ccsut.cn\(port)/admin/caslogin?ticket=fixture%2Bticket%26part%3D2"], "")
                }
                if url.path == "/admin/caslogin" {
                    correctScopedCookies = correctScopedCookies && request.value(forHTTPHeaderField: "Cookie") == nil
                    if url.query == nil {
                        return (302, url, ["Location":"http://auth.ccsut.cn\(port)/backstage/cas/login?service=https%3A%2F%2Ftls.ccsut.cn%2Fadmin%2Fcaslogin"], "")
                    }
                    preservedTicket = url.query == "ticket=fixture%2Bticket%26part%3D2"
                    return (302, url, ["Location":"/frontend/student", "Set-Cookie":"jw_uf=http-renewed; Path=/; Secure"], "")
                }
                if ["/admin/", "/admin"].contains(url.path) { return try SchoolProtocol.verifiedPortalResponse(for: request) }
                return (200, url, [:], "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}")
            }
            let store = sessionStore()
            await store.refresh()
            check(store.phase == .loggedIn && allHTTPS && correctScopedCookies && preservedTicket
                  && CookieJar.header(for: "tls.ccsut.cn") == "jw_uf=http-renewed",
                  "HTTP CAS renewal upgrades before Secure cookie matching and preserves ticket bytes (port \(port))")
        }

        let rejectedAcademicURLs = [
            "http://attacker.invalid/admin/caslogin", "http://auth.ccsut.cn.attacker.invalid/backstage/cas/login",
            "http://unknown.ccsut.cn/admin/caslogin", "http://auth.ccsut.cn:8080/backstage/cas/login",
            "http://user:pass@auth.ccsut.cn/backstage/cas/login", "http://auth.ccsut.cn/backstage/cas/login#fragment"
        ]
        for (index, location) in rejectedAcademicURLs.enumerated() {
            CookieJar.shared = [cookie("TGC", "fixture", domain: "auth.ccsut.cn")]
            SchoolProtocol.requestCount = 0
            SchoolProtocol.response = { request in (302, request.url!, ["Location":location], "") }
            do {
                _ = try await api.response(for: URLRequest(url: URL(string: "https://tls.ccsut.cn/admin/caslogin")!),
                                           allowAuthenticationRedirects: true)
                check(false, "HTTP academic rejection boundary \(index)")
            } catch {
                check((error as? APIError).map { if case .notLoggedIn = $0 { return true }; return false } == true
                      && SchoolProtocol.requestCount == 1, "HTTP academic rejection boundary \(index) sends no further request")
            }
        }

        for status in [307, 308] {
            CookieJar.shared = [cookie("jw_uf", "fixture"), cookie("TGC", "fixture", domain: "auth.ccsut.cn")]
            SchoolProtocol.requestCount = 0
            SchoolProtocol.response = { request in
                (status, request.url!, ["Location":"http://auth.ccsut.cn/backstage/cas/login"], "")
            }
            var request = URLRequest(url: URL(string: "https://tls.ccsut.cn/admin/business")!)
            request.httpMethod = "POST"; request.httpBody = Data("synthetic=form".utf8)
            do {
                _ = try await api.response(for: request, allowAuthenticationRedirects: true)
                check(false, "HTTP upgrade never forwards a cross-host business POST (\(status))")
            } catch {
                check(SchoolProtocol.requestCount == 1, "HTTP upgrade never forwards a cross-host business POST (\(status))")
            }
        }
        CookieJar.shared = [cookie("TGC", "fixture", domain: "auth.ccsut.cn")]
        SchoolProtocol.requestCount = 0
        SchoolProtocol.response = { request in (302, request.url!, ["Location":"http://AUTH.ccsut.cn/backstage/cas/login"], "") }
        do {
            _ = try await api.html("/admin/business")
            check(false, "HTTP upgrade does not enable authentication redirects for business calls")
        } catch { check(SchoolProtocol.requestCount == 1, "HTTP upgrade does not enable authentication redirects for business calls") }

        SchoolProtocol.requestCount = 0
        SchoolProtocol.response = { request in (302, request.url!, ["Location":"http://tls.ccsut.cn:80/loop"], "") }
        do { _ = try await api.html("/loop"); check(false, "HTTP normalization retains academic redirect limit") }
        catch { check((error as? URLError)?.code == .httpTooManyRedirects && SchoolProtocol.requestCount == 8,
                      "HTTP normalization retains academic redirect limit") }

        CookieJar.shared = [cookie("TGC", "before-switch", domain: "auth.ccsut.cn")]
        SchoolProtocol.requestCount = 0
        SchoolProtocol.response = { request in
            CookieJar.shared = []
            return (302, request.url!, ["Location":"http://auth.ccsut.cn/backstage/cas/login"], "")
        }
        do {
            _ = try await api.response(for: URLRequest(url: URL(string: "https://tls.ccsut.cn/admin/caslogin")!),
                                       allowAuthenticationRedirects: true)
            check(false, "account change aborts before upgraded HTTP hop")
        } catch is CancellationError { check(SchoolProtocol.requestCount == 1, "account change aborts before upgraded HTTP hop") }
        catch { check(false, "account change aborts upgraded HTTP hop with cancellation") }

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

        let loggedOut = sessionStore()
        let teachingWeekCacheKey = "ccsut.teachingWeek.v1"
        let previousTeachingWeekCache = UserDefaults.standard.object(forKey: teachingWeekCacheKey)
        UserDefaults.standard.set(Data("fixture-account-cache".utf8), forKey: teachingWeekCacheKey)
        defer {
            if let previousTeachingWeekCache {
                UserDefaults.standard.set(previousTeachingWeekCache, forKey: teachingWeekCacheKey)
            } else {
                UserDefaults.standard.removeObject(forKey: teachingWeekCacheKey)
            }
        }
        await loggedOut.logout()
        check(CookieJar.shared.isEmpty, "logout clears the authoritative Cookie jar")
        check(Keychain.load("ccsut.cookies.v2") == nil, "logout removes persisted credentials")
        check(UserDefaults.standard.object(forKey: teachingWeekCacheKey) == nil,
              "logout removes the prior account teaching-week snapshot")
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

        // Complete personal courses use their own strict flat-grid decoder and fixed read-only routes.
        CookieJar.shared = [cookie("jw_uf", "personal-course-fixture")]
        let courseGeneration = CookieJar.generation
        resetProtocolRequests()
        let personalTerms = ["2026-2027-1","2024-2025-1"]
        SchoolProtocol.response = { request in
            guard request.url?.scheme == "https", request.url?.host == "tls.ccsut.cn" else { throw URLError(.badURL) }
            if request.url!.path == "/admin/xsd/yxkccx" {
                guard request.httpMethod == "GET" else { throw URLError(.badServerResponse) }
                return (200,request.url!,[:],"<select id='xnxq'><option value='2026-2027-1' selected>Current</option><option value='2024-2025-1'>Past</option></select>")
            }
            guard request.url!.path == "/admin/xsd/yxkccx/listYxkc", request.httpMethod == "POST",
                  let body = SchoolProtocol.bodyText(request),
                  let items = URLComponents(string:"https://fixture.invalid/?" + body)?.queryItems else { throw URLError(.badServerResponse) }
            let form = Dictionary(items.map { ($0.name,$0.value ?? "") },uniquingKeysWith:{a,_ in a})
            let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems ?? []
            guard let term = form["xnxq"], personalTerms.contains(term), form["query.xnxq||"] == term,
                  form["page.size"] == "100", let pn = Int(form["page.pn"] ?? ""), (1...2).contains(pn),
                  ["kklx","kcxz","xdxz","xklx"].allSatisfy({form[$0] == "" && form["query.\($0)||"] == ""}),
                  query.contains(URLQueryItem(name:"gridtype",value:"jqgrid")), query.contains(URLQueryItem(name:"async",value:"1")),
                  request.value(forHTTPHeaderField:"Referer") == "https://tls.ccsut.cn/admin/xsd/yxkccx" else { throw URLError(.badServerResponse) }
            let payload: [String:Any] = ["ret":0,"page":pn,"rows":1,"total":2,"totalPages":2,"results":[
                ["id":"personal-\(pn)","xnxq":term,"kcmc":"Fixture personal course","jxbbh":"fixture-\(pn)","xdfs":"1","xkfs":pn == 1 ? "选课" : "配课"]
            ]]
            return (200,request.url!,[:],String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self))
        }
        do {
            let context = try await api.enrolledCoursesContext(expectedGeneration:courseGeneration)
            check(context.terms == personalTerms && context.defaultTerm == personalTerms[0],"personal course context comes from the official selector, including history")
            for term in personalTerms {
                let courses = try await api.enrolledCourses(term:term,expectedGeneration:courseGeneration)
                check(courses.count == 2 && courses.allSatisfy({$0.xnxq == term}),"real personal-course client follows server page size and preserves term attribution")
            }
            check(SchoolProtocol.requestCount == 5 && Set(SchoolProtocol.requestPaths) == ["/admin/xsd/yxkccx","/admin/xsd/yxkccx/listYxkc"],
                  "current and past course reads use only discovery and result queries, with no mutations")
        } catch { check(false,"personal-course discovery and grid load through the production API boundary: \(error)") }
        resetProtocolRequests()
        CookieJar.shared = [cookie("jw_uf", "replacement-course-fixture")]
        do {
            _ = try await api.enrolledCourses(term:personalTerms[0],expectedGeneration:courseGeneration)
            check(false,"personal-course request rejects previous account generation")
        } catch { check(SchoolProtocol.requestCount == 0,"personal-course request rejects previous account generation before transmission") }

        print("Session regression failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
