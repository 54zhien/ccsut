import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor Gate {
    private var opened = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var entered = false
    func wait() async {
        entered = true
        if opened { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func release() {
        opened = true
        let waiting = continuations; continuations = []
        waiting.forEach { $0.resume() }
    }
}

private actor ModelServer {
    let initialization: Gate?
    let payment: Gate?
    let reconciliation: Gate?
    let status: Int
    let paymentBody: String
    private(set) var debits = 0
    private(set) var creations = 0
    private(set) var meterReads = 0
    private var failFirstCheck: Bool
    init(initialization: Gate? = nil, payment: Gate? = nil, reconciliation: Gate? = nil,
         status: Int = 0, paymentBody: String = #"{"code":200,"success":true}"#, failFirstCheck: Bool = false) {
        self.initialization = initialization; self.payment = payment; self.reconciliation = reconciliation
        self.status = status; self.paymentBody = paymentBody
        self.failFirstCheck = failFirstCheck
    }
    func counts() -> (creations: Int, debits: Int) { (creations, debits) }
    func respond(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard let url = request.url, url.host == "ecard.ccsut.cn" else { throw URLError(.badURL) }
        let form = URLComponents(string: "?" + String(decoding: request.httpBody ?? Data(), as: UTF8.self))?.queryItems ?? []
        let body: String
        switch url.path {
        case "/charge/feeitem/singleFeeitem":
            await initialization?.wait()
            body = #"{"code":200,"feeitem":{"feeitemid":"408","name":"fixture fee","flag":"0000000100","maxmoney":"400"}}"#
        case "/charge/feeitem/getThirdData":
            if form.first(where: { $0.name == "level" })?.value == "3" {
                meterReads += 1
                body = #"{"code":200,"map":{"data":{"house_id":"fixture-room","house_no":"101","meter_id":"fixture-meter","meter_no":"001","customer_name":"fixture","sno":"fixture-A"},"showData":{"剩余金额":"42.00"}}}"#
            } else {
                body = #"{"code":200,"map":{"data":[{"name":"campus A","value":"A"},{"name":"campus B","value":"B"}]}}"#
            }
        case "/blade-pay/pay":
            if form.first(where: { $0.name == "paystep" })?.value == "0" {
                creations += 1
                body = #"{"code":200,"success":true,"data":{"orderid":"fixture-order","payList":[{"id":"69","code":"CARDTSM","nopassword":"0"}]}}"#
            } else {
                guard form.first(where: { $0.name == "orderid" })?.value == "fixture-order" else { throw URLError(.badURL) }
                debits += 1; await payment?.wait(); try Task.checkCancellation(); body = paymentBody
            }
        case "/charge/pay/getpayinfo":
            if failFirstCheck { failFirstCheck = false; throw EcardError.authenticationRequired }
            await reconciliation?.wait()
            body = "{\"code\":200,\"order\":{\"status\":\(status)}}"
        default: throw URLError(.badURL)
        }
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!)
    }
}

@MainActor private final class Epoch { var value: UInt64 = 1 }

@main struct EcardPaymentModelTests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)"); if !value { failures += 1 }
        }
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        let root = temporary.appendingPathComponent("payment-tests-" + UUID().uuidString).standardizedFileURL
        precondition(root.deletingLastPathComponent().path == temporary.path, "test cleanup must stay in its owned temporary directory")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var suites: [String] = []
        defer {
            for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
            try? FileManager.default.removeItem(at: root)
        }
        func defaults() -> UserDefaults {
            let name = "ccsut.payment.tests." + UUID().uuidString
            suites.append(name); return UserDefaults(suiteName: name)!
        }
        func store(_ name: String, defaults value: UserDefaults? = nil) -> EcardPendingReceiptStore {
            EcardPendingReceiptStore(directory: root.appendingPathComponent(name), defaults: value ?? defaults())
        }
        func receipt(_ id: String) -> EcardPaymentModel.Receipt {
            .init(status: .pending, room: "fixture room", amount: "1", orderID: id)
        }
        func make(_ server: ModelServer, _ journal: EcardPendingReceiptStore, _ epoch: Epoch,
                  login: Gate? = nil, observedAccounts: (@MainActor (String) -> Void)? = nil) -> EcardPaymentModel {
            let client = EcardClient(token: "fixture-token", transport: { try await server.respond($0) })
            return EcardPaymentModel(pendingStore: journal, currentGeneration: { epoch.value },
                cachedCredential: { account in
                    observedAccounts?(account)
                    return login == nil ? ("fixture-token", true) : nil
                }, clientFactory: { _, _, _ in client }, fetchLoginToken: { _, _ in
                    await login?.wait(); return "fixture-token"
                })
        }
        func waitUntil(_ predicate: @MainActor () async -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if await predicate() { return true }
                try? await Task.sleep(for: .milliseconds(2))
            }
            return false
        }
        func ready(_ model: EcardPaymentModel, account: String = "fixture-A") async {
            model.start(account: account)
            check(await waitUntil { !model.isStarting }, "initialization settles without school traffic")
        }
        func confirm(_ model: EcardPaymentModel) -> EcardPaymentModel.Confirmation? {
            model.room = "fixture-room"; model.amountText = "10"
            model.detail = MeterDetail(context: MeterContext(houseID: "fixture-room"), show: ["房间信息": "fixture room"], dataType: nil)
            model.prepareConfirmation(); return model.confirmation
        }

        do {
            let server = ModelServer(), journal = store("room-mismatch"), epoch = Epoch()
            let model = make(server, journal, epoch)
            await ready(model)
            _ = confirm(model)
            model.detail = MeterDetail(context: MeterContext(houseID: "another-room"), show: [:], dataType: nil)
            model.prepareConfirmation()
            if let approved = model.confirmation { await model.submit(approved) }
            let counts = await server.counts()
            check(counts.creations == 0 && counts.debits == 0 && model.errorText != nil,
                  "mismatched meter room is rejected before order creation or debit")
            model.stopQueries()
        }

        do {
            let server = ModelServer(), journal = store("ten-yuan-minimum"), epoch = Epoch()
            let model = make(server, journal, epoch)
            await ready(model)
            _ = confirm(model)
            model.confirmation = nil
            for invalid in ["0", "1", "9", "9.99"] {
                model.amountText = invalid
                model.prepareConfirmation()
                check(!model.canPay && model.confirmation == nil && model.amountHint != nil,
                      "sub-ten amount \(invalid) cannot reach payment confirmation")
                model.confirmation = nil
            }
            model.amountText = "10"
            model.prepareConfirmation()
            check(model.canPay && model.confirmation?.amount == 10, "ten yuan is a valid minimum confirmation")
            let counts = await server.counts()
            check(counts.creations == 0 && counts.debits == 0, "minimum validation never creates an order or sends payment")
            model.stopQueries()
        }

        do {
            let server = ModelServer(), journal = store("pull-refresh"), epoch = Epoch()
            let model = make(server, journal, epoch)
            await ready(model)
            model.campus = "A"; model.building = "B"; model.room = "fixture-room"; model.amountText = "12"
            await model.refreshMeter(account: "fixture-A")
            let reads = await server.meterReads
            check(model.detail?.remainingAmount == 42 && model.loadingText == nil && reads == 1,
                  "pull refresh awaits the selected meter read and publishes the new balance")
            check(model.campus == "A" && model.building == "B" && model.room == "fixture-room" && model.amountText == "12",
                  "pull refresh preserves selected room and entered amount")
            model.receipt = receipt("original-refresh-order")
            try journal.save(model.receipt!, account: "fixture-A")
            await model.refreshMeter(account: "fixture-A")
            let counts = await server.counts()
            check(try journal.load(account: "fixture-A")?.orderID == "original-refresh-order" &&
                  model.receipt?.orderID == "original-refresh-order" && counts.creations == 0 && counts.debits == 0,
                  "pull refresh preserves the original pending receipt and never sends payment")
            model.stopQueries()
        }

        // Recovery failures must be distinguishable and remain blocking even
        // when the original unreadable file subsequently disappears.
        do {
            var descriptions: Set<String> = []
            for kind in ["read", "version", "corrupt"] {
                let journal = store("recovery-" + kind)
                try journal.save(receipt("original-order"), account: "fixture-A")
                let folder = root.appendingPathComponent("recovery-" + kind)
                let file = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first!
                if kind == "read" {
                    try FileManager.default.removeItem(at: file)
                    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
                } else {
                    try Data((kind == "version" ? #"{"version":99,"futurePayload":{}}"# : "broken-json").utf8).write(to: file)
                }
                do { _ = try journal.load(account: "fixture-A"); check(false, "invalid recovery record must throw") }
                catch { descriptions.insert(error.localizedDescription) }
                var credentialReads = 0
                let server = ModelServer(), model = make(server, journal, Epoch(), observedAccounts: { _ in credentialReads += 1 })
                await ready(model)
                check(credentialReads == 0 && model.fee == nil, "blocked \(kind) recovery stops before authentication")
                try FileManager.default.removeItem(at: file)
                let restarted = store("recovery-" + kind)
                do { _ = try restarted.load(account: "fixture-A"); check(false, "missing \(kind) journal remains blocked after restart") }
                catch { descriptions.insert(error.localizedDescription) }
                check(try restarted.load(account: "fixture-B") == nil, "recovery block is isolated to its account")
                model.start(account: "fixture-A", force: true)
                _ = await waitUntil { !model.isStarting }
                check(confirm(model) == nil && !model.canPay, "force reload cannot bypass missing \(kind) journal")
                let counts = await server.counts()
                check(counts.creations == 0 && counts.debits == 0, "blocked recovery has no payment requests")
                model.stopQueries()
            }
            check(descriptions.count == 4, "read failure, unsupported version, corruption and missing record have distinct explanations")
        }

        do {
            let journal = store("retry"), epoch = Epoch(), server = ModelServer(status: 1)
            try journal.save(receipt("original-order"), account: "fixture-A")
            let file = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("retry"), includingPropertiesForKeys: nil).first!
            let original = try Data(contentsOf: file)
            try Data("broken-json".utf8).write(to: file)
            let model = make(server, journal, epoch); await ready(model)
            check(model.recoveryIssue == .corrupted, "corrupt payload has typed recovery state")
            for _ in 0..<3 { model.retryRecovery(account: "fixture-A") }
            check(model.recoveryIssue == .corrupted && !model.canPay && model.receipt == nil, "repeated failed retries stay blocked")
            check(try Data(contentsOf: file) == Data("broken-json".utf8), "retries preserve original corrupt bytes")
            try original.write(to: file)
            model.retryRecovery(account: "fixture-B")
            check(model.recoveryIssue == .corrupted && model.receipt == nil, "retry rejects a different account")
            epoch.value += 1
            model.retryRecovery(account: "fixture-A")
            check(model.recoveryIssue == .corrupted && model.receipt == nil, "retry rejects an invalidated session")
            model.start(account: "fixture-A", force: true)
            _ = await waitUntil { !model.isStarting }
            check(model.receipt?.orderID == "original-order" && model.recoveryIssue == nil && !model.canPay,
                  "restored original journal returns to pending receipt without enabling payment")
            await model.checkOrder()
            let completed = try journal.load(account: "fixture-A")
            check(model.receipt?.status == .completed && completed == nil,
                  "recovered original can complete through existing server check")
            let counts = await server.counts()
            check(counts.creations == 0 && counts.debits == 0, "recovery and original-order check never create or debit")
            model.stopQueries()
        }
        do {
            let journal = store("retry-read"), server = ModelServer(), epoch = Epoch()
            try journal.save(receipt("read-order"), account: "fixture-A")
            let file = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("retry-read"), includingPropertiesForKeys: nil).first!
            let original = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            let model = make(server, journal, epoch); await ready(model)
            check(model.recoveryIssue == .readUnavailable, "read error is distinct from malformed content")
            try FileManager.default.removeItem(at: file)
            try original.write(to: file)
            model.retryRecovery(account: "fixture-A")
            _ = await waitUntil { !model.isStarting }
            check(model.receipt?.orderID == "read-order" && model.recoveryIssue == nil && !model.canPay,
                  "explicit retry restores the original pending receipt after transient read failure")
            model.start(account: "fixture-B")
            _ = await waitUntil { !model.isStarting }
            model.retryRecovery(account: "fixture-A")
            check(model.receipt == nil && model.recoveryIssue == nil && confirm(model) != nil,
                  "account switch removes old recovery state and stale retry cannot restore it")
            model.stopQueries()
        }

        do {
            let journal = store("known-pending-missing"), epoch = Epoch(), server = ModelServer()
            try journal.save(receipt("known-order"), account: "fixture-A")
            let model = make(server, journal, epoch); await ready(model)
            let file = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("known-pending-missing"), includingPropertiesForKeys: nil).first!
            try FileManager.default.removeItem(at: file)
            epoch.value += 1
            model.start(account: "fixture-A", force: true)
            _ = await waitUntil { !model.isStarting }
            check(model.recoveryIssue == .missingRecord && confirm(model) == nil && !model.canPay,
                  "known pending cannot disappear across a replacement session")
            let restarted = store("known-pending-missing")
            do { _ = try restarted.load(account: "fixture-A"); check(false, "detected loss of known pending remains blocked after restart") }
            catch { check(error as? EcardReceiptRecoveryError == .missingRecord, "detected loss of known pending remains blocked after restart") }
            model.stopQueries()
        }

        do {
            let journal = store("marker-write-failure")
            try journal.save(receipt("original-order"), account: "fixture-A")
            let file = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("marker-write-failure"), includingPropertiesForKeys: nil).first!
            let original = Data("broken-json".utf8)
            try original.write(to: file)
            // A directory at the marker destination rejects its atomic write.
            let marker = file.appendingPathExtension("recovery-block")
            try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
            let model = make(ModelServer(), journal, Epoch()); await ready(model)
            model.retryRecovery(account: "fixture-A")
            check(model.recoveryIssue == .corrupted && !model.canPay, "failed block-marker write cannot unlock the current process")
            check(try Data(contentsOf: file) == original, "failed block-marker write preserves damaged source")
            try FileManager.default.removeItem(at: file)
            model.retryRecovery(account: "fixture-A")
            check(model.recoveryIssue == .missingRecord && !model.canPay, "in-memory block survives disappearance when marker write fails")
            model.stopQueries()
        }

        // Restart while the server has received the debit, before its response.
        do {
            let gate = Gate(), journal = store("restart"), epoch = Epoch()
            let server = ModelServer(payment: gate)
            let model = make(server, journal, epoch); await ready(model)
            guard let confirmation = confirm(model) else { fatalError("fixture must be payable") }
            let task = Task { await model.submit(confirmation) }
            check(await waitUntil { await gate.entered }, "debit fixture reached its suspended response")
            check(try journal.load(account: "fixture-A")?.orderID == "fixture-order", "original order is recorded before debit responds")
            let restarted = make(ModelServer(), journal, epoch); await ready(restarted)
            check(restarted.receipt?.orderID == "fixture-order", "recreated model recovers the in-flight original order")
            check(confirm(restarted) == nil && !restarted.canPay, "recovered pending order prevents another confirmation")
            await gate.release(); await task.value
            let counts = await server.counts()
            check(counts.creations == 1 && counts.debits == 1, "pending recovery never resubmits the debit")
            restarted.stopQueries(); model.stopQueries()
        }
        // A new store with unrelated defaults must recover the durable file.
        do {
            let first = store("durable"), second = store("durable")
            try first.save(receipt("durable-order"), account: "fixture-A")
            check(try second.load(account: "fixture-A")?.orderID == "durable-order", "pending survives a new store and independent defaults")
            check(try second.load(account: "fixture-B") == nil, "accounts cannot recover each other's pending orders")
            try first.clear(account: "fixture-A", orderID: "different-order")
            check(try first.load(account: "fixture-A")?.orderID == "durable-order", "stale completion cannot clear a different order")
            do { try first.save(receipt("replacement-order"), account: "fixture-A"); check(false, "unresolved original cannot be overwritten") }
            catch { check(true, "unresolved original cannot be overwritten") }
        }
        // Legacy receipts must migrate durably; corrupt records remain blocking.
        do {
            let legacy = defaults()
            legacy.set(try JSONEncoder().encode(receipt("legacy-order")), forKey: "ecard.pending.fixture-A")
            let old = store("legacy", defaults: legacy)
            _ = try old.load(account: "fixture-A")
            check(try store("legacy").load(account: "fixture-A")?.orderID == "legacy-order", "legacy pending migrates before relying on a new defaults store")
            let corruptDefaults = defaults()
            corruptDefaults.set(Data("invalid-json".utf8), forKey: "ecard.pending.fixture-A")
            let corruptStore = store("corrupt", defaults: corruptDefaults)
            let model = make(ModelServer(), corruptStore, Epoch()); await ready(model)
            check(confirm(model) == nil && !model.canPay && model.errorText != nil, "unreadable pending receipt blocks payment and explains recovery failure")
            check(corruptDefaults.data(forKey: "ecard.pending.fixture-A") != nil, "unreadable legacy data is preserved")
            model.stopQueries()
        }
        do {
            let blocked = root.appendingPathComponent("not-a-directory")
            try Data("fixture".utf8).write(to: blocked)
            let journal = EcardPendingReceiptStore(directory: blocked, defaults: defaults())
            let server = ModelServer(), model = make(server, journal, Epoch()); await ready(model)
            if let confirmation = confirm(model) { await model.submit(confirmation) }
            let counts = await server.counts()
            check(counts.debits == 0, "unwritable recovery journal prevents debit")
            check(model.errorText != nil || model.receipt?.status == .failed, "journal failure is visible")
            model.stopQueries()
        }
        // Both startup awaits must settle on generation invalidation.
        do {
            let legacy = defaults(), journal = store("migration-interrupted", defaults: legacy)
            try journal.save(receipt("original-order"), account: "fixture-A")
            // Simulate termination after writing the migrated file but before
            // removing the legacy defaults copy.
            legacy.set(try JSONEncoder().encode(receipt("original-order")), forKey: "ecard.pending.fixture-A")
            try journal.clear(account: "fixture-A", orderID: "original-order")
            check(try journal.load(account: "fixture-A") == nil, "completed migrated order cannot resurrect from leftover defaults")
            // Model the older defaults snapshot surviving an asynchronous flush
            // when the process terminates immediately after completing payment.
            legacy.set(try JSONEncoder().encode(receipt("original-order")), forKey: "ecard.pending.fixture-A")
            check(try journal.load(account: "fixture-A") == nil,
                  "durable cleared marker defeats an older defaults snapshot after restart")
        }
        do {
            let journal = store("corrupt-file")
            try journal.save(receipt("original-order"), account: "fixture-A")
            let folder = root.appendingPathComponent("corrupt-file")
            let file = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first!
            try Data("invalid-json".utf8).write(to: file)
            let model = make(ModelServer(), journal, Epoch()); await ready(model)
            check(confirm(model) == nil && !model.canPay && model.errorText != nil, "unreadable durable journal blocks a new payment")
            check(try Data(contentsOf: file) == Data("invalid-json".utf8), "unreadable durable journal is not overwritten")
            model.stopQueries()
        }
        for backgroundLogin in [false, true] {
            let gate = Gate(), epoch = Epoch(), journal = store("epoch-\(backgroundLogin)")
            let server = ModelServer(initialization: backgroundLogin ? nil : gate)
            let model = make(server, journal, epoch, login: backgroundLogin ? gate : nil)
            model.start(account: "fixture-A")
            check(await waitUntil { await gate.entered }, "startup fixture suspended at its external boundary")
            epoch.value += 1; await gate.release()
            _ = await waitUntil { !model.isStarting || model.errorText != nil }
            check(!model.isStarting && model.errorText != nil && model.fee == nil,
                  "invalidated \(backgroundLogin ? "login" : "initialization") ends waiting with recoverable state")
            model.start(account: "fixture-B", force: true)
            check(await waitUntil { model.fee != nil && !model.isStarting }, "replacement startup can recover after invalidation")
            model.stopQueries()
        }
        do {
            let gate = Gate(), epoch = Epoch()
            var accounts: [String] = []
            let model = make(ModelServer(initialization: gate), store("replacement"), epoch,
                             observedAccounts: { accounts.append($0) })
            model.start(account: "fixture-A")
            check(await waitUntil { await gate.entered }, "old startup reaches delayed initialization")
            epoch.value += 1; model.start(account: "fixture-B")
            await gate.release()
            check(await waitUntil { model.fee != nil && !model.isStarting }, "new account supersedes an in-flight startup")
            check(accounts.contains("fixture-B"), "replacement account actually obtains its own credentials")
            model.stopQueries()
        }
        // A delayed check of A must never complete/remove B's pending order.
        do {
            let gate = Gate(), journal = store("late-check"), epoch = Epoch()
            try journal.save(receipt("order-A"), account: "fixture-A")
            try journal.save(receipt("order-B"), account: "fixture-B")
            let model = make(ModelServer(reconciliation: gate, status: 1), journal, epoch)
            await ready(model)
            let checking = Task { await model.checkOrder() }
            check(await waitUntil { await gate.entered }, "old account check reaches delayed response")
            epoch.value += 1; model.start(account: "fixture-B")
            _ = await waitUntil { !model.isStarting }
            await gate.release(); await checking.value
            check(model.receipt?.orderID == "order-B" && model.receipt?.status == .pending,
                  "late old-account status cannot complete new-account receipt")
            check(try journal.load(account: "fixture-B")?.orderID == "order-B", "late old-account status cannot erase new-account journal")
            model.stopQueries()
        }
        do {
            let journal = store("check-auth"), epoch = Epoch()
            try journal.save(receipt("order-A"), account: "fixture-A")
            let server = ModelServer(status: 1, failFirstCheck: true)
            let model = make(server, journal, epoch); await ready(model)
            await model.checkOrder()
            check(model.receipt?.status == .pending && model.receipt?.orderID == "order-A", "expired check authentication retains the pending receipt")
            await model.checkOrder() // Rebuild the authentication/client boundary.
            _ = await waitUntil { !model.isStarting }
            await model.checkOrder()
            let recovered = try journal.load(account: "fixture-A")
            check(model.receipt?.status == .completed && recovered == nil,
                  "authenticated original-order check completes and clears recovery state")
            let counts = await server.counts()
            check(counts.creations == 0 && counts.debits == 0, "check recovery never creates or pays another order")
            model.stopQueries()
        }
        do {
            let gate = Gate(), journal = store("close-login"), epoch = Epoch()
            try journal.save(receipt("order-A"), account: "fixture-A")
            let model = make(ModelServer(), journal, epoch, login: gate)
            model.start(account: "fixture-A")
            _ = await waitUntil { await gate.entered }
            model.openLogin(); model.loginRequest = nil; model.loginDismissed()
            await gate.release()
            try? await Task.sleep(for: .milliseconds(20))
            check(!model.isStarting && model.fee == nil && model.errorText != nil, "closed login cannot restart loading from a late token")
            let recovered = try journal.load(account: "fixture-A")
            check(model.receipt?.orderID == "order-A" && recovered?.orderID == "order-A",
                  "closing recovery login preserves the original pending order")
            model.stopQueries()
        }
        do {
            let gate = Gate(), journal = store("late-payment"), epoch = Epoch()
            let server = ModelServer(payment: gate, status: 1)
            let model = make(server, journal, epoch); await ready(model)
            guard let confirmation = confirm(model) else { fatalError("fixture must be payable") }
            let paying = Task { await model.submit(confirmation) }
            _ = await waitUntil { await gate.entered }
            try journal.save(receipt("order-B"), account: "fixture-B")
            epoch.value += 1; model.start(account: "fixture-B")
            _ = await waitUntil { !model.isStarting }
            await gate.release(); await paying.value
            check(model.receipt?.orderID == "order-B" && model.receipt?.status == .pending && !model.isSubmitting,
                  "late payment completion cannot replace a new account's pending receipt")
            check(try journal.load(account: "fixture-B")?.orderID == "order-B", "late payment completion clears only its captured account/order")
            model.stopQueries()
        }
        do {
            let oldLogin = Gate(), newLogin = Gate(), epoch = Epoch()
            let server = ModelServer()
            let client = EcardClient(token: "fixture-token", transport: { try await server.respond($0) })
            let model = EcardPaymentModel(pendingStore: store("late-dismiss"), currentGeneration: { epoch.value },
                cachedCredential: { _ in nil }, clientFactory: { _, _, _ in client },
                fetchLoginToken: { _, account in
                    if account == "fixture-A" { await oldLogin.wait() } else { await newLogin.wait() }
                    return "fixture-token"
                })
            model.start(account: "fixture-A")
            _ = await waitUntil { await oldLogin.entered }
            model.openLogin()
            check(model.loginRequest != nil, "old account owns a presented login request")
            epoch.value += 1; model.start(account: "fixture-B")
            _ = await waitUntil { await newLogin.entered }
            model.loginDismissed() // A's delayed SwiftUI callback, after B started.
            check(model.isStarting && model.errorText == nil, "old sheet dismissal cannot cancel replacement login")
            await oldLogin.release(); await newLogin.release()
            check(await waitUntil { model.fee != nil && !model.isStarting }, "replacement login completes after old sheet dismissal")
            model.stopQueries()
        }
        do {
            let gate = Gate(), journal = store("canceled-payment"), epoch = Epoch()
            let model = make(ModelServer(payment: gate), journal, epoch); await ready(model)
            guard let confirmation = confirm(model) else { fatalError("fixture must be payable") }
            let paying = Task { await model.submit(confirmation) }
            _ = await waitUntil { await gate.entered }
            paying.cancel(); await gate.release(); await paying.value
            check(model.receipt?.status == .pending && model.receipt?.orderID == "fixture-order", "cancellation after dispatch retains pending original order")
            check(try journal.load(account: "fixture-A")?.orderID == "fixture-order", "cancellation after dispatch keeps durable recovery state")
            model.stopQueries()
        }
        print("Payment model failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
