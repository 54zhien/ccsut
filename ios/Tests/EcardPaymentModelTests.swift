import Foundation
import WebKit

@MainActor private final class PaymentInertWebView: WKWebView {
    override func load(_ request: URLRequest) -> WKNavigation? { nil }
}

private actor PaymentReadFixture {
    enum Failure { case http401, business401, http500 }
    let failure: Failure
    let alwaysReject: Bool
    let singleCampus: Bool
    let rejectSelectionReads: Bool
    var expired = true
    private var rejectedTokens: Set<String> = []
    var requests: [URLRequest] = []

    init(_ failure: Failure = .http401, alwaysReject: Bool = false,
         singleCampus: Bool = false, rejectSelectionReads: Bool = false) {
        self.failure = failure
        self.alwaysReject = alwaysReject
        self.singleCampus = singleCampus
        self.rejectSelectionReads = rejectSelectionReads
    }

    func setExpired(_ value: Bool) { expired = value }
    func reject(_ token: String) { rejectedTokens.insert(token) }

    func reply(_ request: URLRequest, token: String) -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url!.path
        let isRead = path.hasSuffix("singleFeeitem") || path.hasSuffix("getThirdData")
        let selection = path.hasSuffix("getThirdData") &&
            String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("level=0") != true
        let rejected = !isRead || (rejectSelectionReads && selection) ||
            (expired && (alwaysReject || token.hasSuffix("stale") || rejectedTokens.contains(token)))
        let status: Int
        let body: String
        if rejected {
            switch failure {
            case .http401: status = 401; body = "{}"
            case .business401: status = 200; body = #"{"code":401,"msg":"fixture expired"}"#
            case .http500: status = 500; body = "{}"
            }
        } else if path.hasSuffix("singleFeeitem") {
            status = 200
            body = #"{"code":200,"feeitem":{"feeitemid":"408","name":"示例电费","flag":"0000400100","maxmoney":"100"}}"#
        } else {
            status = 200
            body = singleCampus
                ? #"{"code":200,"map":{"data":[{"name":"示例北校区","value":"north"}]}}"#
                : #"{"code":200,"map":{"data":[{"name":"示例北校区","value":"north"},{"name":"示例南校区","value":"south"}]}}"#
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!)
    }
}

@main struct EcardPaymentModelTests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print("\(ok ? "PASS" : "FAIL") \(name)")
            if !ok { failures += 1 }
        }
        func token(_ suffix: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: [
                "sno": "fixture-payment-recovery", "exp": Date().addingTimeInterval(3600).timeIntervalSince1970
            ])
            let body = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return "e30.\(body).\(suffix)"
        }
        func bridge(_ token: String) -> EcardTokenBridge {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = PaymentInertWebView(frame: .zero, configuration: configuration)
            return EcardTokenBridge(webView: view, nativeTokenProvider: { _, _ in token })
        }
        func seed(_ token: String) async {
            EcardTokenBridge.clearCachedToken()
            _ = try! await bridge(token).fetchToken(forAccount: "fixture-payment-recovery")
        }
        func settle(_ model: EcardPaymentModel) async {
            for _ in 0..<600 {
                if !model.isStarting && model.loadingText == nil { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        for failure in [PaymentReadFixture.Failure.http401, .business401] {
            let fixture = PaymentReadFixture(failure)
            let stale = token("stale"), renewed = token("renewed")
            await seed(stale)
            var renewals = 0
            let model = EcardPaymentModel(clientFactory: { value, _, _ in
                EcardClient(token: value, transport: { await fixture.reply($0, token: value) })
            }, bridgeFactory: { renewals += 1; return bridge(renewed) })
            model.start(account: "fixture-payment-recovery")
            await settle(model)
            check(model.fee?.feeitemid == "408" && model.campuses.count == 2 && model.errorText == nil && renewals == 1,
                  "ecard \(failure) renews a rejected cached session in the background and completes initial reads")
            let sent = await fixture.requests
            check(sent.allSatisfy { $0.url!.path.hasSuffix("singleFeeitem") || $0.url!.path.hasSuffix("getThirdData") } && model.loginRequest == nil,
                  "automatic ecard recovery performs only reads and does not show a login sheet on success")
            model.stopQueries()
        }

        let denied = PaymentReadFixture(alwaysReject: true)
        await seed(token("stale"))
        var attempts = 0
        let deniedModel = EcardPaymentModel(clientFactory: { value, _, _ in
            EcardClient(token: value, transport: { await denied.reply($0, token: value) })
        }, bridgeFactory: { attempts += 1; return bridge(token("renewed")) })
        deniedModel.start(account: "fixture-payment-recovery")
        await settle(deniedModel)
        check(attempts == 1 && deniedModel.fee == nil && deniedModel.errorText != nil && !deniedModel.isStarting,
              "ecard stops with a retryable error after one unsuccessful automatic renewal")
        deniedModel.stopQueries()

        let offline = PaymentReadFixture(.http500)
        await seed(token("stale"))
        var offlineRenewals = 0
        let offlineModel = EcardPaymentModel(clientFactory: { value, _, _ in
            EcardClient(token: value, transport: { await offline.reply($0, token: value) })
        }, bridgeFactory: { offlineRenewals += 1; return bridge(token("renewed")) })
        offlineModel.start(account: "fixture-payment-recovery")
        await settle(offlineModel)
        check(offlineRenewals == 0 && offlineModel.errorText != nil, "ecard server errors do not trigger authentication")
        offlineModel.stopQueries()

        for singleCampus in [false, true] {
            let later = PaymentReadFixture(singleCampus: singleCampus)
            await later.setExpired(false)
            await seed(token("stale"))
            let firstRenewedToken = token("renewed-1"), secondRenewedToken = token("renewed-2")
            var laterRenewals = 0
            let laterModel = EcardPaymentModel(clientFactory: { value, _, _ in
                EcardClient(token: value, transport: { await later.reply($0, token: value) })
            }, bridgeFactory: {
                laterRenewals += 1
                return bridge(laterRenewals == 1 ? firstRenewedToken : secondRenewedToken)
            })
            laterModel.start(account: "fixture-payment-recovery")
            await settle(laterModel)
            await later.setExpired(true)
            laterModel.selectCampus("north")
            await settle(laterModel)
            check(laterRenewals == 1 && laterModel.fee != nil && laterModel.errorText == nil && laterModel.room == nil,
                  "ecard selection reads recover expiry and discard stale payment context (single campus: \(singleCampus))")
            await later.reject(firstRenewedToken)
            laterModel.selectCampus("north")
            await settle(laterModel)
            check(laterRenewals == 2 && laterModel.fee != nil && laterModel.errorText == nil,
                  "a later expiry can renew after the previous read recovery succeeded (single campus: \(singleCampus))")
            laterModel.stopQueries()
        }

        let cascade = PaymentReadFixture(singleCampus: true, rejectSelectionReads: true)
        await cascade.setExpired(false)
        await seed(token("stale"))
        var cascadeRenewals = 0
        let cascadeModel = EcardPaymentModel(clientFactory: { value, _, _ in
            EcardClient(token: value, transport: { await cascade.reply($0, token: value) })
        }, bridgeFactory: { cascadeRenewals += 1; return bridge(token("renewed")) })
        cascadeModel.start(account: "fixture-payment-recovery")
        await settle(cascadeModel)
        check(cascadeRenewals == 1 && cascadeModel.errorText != nil && !cascadeModel.isStarting && cascadeModel.loadingText == nil,
              "single-campus automatic selection cannot reset an unsuccessful recovery into a loop")
        cascadeModel.stopQueries()

        let write = PaymentReadFixture()
        await write.setExpired(false)
        await seed(token("stale"))
        var writeRenewals = 0
        let writeModel = EcardPaymentModel(clientFactory: { value, _, _ in
            EcardClient(token: value, transport: { await write.reply($0, token: value) })
        }, bridgeFactory: { writeRenewals += 1; return bridge(token("renewed")) })
        writeModel.start(account: "fixture-payment-recovery")
        await settle(writeModel)
        writeModel.room = "fixture-room"
        writeModel.detail = MeterDetail(context: MeterContext(houseID: "fixture-room"), show: [:], dataType: "IEC")
        writeModel.amountText = "10"
        writeModel.prepareConfirmation()
        if let confirmation = writeModel.confirmation {
            await writeModel.submit(confirmation)
            let sent = await write.requests
            check(writeRenewals == 0 && sent.filter { !$0.url!.path.hasSuffix("singleFeeitem") && !$0.url!.path.hasSuffix("getThirdData") }.count == 1,
                  "payment authentication failure never renews and resends a mutation")
        } else { check(false, "synthetic payment reaches explicit confirmation") }
        writeModel.stopQueries()
        EcardTokenBridge.clearCachedToken()
        if failures > 0 { exit(1) }
    }
}
