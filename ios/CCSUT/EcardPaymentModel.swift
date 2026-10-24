import Foundation
import Observation

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
    var loginRequest: LoginRequest?
    var confirmation: Confirmation?
    var receipt: Receipt?

    @ObservationIgnored private var client: EcardClient?
    @ObservationIgnored private var account: String?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var initialTask: Task<Void, Never>?

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
        detail != nil && room != nil && amount != nil && !amountText.isEmpty && amountHint == nil &&
        loadingText == nil && !isStarting && !isSubmitting && receipt == nil
    }
    var quickAmounts: [Decimal] { fee?.quickAmounts.filter { $0 > 0 && $0 <= (fee?.maxAmount ?? 0) } ?? [] }

    func start(account: String?, force: Bool = false) {
        guard !isStarting, !isSubmitting else { return }
        guard let account, !account.isEmpty else {
            errorText = "暂未获取到学号，请稍后重新加载"
            return
        }
        if self.account == account, fee != nil, !force {
            if let campus, buildings.isEmpty { selectCampus(campus) }
            else if let room, detail == nil { selectRoom(room) }
            return
        }
        stopQueries()
        self.account = account
        receipt = pendingReceipt(for: account)
        campus = nil; building = nil; room = nil; detail = nil
        campuses = []; buildings = []; rooms = []; fee = nil
        client = nil
        amountText = ""; errorText = nil; isStarting = true
        if force { EcardTokenBridge.clearCachedToken() }
        if let token = EcardTokenBridge.cachedToken(forAccount: account) {
            acceptToken(token)
        } else {
            loginRequest = LoginRequest(bridge: EcardTokenBridge(dataStore: WebStore.dataStore), account: account)
        }
    }

    func acceptToken(_ token: String) {
        client = EcardClient(token: token)
        loginRequest = nil
        let current = revision
        initialTask = Task {
            defer { if current == revision { isStarting = false } }
            do {
                guard let client else { return }
                async let item = client.feeItem()
                async let options = client.campuses()
                let (loadedFee, loadedCampuses) = try await (item, options)
                guard current == revision, !Task.isCancelled else { return }
                fee = loadedFee; campuses = loadedCampuses
                isStarting = false
                if loadedCampuses.count == 1 { selectCampus(loadedCampuses[0].value) }
                else if loadedCampuses.isEmpty { errorText = "暂无可选校区，请稍后重新加载" }
            } catch { if current == revision, !Task.isCancelled { errorText = error.localizedDescription } }
        }
    }

    func loginFailed(_ error: Error) {
        errorText = error.localizedDescription
        loginRequest = nil; isStarting = false
    }
    func loginDismissed() {
        // SwiftUI clears the sheet item before calling onDismiss.
        if isStarting, client == nil {
            loginRequest = nil; isStarting = false
            errorText = EcardError.canceled.localizedDescription
        }
    }
    func stopQueries() {
        revision &+= 1
        queryTask?.cancel(); initialTask?.cancel()
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
        loadingText = label; errorText = nil
        queryTask = Task {
            defer { if current == revision { loadingText = nil } }
            do {
                guard let client else { return }
                try await action(client)
            } catch {
                if current == revision, !Task.isCancelled { errorText = error.localizedDescription }
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
        guard !isSubmitting, confirmation?.id == confirmed.id, room == confirmed.roomValue, let client else { return }
        isSubmitting = true; errorText = nil
        defer { isSubmitting = false; confirmation = nil }
        do {
            let outcome = try await client.rechargeElectricity(amount: confirmed.amount, context: confirmed.context)
            receipt = Receipt(status: outcome.isCompleted ? .completed : .pending,
                room: confirmed.room, amount: confirmed.amount.ecardAmountText, orderID: outcome.orderID)
        } catch EcardError.paymentUnconfirmed(let orderID) {
            receipt = Receipt(status: .pending, room: confirmed.room, amount: confirmed.amount.ecardAmountText, orderID: orderID)
        } catch {
            receipt = Receipt(status: .failed, room: confirmed.room, amount: confirmed.amount.ecardAmountText,
                              orderID: nil, message: error.localizedDescription)
        }
        persistPending()
    }
    func checkOrder() async {
        guard !isChecking, let receipt, let orderID = receipt.orderID else { return }
        guard let client else { start(account: account, force: true); return }
        isChecking = true; errorText = nil
        defer { isChecking = false }
        do {
            if try await client.orderStatus(orderID: orderID) == 1 {
                self.receipt?.status = .completed
                persistPending()
            } else { errorText = "订单暂未确认完成，请稍后再次查询，勿重复缴费" }
        } catch { errorText = error.localizedDescription }
    }
    func returnToForm() {
        guard receipt?.status != .pending else { return }
        receipt = nil; amountText = ""; errorText = nil
        if let room { selectRoom(room) }
    }
    private func pendingReceipt(for account: String) -> Receipt? {
        guard let data = UserDefaults.standard.data(forKey: "ecard.pending.\(account)"),
              let saved = try? JSONDecoder().decode(Receipt.self, from: data), saved.status == .pending else { return nil }
        return saved
    }
    private func persistPending() {
        guard let account else { return }
        let key = "ecard.pending.\(account)"
        if let receipt, receipt.status == .pending, let data = try? JSONEncoder().encode(receipt) {
            UserDefaults.standard.set(data, forKey: key)
        } else { UserDefaults.standard.removeObject(forKey: key) }
    }
}
