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
    struct ReadinessFailure: Error, CustomStringConvertible {
        let description: String
    }
    static func waitUntil(_ description: String, timeout: TimeInterval = 5,
                          condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                throw ReadinessFailure(description: "Timed out waiting for \(description)")
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
    static func navigation(_ view: OfflineEcardWebView, count: Int,
                           _ description: String) async throws -> WKNavigation {
        try await waitUntil("\(description): navigation count >= \(count)") {
            view.navigations.count >= count
        }
        return view.navigations[count - 1]
    }
    // A negative assertion needs a bounded observation window while the request
    // remains live; readiness of positive callbacks is always condition-based.
    static func observesUnexpectedCallback(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(0.5))
        repeat {
            if condition() { return true }
            try await Task.sleep(nanoseconds: 5_000_000)
        } while ContinuousClock.now < deadline
        return condition()
    }
    static func jwt(_ account: String = "student-B", seconds: TimeInterval = 3600) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["sno": account, "exp": Date().timeIntervalSince1970 + seconds])
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "e30.\(payload).fixture-signature"
    }
    static func bridge(timeout: TimeInterval = 10,
                       preparationDelay: UInt64 = 0) -> (EcardTokenBridge, OfflineEcardWebView) {
        EcardTokenBridge.clearCachedToken()
        #if ECARD_WEBKIT_DOUBLE
        let bridge = EcardTokenBridge(timeout: timeout)
        return (bridge, bridge.webView)
        #else
        let view = OfflineEcardWebView(frame: .zero, configuration: WKWebViewConfiguration())
        return (EcardTokenBridge(timeout: timeout, webView: view, nativeTokenProvider: { _, _ in
            // Controlled offline preparation delay exceeds the old 15 ms wait;
            // the real cookie restoration still runs before navigation starts.
            if preparationDelay > 0 { try await Task.sleep(nanoseconds: preparationDelay) }
            throw EcardSSOError.serviceUnavailable
        }), view)
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
        do { try await loginTests() }
        catch { check(false, "callback fixture readiness: \(error)") }
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

    static func loginTests() async throws {
        let (retryLogin, _) = bridge(timeout: 0.2)
        for attempt in 1...2 {
            do {
                _ = try await retryLogin.fetchToken(forAccount: "student-B")
                check(false, "attempt \(attempt) without a token must time out")
            } catch EcardError.authenticationTimeout(.starting) {
                check(true, "attempt \(attempt) finishes with its actual authentication stage timeout")
            } catch { check(false, "attempt \(attempt) timeout reason: \(error)") }
        }
        let (cancelLogin, cancelView) = bridge(preparationDelay: 50_000_000)
        let canceled = Task { try await cancelLogin.fetchToken(forAccount: "student-B") }
        defer { canceled.cancel() }
        _ = try await navigation(cancelView, count: 1, "cancelable request")
        canceled.cancel()
        let following = Task { try await cancelLogin.fetchToken(forAccount: "student-B") }
        defer { following.cancel() }
        let followingNavigation = try await navigation(cancelView, count: 2, "request following cancellation")
        let followingToken = jwt()
        deliver(cancelLogin, cancelView, navigation: followingNavigation, token: followingToken)
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
        defer { first.cancel() }
        let oldNavigation = try await navigation(view, count: 1, "original navigation")
        let second = Task { try await login.fetchToken(forAccount: "student-B") }
        defer { second.cancel() }
        let newNavigation = try await navigation(view, count: 2, "replacement navigation")
        login.webView(view, didFailProvisionalNavigation: oldNavigation, withError: URLError(.cannotFindHost))
        let fresh = jwt()
        deliver(login, view, navigation: newNavigation, token: fresh)
        check((try? await second.value) == fresh, "old navigation error cannot terminate the replacement request")
        _ = try? await first.value

        let (scriptLogin, scriptView) = bridge()
        let scriptFirst = Task { try await scriptLogin.fetchToken(forAccount: "student-B") }
        defer { scriptFirst.cancel() }
        let scriptNavigation = try await navigation(scriptView, count: 1, "storage fallback request")
        setURL(scriptView, URL(string: "https://ecard.ccsut.cn/charge-app/")!)
        scriptLogin.webView(scriptView, didFinish: scriptNavigation)
        try await waitUntil("trusted payment storage script") { scriptView.storageScriptCompletion != nil }
        let oldScript = scriptView.storageScriptCompletion
        check(oldScript != nil, "trusted payment page starts storage fallback")
        let scriptSecond = Task { try await scriptLogin.fetchToken(forAccount: "student-B") }
        defer { scriptSecond.cancel() }
        let replacementNavigation = try await navigation(scriptView, count: 2, "replacement storage request")
        oldScript?(jwt(seconds: 7200), nil)
        // Let the retired script's resumed consumer run while the replacement
        // is still pending. Immediate token delivery could hide a broken fence.
        _ = try await observesUnexpectedCallback { EcardTokenBridge.cachedToken(forAccount: "student-B") != nil }
        let replacement = jwt(seconds: 10800)
        deliver(scriptLogin, scriptView, navigation: replacementNavigation, token: replacement)
        check((try? await scriptSecond.value) == replacement, "old JavaScript result cannot finish a newer request")
        _ = try? await scriptFirst.value

        let (logoutLogin, logoutView) = bridge()
        let logoutTask = Task { try await logoutLogin.fetchToken(forAccount: "student-B") }
        defer { logoutTask.cancel() }
        let logoutNavigation = try await navigation(logoutView, count: 1, "logout request")
        EcardTokenBridge.clearCachedToken()
        deliver(logoutLogin, logoutView, navigation: logoutNavigation, token: jwt())
        check((try? await logoutTask.value) == nil && EcardTokenBridge.cachedToken(forAccount: "student-B") == nil,
              "logout invalidates in-flight token and prevents cache resurrection")

        let (deliveredLogin, deliveredView) = bridge()
        let deliveredTask = Task { try await deliveredLogin.fetchToken(forAccount: "student-B") }
        defer { deliveredTask.cancel() }
        let deliveredNavigation = try await navigation(deliveredView, count: 1, "resumed token request")
        deliver(deliveredLogin, deliveredView, navigation: deliveredNavigation, token: jwt())
        // The continuation is resumed, but its caller has not run yet.
        EcardTokenBridge.clearCachedToken()
        check((try? await deliveredTask.value) == nil,
              "logout also fences a token already resumed but not yet returned")

        for location in ["http://ecard.ccsut.cn/charge-app/", "https://ecard.ccsut.cn/plat/login",
                         "https://ecard.ccsut.cn/charge-app-other/"] {
            let (restricted, restrictedView) = bridge()
            let waiting = Task { try await restricted.fetchToken(forAccount: "student-B") }
            defer { waiting.cancel() }
            let restrictedNavigation = try await navigation(restrictedView, count: 1, "restricted page \(location)")
            setURL(restrictedView, URL(string: location)!)
            restricted.webView(restrictedView, didFinish: restrictedNavigation)
            let scriptStarted = try await observesUnexpectedCallback { restrictedView.storageScriptCompletion != nil }
            restrictedView.storageScriptCompletion?(jwt(), nil)
            waiting.cancel()
            _ = try? await waiting.value
            check(!scriptStarted, "storage fallback rejects \(location)")
        }
        let (expiry, expiryView) = bridge(timeout: 0.2)
        let expiryTask = Task { try await expiry.fetchToken(forAccount: "student-B") }
        defer { expiryTask.cancel() }
        let expiryNavigation = try await navigation(expiryView, count: 1, "expired token request")
        deliver(expiry, expiryView, navigation: expiryNavigation, token: jwt(seconds: -3600))
        let expiryResult = try? await expiryTask.value
        check(expiryResult == nil, "expired token is never returned")
    }
}
