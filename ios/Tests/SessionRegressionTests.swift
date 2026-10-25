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

/// The external WebKit boundary returns actual callback values without loading a school page.
@MainActor private final class ScriptedEcardWebView: WKWebView {
    let fixtureNavigation = WKNavigation()
    var fixtureURL = URL(string: "https://auth.ccsut.cn/backstage/cas/login")!
    var interactionResult = true
    var callbackCount = 0
    var allowedCASActions: [Bool] = []
    override var url: URL? { fixtureURL }
    override var isLoading: Bool { false }
    override func load(_ request: URLRequest) -> WKNavigation? { fixtureNavigation }
    override func callAsyncJavaScript(_ functionBody: String, arguments: [String: Any] = [:],
                                     in frame: WKFrameInfo?, in contentWorld: WKContentWorld,
                                     completionHandler: ((Result<Any, Error>) -> Void)? = nil) {
        let result: Any
        if let allowCAS = arguments["allowCAS"] as? Bool {
            allowedCASActions.append(allowCAS)
            result = allowCAS ? "cas" : ""
        } else { result = interactionResult }
        if let completionHandler { callbackCount += 1; completionHandler(.success(result)) }
    }
}

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
        var coldStartReads = 0
        SchoolProtocol.response = { request in
            coldStartReads += 1
            // Only the validation returns an identity. The follow-up profile
            // is empty so this offline test never launches a real SSO prefetch.
            let body = coldStartReads == 1 ? "{\"ret\":0,\"data\":{\"xsxh\":\"fixture\"}}" : "{\"ret\":0,\"data\":{}}"
            return (200, request.url!, ["Set-Cookie": "jw_uf=cold-rotated; Path=/; Secure; HttpOnly"], body)
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

        let interactionView = ScriptedEcardWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let interactionBridge = EcardTokenBridge(timeout: 5, webView: interactionView, nativeTokenProvider: { _, _ in
            throw EcardSSOError.requiresInteraction
        })
        var interactionReports = 0
        interactionBridge.onNeedsInteraction = { interactionReports += 1 }
        let interactionFetch = Task { @MainActor in try await interactionBridge.fetchToken(forAccount: "fixture-native") }
        for _ in 0..<100 { if interactionView.navigationDelegate != nil { break }; try? await Task.sleep(for: .milliseconds(10)) }
        // Wait for the native fallback's load to bind this navigation to the active request.
        try? await Task.sleep(for: .milliseconds(100))
        interactionBridge.webView(interactionView, didFinish: interactionView.fixtureNavigation)
        try? await Task.sleep(for: .milliseconds(100))
        check(interactionReports == 1 && interactionView.callbackCount == 1,
              "fallback consumes the WebKit boolean result and reports real login interaction")
        interactionBridge.webView(interactionView, didFinish: interactionView.fixtureNavigation)
        try? await Task.sleep(for: .milliseconds(50))
        check(interactionReports == 1, "the same fallback login is reported only once")
        interactionFetch.cancel()
        _ = try? await interactionFetch.value
        EcardTokenBridge.clearCachedToken()

        let portalView = ScriptedEcardWebView(frame: .zero, configuration: WKWebViewConfiguration())
        portalView.fixtureURL = URL(string: "https://ecard.ccsut.cn/plat/login")!
        portalView.interactionResult = false
        let portalBridge = EcardTokenBridge(timeout: 5, webView: portalView, nativeTokenProvider: { _, _ in
            throw EcardSSOError.requiresInteraction
        })
        let portalFetch = Task { @MainActor in try await portalBridge.fetchToken(forAccount: "fixture-native") }
        try? await Task.sleep(for: .milliseconds(100))
        portalBridge.webView(portalView, didFinish: portalView.fixtureNavigation)
        try? await Task.sleep(for: .milliseconds(100))
        portalBridge.webView(portalView, didFinish: portalView.fixtureNavigation)
        try? await Task.sleep(for: .milliseconds(100))
        check(portalView.allowedCASActions == [true, false] && portalView.callbackCount == 2,
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

        SchoolProtocol.response = { (200, $0.url!, ["Set-Cookie": "jw_uf=verified; Path=/; Secure; HttpOnly"],
                                     "{\"ret\":0,\"data\":{\"xsxh\":\"fixture-student\"}}") }
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
