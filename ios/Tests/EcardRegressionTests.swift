import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if !ECARD_WEBKIT_DOUBLE
import WebKit
import Darwin
#endif

final class EcardProtocol: URLProtocol {
    nonisolated(unsafe) static var respond: (URLRequest) throws -> (Int, String) = { _ in
        throw URLError(.unsupportedURL)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    static func form(_ request: URLRequest) -> [String: String] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: data, as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}

@main @MainActor struct EcardRegressionTests {
    static var failures = 0
    static func check(_ value: Bool, _ name: String) {
        print("\(value ? "PASS" : "FAIL") \(name)")
        if !value { failures += 1 }
    }
    static func pause() async { try? await Task.sleep(nanoseconds: 15_000_000) }
    static func jwt(_ account: String = "student-B", seconds: TimeInterval = 3600) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["sno": account, "exp": Date().timeIntervalSince1970 + seconds])
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "e30.\(payload).fixture-signature"
    }
    static func bridge() -> (EcardTokenBridge, OfflineEcardWebView) {
        EcardTokenBridge.clearCachedToken()
        #if ECARD_WEBKIT_DOUBLE
        let bridge = EcardTokenBridge(timeout: 0.2)
        return (bridge, bridge.webView)
        #else
        let view = OfflineEcardWebView(frame: .zero, configuration: WKWebViewConfiguration())
        return (EcardTokenBridge(timeout: 0.2, webView: view, nativeTokenProvider: { _, _ in throw EcardSSOError.serviceUnavailable }), view)
        #endif
    }
    static func setURL(_ view: OfflineEcardWebView, _ url: URL) {
        #if ECARD_WEBKIT_DOUBLE
        view.url = url
        #else
        view.pageURL = url
        #endif
    }
    static func deliver(_ bridge: EcardTokenBridge, _ view: OfflineEcardWebView,
                        navigation: WKNavigation, token: String) {
        setURL(view, URL(string: "https://ecard.ccsut.cn/charge-app/?token=\(token)")!)
        bridge.webView(view, didReceiveServerRedirectForProvisionalNavigation: navigation)
    }
    static func main() async {
        #if !ECARD_WEBKIT_DOUBLE
        setbuf(stdout, nil)
        #endif
        await paymentTests()
        await loginTests()
        print("Ecard regression failures: \(failures)")
        if failures > 0 { exit(1) }
    }
    static func paymentTests() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EcardProtocol.self]
        let client = EcardClient(token: "fixture-token", configuration: configuration)
        let ready = #"{"code":200,"success":true,"data":{"orderid":"fixture-order","payList":[{"id":"69","code":"CARDTSM","nopassword":"0"}]}}"#
        for failure in ["timeout", "malformed", "canceled", "http", "httpJSON"] {
            var payments = 0
            var queries = 0
            EcardProtocol.respond = { request in
                if request.url!.path.contains("getpayinfo") {
                    queries += 1
                    return (200, #"{"code":200,"order":{"orderid":"fixture-order","status":0}}"#)
                }
                let form = EcardProtocol.form(request)
                if form["paystep"] == "0" { return (200, ready) }
                payments += 1
                switch failure {
                case "timeout": throw URLError(.timedOut)
                case "canceled": throw URLError(.cancelled)
                case "http": return (502, "bad gateway")
                case "httpJSON": return (502, #"{"code":500,"msg":"upstream timeout"}"#)
                default: return (200, "truncated JSON")
                }
            }
            do {
                let result = try await client.rechargeElectricity(amount: 10, context: MeterContext())
                check(!result.isCompleted && result.orderID == "fixture-order" && payments == 1 && queries == 1,
                      "\(failure) after payment submission retains order and never resubmits")
            } catch { check(false, "\(failure) after payment submission must not become retryable error: \(error)") }
        }
        var payments = 0
        var rejectionQueries = 0
        EcardProtocol.respond = { request in
            if request.url!.path.contains("getpayinfo") {
                rejectionQueries += 1
                return (200, #"{"code":200,"order":{"orderid":"fixture-order","status":0}}"#)
            }
            let form = EcardProtocol.form(request)
            if form["paystep"] == "0" { return (200, ready) }
            payments += 1
            return (200, #"{"code":200,"success":false,"msg":"insufficient balance"}"#)
        }
        do {
            let result = try await client.rechargeElectricity(amount: 10, context: MeterContext())
            check(!result.isCompleted && result.orderID == "fixture-order" && payments == 1 && rejectionQueries == 1,
                  "business rejection after dispatch retains and reconciles the original order without another debit")
        } catch { check(false, "post-dispatch business rejection must preserve the uncertain order: \(error)") }

        EcardProtocol.respond = { request in
            let form = EcardProtocol.form(request)
            if form["paystep"] == "0" {
                return (200, #"{"code":200,"success":true,"data":{"orderid":"fixture-order","payList":[{"id":"","code":"CARDTSM","nopassword":"0"},{"id":"69","code":"CARDTSM","nopassword":"0"}]}}"#)
            }
            if request.url!.path.contains("getpayinfo") {
                return (200, #"{"code":200,"order":{"orderid":"fixture-order","status":1}}"#)
            }
            checkFormID = form["paytypeid"]
            return (200, #"{"code":200,"success":true}"#)
        }
        checkFormID = nil
        do {
            let result = try await client.rechargeElectricity(amount: 10, context: MeterContext())
            check(result.isCompleted && checkFormID == "69", "skip balance channels with empty identifiers")
        } catch { check(false, "valid second channel selected: \(error)") }
        let raw = "room\nname\t\"quoted\""
        let quoted = MeterContext.jsonQuoted(raw)
        check((try? JSONDecoder().decode(String.self, from: Data(quoted.utf8))) == raw,
              "meter context JSON preserves control characters")
        let map = try! JSONDecoder().decode(ThirdDataMap.self, from: Data(#"{"data":{"sysId":"null"}}"#.utf8))
        check(map.meterContext?.formFields["sysId"] == "\"null\"", "literal null context is passed back unchanged")
    }
    nonisolated(unsafe) static var checkFormID: String?

    static func loginTests() async {
        let (retryLogin, _) = bridge()
        for attempt in 1...2 {
            do {
                _ = try await retryLogin.fetchToken(forAccount: "student-B")
                check(false, "attempt \(attempt) without a token must time out")
            } catch EcardError.authenticationTimeout(.starting) {
                check(true, "attempt \(attempt) finishes with its actual authentication stage timeout")
            } catch { check(false, "attempt \(attempt) timeout reason: \(error)") }
        }
        let (cancelLogin, cancelView) = bridge()
        let canceled = Task { try await cancelLogin.fetchToken(forAccount: "student-B") }
        await pause()
        canceled.cancel()
        let following = Task { try await cancelLogin.fetchToken(forAccount: "student-B") }
        await pause()
        let followingToken = jwt()
        deliver(cancelLogin, cancelView, navigation: cancelView.navigations.last!, token: followingToken)
        let canceledValue = try? await canceled.value
        let followingValue = try? await following.value
        check(canceledValue == nil && followingValue == followingToken,
              "canceling an older task leaves the following request usable")
        check(EcardTokenBridge.cachedToken(forAccount: "student-B") == followingToken &&
              EcardTokenBridge.cachedToken(forAccount: "student-A") == nil &&
              EcardTokenBridge.cachedToken(forAccount: nil) == nil,
              "token cache only serves its named account")

        let (login, view) = bridge()
        let first = Task { try await login.fetchToken(forAccount: "student-B") }
        await pause()
        let oldNavigation = view.navigations.last!
        let second = Task { try await login.fetchToken(forAccount: "student-B") }
        await pause()
        let newNavigation = view.navigations.last!
        login.webView(view, didFailProvisionalNavigation: oldNavigation, withError: URLError(.cannotFindHost))
        await pause()
        let fresh = jwt()
        deliver(login, view, navigation: newNavigation, token: fresh)
        check((try? await second.value) == fresh, "old navigation error cannot terminate the replacement request")
        _ = try? await first.value

        let (scriptLogin, scriptView) = bridge()
        let scriptFirst = Task { try await scriptLogin.fetchToken(forAccount: "student-B") }
        await pause()
        setURL(scriptView, URL(string: "https://ecard.ccsut.cn/charge-app/")!)
        scriptLogin.webView(scriptView, didFinish: scriptView.navigations.last!)
        await pause()
        let oldScript = scriptView.scriptCompletion
        check(oldScript != nil, "trusted payment page starts storage fallback")
        let scriptSecond = Task { try await scriptLogin.fetchToken(forAccount: "student-B") }
        await pause()
        oldScript?(jwt(seconds: 7200), nil)
        await pause()
        let replacement = jwt(seconds: 10800)
        deliver(scriptLogin, scriptView, navigation: scriptView.navigations.last!, token: replacement)
        check((try? await scriptSecond.value) == replacement, "old JavaScript result cannot finish a newer request")
        _ = try? await scriptFirst.value

        let (logoutLogin, logoutView) = bridge()
        let logoutTask = Task { try await logoutLogin.fetchToken(forAccount: "student-B") }
        await pause()
        EcardTokenBridge.clearCachedToken()
        deliver(logoutLogin, logoutView, navigation: logoutView.navigations.last!, token: jwt())
        check((try? await logoutTask.value) == nil && EcardTokenBridge.cachedToken(forAccount: "student-B") == nil,
              "logout invalidates in-flight token and prevents cache resurrection")

        let (deliveredLogin, deliveredView) = bridge()
        let deliveredTask = Task { try await deliveredLogin.fetchToken(forAccount: "student-B") }
        await pause()
        deliver(deliveredLogin, deliveredView, navigation: deliveredView.navigations.last!, token: jwt())
        // The continuation is resumed, but its caller has not run yet.
        EcardTokenBridge.clearCachedToken()
        check((try? await deliveredTask.value) == nil,
              "logout also fences a token already resumed but not yet returned")

        for location in ["http://ecard.ccsut.cn/charge-app/", "https://ecard.ccsut.cn/plat/login",
                         "https://ecard.ccsut.cn/charge-app-other/"] {
            let (restricted, restrictedView) = bridge()
            let waiting = Task { try await restricted.fetchToken(forAccount: "student-B") }
            await pause()
            setURL(restrictedView, URL(string: location)!)
            restricted.webView(restrictedView, didFinish: restrictedView.navigations.last!)
            await pause()
            let scriptStarted = restrictedView.scriptCompletion != nil
            restrictedView.scriptCompletion?(jwt(), nil)
            waiting.cancel()
            _ = try? await waiting.value
            check(!scriptStarted, "storage fallback rejects \(location)")
        }
        let (expiry, expiryView) = bridge()
        let expiryTask = Task { try await expiry.fetchToken(forAccount: "student-B") }
        await pause()
        deliver(expiry, expiryView, navigation: expiryView.navigations.last!, token: jwt(seconds: -3600))
        let expiryResult = try? await expiryTask.value
        check(expiryResult == nil, "expired token is never returned")
    }
}
