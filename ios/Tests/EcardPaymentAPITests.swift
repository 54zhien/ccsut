import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor PaymentServer {
    let paymentBody: String
    let finalStatus: Int
    private(set) var creations = 0
    private(set) var debits = 0
    private(set) var checks = 0
    init(paymentBody: String, finalStatus: Int = 0) {
        self.paymentBody = paymentBody; self.finalStatus = finalStatus
    }
    func counts() -> (Int, Int, Int) { (creations, debits, checks) }
    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url, url.host == "ecard.ccsut.cn" else { throw URLError(.badURL) }
        let form = URLComponents(string: "?" + String(decoding: request.httpBody ?? Data(), as: UTF8.self))?.queryItems ?? []
        let step = form.first { $0.name == "paystep" }?.value
        let body: String
        if step == "0" {
            creations += 1
            body = #"{"code":200,"success":true,"data":{"orderid":"fixture-order","payList":[{"id":"69","code":"CARDTSM","nopassword":"0"}]}}"#
        } else if step == "2" {
            guard form.first(where: { $0.name == "orderid" })?.value == "fixture-order" else { throw URLError(.badURL) }
            debits += 1; body = paymentBody
        } else if url.path == "/charge/pay/getpayinfo" {
            guard URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "orderid" })?.value == "fixture-order" else { throw URLError(.badURL) }
            checks += 1; body = "{\"code\":200,\"order\":{\"status\":\(finalStatus)}}"
        } else { throw URLError(.badURL) }
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!)
    }
}

@main struct EcardPaymentAPITests {
    static func main() async {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)"); if !value { failures += 1 }
        }
        for body in [#"{"code":500,"msg":"fixture upstream error","success":false}"#,
                     #"{"code":200,"msg":"fixture uncertain result","success":false}"#] {
            let server = PaymentServer(paymentBody: body)
            let client = EcardClient(token: "fixture-token", transport: { try await server.respond($0) })
            do {
                let outcome = try await client.rechargeElectricity(amount: 1, context: MeterContext())
                check(!outcome.isCompleted && outcome.orderID == "fixture-order", "uncertain business response retains original pending order")
            } catch { check(false, "uncertain business response must not discard order: \(error)") }
            let counts = await server.counts()
            check(counts.0 == 1 && counts.1 == 1 && counts.2 == 1,
                  "uncertain business response queries original order once without another debit")
        }
        let completed = PaymentServer(paymentBody: #"{"code":500,"msg":"fixture upstream error"}"#, finalStatus: 1)
        let client = EcardClient(token: "fixture-token", transport: { try await completed.respond($0) })
        do {
            let outcome = try await client.rechargeElectricity(amount: 1, context: MeterContext())
            check(outcome.isCompleted && outcome.orderID == "fixture-order", "reconciliation can prove a business-error payment completed")
        } catch { check(false, "business error must reconcile before deciding outcome") }
        enum CheckpointError: Error { case diskUnavailable }
        let blockedServer = PaymentServer(paymentBody: #"{"code":200,"success":true}"#)
        let blocked = EcardClient(token: "fixture-token", transport: { try await blockedServer.respond($0) })
        do {
            _ = try await blocked.rechargeElectricity(amount: 1, context: MeterContext(), beforePayment: { _ in
                throw CheckpointError.diskUnavailable
            })
            check(false, "checkpoint failure must stop payment")
        } catch is CheckpointError { check(true, "checkpoint failure is surfaced before debit") }
        catch { check(false, "checkpoint failure retains its storage error") }
        let blockedCounts = await blockedServer.counts()
        check(blockedCounts.0 == 1 && blockedCounts.1 == 0 && blockedCounts.2 == 0,
              "checkpoint failure sends no debit or reconciliation request")
        print("Payment API failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
