import Foundation
import Observation
#if canImport(WebKit)
import WebKit
#else
import FoundationNetworking
#endif

@Observable @MainActor
final class EcardPaymentModel {
    struct LoginRequest: Identifiable {
        let id = UUID()
        let bridge: EcardTokenBridge
        let account: String
    }
    struct Confirmation: Identifiable {
        let id = UUID()
        let amount: Decimal
        let room: String
        let roomValue: String
        let context: MeterContext
    }
    struct Receipt: Codable {
        enum Status: String, Codable { case completed, pending, failed }
        var status: Status
        let room: String
        let amount: String
        let orderID: String?
        var message: String?
    }

    var fee: FeeItem?
    var campuses: [ThirdOption] = []
    var buildings: [ThirdOption] = []
    var rooms: [ThirdOption] = []
    var campus: String?
    var building: String?
    var room: String?
    var detail: MeterDetail?
    var amountText = ""
    var errorText: String?
    var loadingText: String?
    var isStarting = false
    var isSubmitting = false
    var isChecking = false
    var canOpenLogin = false
    var loginRequest: LoginRequest?
    var confirmation: Confirmation?
    var receipt: Receipt?

    @ObservationIgnored private var client: EcardClient?
    @ObservationIgnored private var account: String?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var initialTask: Task<Void, Never>?
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var loginPromptTask: Task<Void, Never>?
    @ObservationIgnored private var pendingLogin: LoginRequest?
    @ObservationIgnored private var boundGeneration: UInt64?
    @ObservationIgnored private var submissionID: UUID?
    @ObservationIgnored private var checkingID: UUID?
    private var recoveryError: String?
    typealias CachedCredential = (token: String, nativeCookies: Bool)
    @ObservationIgnored private let pendingStore: EcardPendingReceiptStore
    @ObservationIgnored private let currentGeneration: @MainActor () -> UInt64
    @ObservationIgnored private let cachedCredential: @MainActor (String) -> CachedCredential?
    @ObservationIgnored private let clientFactory: @MainActor (String, UInt64, WKWebsiteDataStore?) -> EcardClient
    @ObservationIgnored private let fetchLoginToken: @MainActor (EcardTokenBridge, String) async throws -> String

    init(pendingStore: EcardPendingReceiptStore? = nil,
         currentGeneration: @escaping @MainActor () -> UInt64 = { CookieJar.generation },
         cachedCredential: (@MainActor (String) -> CachedCredential?)? = nil,
         clientFactory: (@MainActor (String, UInt64, WKWebsiteDataStore?) -> EcardClient)? = nil,
         fetchLoginToken: (@MainActor (EcardTokenBridge, String) async throws -> String)? = nil) {
        self.pendingStore = pendingStore ?? EcardPendingReceiptStore()
        self.currentGeneration = currentGeneration
        self.cachedCredential = cachedCredential ?? { account in
            EcardTokenBridge.cachedToken(forAccount: account).map {
                ($0, EcardTokenBridge.cachedTokenUsesNativeCookies(forAccount: account))
            }
        }
        self.clientFactory = clientFactory ?? Self.authenticatedClient
        self.fetchLoginToken = fetchLoginToken ?? { try await $0.fetchToken(forAccount: $1) }
    }

    var amount: Decimal? {
        let value = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ".").replacingOccurrences(of: ",", with: ".")
        guard !value.isEmpty, value.range(of: #"^\d+(\.\d{0,2})?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
    var amountHint: String? {
        guard !amountText.isEmpty else { return nil }
        guard let amount else { return "请输入金额，最多保留两位小数" }
        guard amount > 0 else { return "缴费金额需大于 0" }
        guard let maximum = fee?.maxAmount, maximum > 0 else { return "暂未获取到缴费限额，请重新加载" }
        if amount > maximum { return "单笔最多缴费 \(maximum.ecardAmountText) 元" }
        return nil
    }
    var canPay: Bool {
        client != nil && detail != nil && room != nil && amount != nil && !amountText.isEmpty && amountHint == nil &&
        loadingText == nil && !isStarting && !isSubmitting && !isChecking && receipt == nil &&
        recoveryError == nil && boundGeneration == currentGeneration()
    }
    var quickAmounts: [Decimal] { fee?.quickAmounts.filter { $0 > 0 && $0 <= (fee?.maxAmount ?? 0) } ?? [] }

    func start(account: String?, force: Bool = false) {
        guard let account, !account.isEmpty else {
            errorText = "暂未获取到学号，请稍后重新加载"
            return
        }
        let generation = currentGeneration()
        let sameSession = self.account == account && boundGeneration == generation
        guard !isSubmitting || !sameSession else { return }
        guard !isStarting || !sameSession || force else { return }
        if sameSession, fee != nil, !force {
            if let campus, buildings.isEmpty { selectCampus(campus) }
            else if let room, detail == nil { selectRoom(room) }
            return
        }
        stopQueries()
        submissionID = nil; isSubmitting = false
        checkingID = nil; isChecking = false
        EcardTokenBridge.cancelPreparation()
        self.account = account
        boundGeneration = generation
        recoveryError = nil; receipt = nil
        do { receipt = try pendingStore.load(account: account) }
        catch { recoveryError = error.localizedDescription }
        campus = nil; building = nil; room = nil; detail = nil
        campuses = []; buildings = []; rooms = []; fee = nil
        client = nil
        amountText = ""; errorText = recoveryError; isStarting = true
        if let credential = cachedCredential(account) {
            acceptToken(credential.token, nativeCookies: credential.nativeCookies)
        } else {
            beginBackgroundLogin(account: account)
        }
    }

    private func beginBackgroundLogin(account: String) {
        let current = revision
        let generation = currentGeneration()
        let request = LoginRequest(bridge: EcardTokenBridge(dataStore: WebStore.dataStore), account: account)
        let requestID = request.id
        pendingLogin = request
        request.bridge.onNeedsInteraction = { [weak self] in
            guard let self, self.startupIsCurrent(current, generation: generation),
                  self.pendingLogin?.id == requestID else { return }
            self.openLogin()
        }
        loginPromptTask = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard startupIsCurrent(current, generation: generation), pendingLogin?.id == request.id else { return }
            canOpenLogin = true
        }
        loginTask = Task {
            defer {
                if current == revision {
                    loginTask = nil
                    loginPromptTask?.cancel(); loginPromptTask = nil
                    pendingLogin = nil; canOpenLogin = false
                }
                request.bridge.onNeedsInteraction = nil
            }
            do {
                let token = try await fetchLoginToken(request.bridge, account)
                guard startupIsCurrent(current, generation: generation) else { return }
                acceptToken(token, store: request.bridge.webView.configuration.websiteDataStore,
                            nativeCookies: request.bridge.usesNativeCookies)
            } catch {
                if startupIsCurrent(current, generation: generation) { loginFailed(error) }
            }
        }
    }

    func openLogin() {
        guard isStarting, let pendingLogin else { return }
        loginRequest = pendingLogin
    }

    private func acceptToken(_ token: String, store: WKWebsiteDataStore? = nil, nativeCookies: Bool = false) {
        let current = revision
        let generation = currentGeneration()
        let store = store ?? WebStore.dataStore
        initialTask = Task {
            defer { if current == revision { isStarting = false } }
            do {
                // The token and gateway session are both required. WebKit's
                // cookie store is separate from URLSession's default store.
                var loaded: (FeeItem, [ThirdOption])?
                for attempt in 0..<4 {
                    if !nativeCookies {
                        let cookies = try await store.httpCookieStore.cookieSnapshot()
                        guard startupIsCurrent(current, generation: generation) else { return }
                        CookieJar.upsert(cookies, generation: generation)
                    }
                    guard startupIsCurrent(current, generation: generation) else { return }
                    let client = clientFactory(token, generation, nativeCookies ? nil : store)
                    self.client = client
                    loginRequest = nil
                    do {
                        async let item = client.feeItem()
                        async let options = client.campuses()
                        loaded = try await (item, options)
                        break
                    } catch EcardError.authenticationRequired where attempt < 3 {
                        // WebKit may publish the final gateway cookies after
                        // the token redirect. Re-read them with a bounded wait.
                        // Only these initial READS are retried, never a payment.
                        try await Task.sleep(for: .milliseconds(300))
                    }
                }
                guard let (loadedFee, loadedCampuses) = loaded else { throw EcardError.noToken }
                guard startupIsCurrent(current, generation: generation) else { return }
                fee = loadedFee; campuses = loadedCampuses
                isStarting = false
                if loadedCampuses.count == 1 { selectCampus(loadedCampuses[0].value) }
                else if loadedCampuses.isEmpty { errorText = "暂无可选校区，请稍后重新加载" }
            } catch {
                if startupIsCurrent(current, generation: generation) {
                    handleLoadError(error)
                    loginRequest = nil
                }
            }
        }
    }

    /// Only the current startup may end its waiting state. A superseded task
    /// must leave the replacement task alone, including its error/progress.
    private func startupIsCurrent(_ current: Int, generation: UInt64) -> Bool {
        guard current == revision else { return false }
        guard currentGeneration() == generation, !Task.isCancelled else {
            stopQueries()
            client = nil; fee = nil; campuses = []; buildings = []; rooms = []
            campus = nil; building = nil; room = nil; detail = nil; receipt = nil
            errorText = recoveryError ?? EcardError.canceled.localizedDescription
            return false
        }
        return true
    }

    private static func authenticatedClient(token: String, generation: UInt64, store: WKWebsiteDataStore?) -> EcardClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        return EcardClient(token: token, transport: { original in
            try Task.checkCancellation()
            guard let url = original.url, url.scheme == "https", url.host == "ecard.ccsut.cn",
                  url.port == nil || url.port == 443 else { throw EcardError.noToken }
            var request = original
            request.httpShouldHandleCookies = false
            request.setValue(try CookieJar.header(for: url, expectedGeneration: generation), forHTTPHeaderField: "Cookie")
            request.setValue(UserAgent.mobile, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard CookieJar.generation == generation else { throw EcardError.canceled }
            if let http = response as? HTTPURLResponse, let fields = http.allHeaderFields as? [String: String] {
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).filter(CookieJar.isSchoolCookie)
                CookieJar.upsert(cookies, generation: generation)
                // Keep the next WebKit handoff from restoring a stale cookie
                // after the native request has received a rotated session.
                for cookie in cookies {
                    guard let store else { continue }
                    guard CookieJar.generation == generation else { throw EcardError.canceled }
                    do { try await store.httpCookieStore.set(cookie) }
                    catch {
                        guard CookieJar.generation == generation, !Task.isCancelled else { throw EcardError.canceled }
                        throw EcardError.sessionSynchronization
                    }
                }
            }
            guard CookieJar.generation == generation else { throw EcardError.canceled }
            return (data, response)
        })
    }

    private func handleLoadError(_ error: Error) {
        errorText = error.localizedDescription
        if let error = error as? EcardError {
            switch error {
            case .authenticationRequired, .sessionSynchronization, .noToken, .business(401, _):
                EcardTokenBridge.clearCachedToken()
                client = nil
                fee = nil
            default: break
            }
        }
    }

    private func loginFailed(_ error: Error) {
        errorText = error.localizedDescription
        loginRequest = nil; isStarting = false
    }
    func loginDismissed() {
        // SwiftUI clears the sheet item before calling onDismiss.
        if isStarting, client == nil {
            // Cookie handoff is asynchronous too. Closing the sheet in that
            // window must not let its pending snapshot restart data loading.
            stopQueries()
            loginRequest = nil
            errorText = EcardError.canceled.localizedDescription
        }
    }
    func stopQueries() {
        revision &+= 1
        queryTask?.cancel(); initialTask?.cancel()
        loginTask?.cancel(); loginTask = nil
        loginPromptTask?.cancel(); loginPromptTask = nil
        pendingLogin?.bridge.onNeedsInteraction = nil
        pendingLogin = nil; loginRequest = nil; canOpenLogin = false
        loadingText = nil; isStarting = false
    }

    func selectCampus(_ value: String?) {
        campus = value; building = nil; room = nil; detail = nil
        buildings = []; rooms = []
        query("加载楼栋…") { client in
            guard let value else { return }
            let options = try await client.buildings(campus: value)
            try Task.checkCancellation()
            self.buildings = options
        }
    }
    func selectBuilding(_ value: String?) {
        building = value; room = nil; detail = nil; rooms = []
        query("加载房间…") { client in
            guard let campus = self.campus, let value else { return }
            let options = try await client.rooms(campus: campus, building: value)
            try Task.checkCancellation()
            self.rooms = options
        }
    }
    func selectRoom(_ value: String?) {
        room = value; detail = nil
        query("查询电表…") { client in
            guard let campus = self.campus, let building = self.building, let value else { return }
            let meter = try await client.meterDetail(campus: campus, building: building, room: value)
            try Task.checkCancellation()
            self.detail = meter
        }
    }
    private func query(_ label: String, action: @escaping @MainActor (EcardClient) async throws -> Void) {
        queryTask?.cancel()
        revision &+= 1
        let current = revision
        loadingText = label; errorText = recoveryError
        queryTask = Task {
            defer { if current == revision { loadingText = nil } }
            do {
                guard let client else { return }
                try await action(client)
            } catch {
                if current == revision, !Task.isCancelled { handleLoadError(error) }
            }
        }
    }

    func prepareConfirmation() {
        guard canPay, let amount, let room, let detail else { return }
        confirmation = Confirmation(amount: amount,
            room: detail.roomDescription ?? "\(buildings.first { $0.value == building }?.name ?? "") \(rooms.first { $0.value == room }?.name ?? "")",
            roomValue: room, context: detail.context)
    }
    func submit(_ confirmed: Confirmation) async {
        guard !isSubmitting, !isChecking, !isStarting, recoveryError == nil, receipt == nil,
              confirmation?.id == confirmed.id, room == confirmed.roomValue, let client, let account,
              boundGeneration == currentGeneration() else { return }
        // A second model may have recorded an order since this confirmation.
        do {
            if let saved = try pendingStore.load(account: account) {
                receipt = saved; errorText = EcardReceiptRecoveryError.unresolvedOrder.localizedDescription
                confirmation = nil; return
            }
        } catch {
            recoveryError = error.localizedDescription; errorText = recoveryError
            confirmation = nil; return
        }
        let operation = UUID(), current = revision, generation = currentGeneration()
        submissionID = operation
        isSubmitting = true; errorText = nil
        defer {
            if submissionID == operation { isSubmitting = false; confirmation = nil; submissionID = nil }
        }
        do {
            let outcome = try await client.rechargeElectricity(amount: confirmed.amount, context: confirmed.context,
                beforePayment: { [self] orderID in
                    guard submissionID == operation, revision == current, self.account == account,
                          currentGeneration() == generation, !Task.isCancelled else { throw EcardError.canceled }
                    guard try pendingStore.load(account: account) == nil else { throw EcardReceiptRecoveryError.unresolvedOrder }
                    let pending = Receipt(status: .pending, room: confirmed.room,
                                          amount: confirmed.amount.ecardAmountText, orderID: orderID)
                    try pendingStore.save(pending, account: account)
                    receipt = pending
                })
            // Journal updates stay bound to the captured account/order even if
            // the visible model has since moved to a replacement session.
            if outcome.isCompleted { try pendingStore.clear(account: account, orderID: outcome.orderID) }
            guard submissionID == operation, revision == current, self.account == account,
                  currentGeneration() == generation else { return }
            receipt = Receipt(status: outcome.isCompleted ? .completed : .pending,
                room: confirmed.room, amount: confirmed.amount.ecardAmountText, orderID: outcome.orderID)
        } catch {
            guard submissionID == operation, revision == current, self.account == account,
                  currentGeneration() == generation else { return }
            do {
                if let saved = try pendingStore.load(account: account) {
                    receipt = saved; errorText = error.localizedDescription
                } else {
                    handleLoadError(error)
                    receipt = Receipt(status: .failed, room: confirmed.room, amount: confirmed.amount.ecardAmountText,
                                      orderID: nil, message: error.localizedDescription)
                }
            } catch {
                recoveryError = error.localizedDescription; errorText = recoveryError
            }
        }
    }
    func checkOrder() async {
        guard !isChecking, !isSubmitting, !isStarting, let receipt, receipt.status == .pending,
              let orderID = receipt.orderID, let account else { return }
        guard boundGeneration == currentGeneration() else { start(account: account, force: true); return }
        guard let client else { start(account: account, force: true); return }
        let operation = UUID(), current = revision, generation = currentGeneration()
        checkingID = operation
        isChecking = true; errorText = nil
        defer { if checkingID == operation { isChecking = false; checkingID = nil } }
        do {
            let status = try await client.orderStatus(orderID: orderID)
            guard checkingID == operation, revision == current, self.account == account,
                  currentGeneration() == generation, self.receipt?.orderID == orderID else { return }
            if status == 1 {
                try pendingStore.clear(account: account, orderID: orderID)
                self.receipt?.status = .completed
            } else { errorText = "订单暂未确认完成，请稍后再次查询，勿重复缴费" }
        } catch {
            if checkingID == operation, revision == current, self.account == account, currentGeneration() == generation {
                handleLoadError(error)
            }
        }
    }
    func returnToForm() {
        guard receipt?.status != .pending else { return }
        receipt = nil; amountText = ""; errorText = recoveryError
        guard client != nil else { start(account: account, force: true); return }
        if let room { selectRoom(room) }
    }
}
