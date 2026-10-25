import Foundation

enum EcardReceiptRecoveryError: Error, LocalizedError {
    case unreadable, storageUnavailable, unresolvedOrder
    var errorDescription: String? {
        switch self {
        case .unreadable: return "有一笔无法读取的待确认订单，请先核实原订单，勿重复缴费"
        case .storageUnavailable: return "无法保存或更新支付恢复记录，请稍后重试，勿重复缴费"
        case .unresolvedOrder: return "已有待确认订单，请先查询原订单，勿重复缴费"
        }
    }
}

/// Account-scoped recovery boundary. The regression runner supplies an isolated
/// directory/defaults suite, never the app's production records.
@MainActor final class EcardPendingReceiptStore {
    private let directory: URL?
    private let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CCSUT/PendingPayments", isDirectory: true)
        self.defaults = defaults
    }

    func load(account: String) throws -> EcardPaymentModel.Receipt? {
        let file = try fileURL(account: account)
        if FileManager.default.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file) else { throw EcardReceiptRecoveryError.unreadable }
            let receipt = try decode(data)
            // Migration can be interrupted between atomic write and removing
            // defaults. Retire that shadow copy before a later completion clears
            // the durable file, otherwise the completed order would resurrect.
            defaults.removeObject(forKey: "ecard.pending.\(account)")
            return receipt
        }
        let key = "ecard.pending.\(account)"
        guard defaults.object(forKey: key) != nil else { return nil }
        guard let data = defaults.data(forKey: key) else { throw EcardReceiptRecoveryError.unreadable }
        let receipt = try decode(data)
        // Remove the old copy only after its atomic replacement exists.
        try write(receipt, to: file)
        defaults.removeObject(forKey: key)
        return receipt
    }

    func save(_ receipt: EcardPaymentModel.Receipt, account: String) throws {
        guard receipt.status == .pending, let orderID = receipt.orderID, !orderID.isEmpty else {
            throw EcardReceiptRecoveryError.unreadable
        }
        if let existing = try load(account: account), existing.orderID != orderID {
            throw EcardReceiptRecoveryError.unresolvedOrder
        }
        try write(receipt, to: fileURL(account: account))
    }

    func clear(account: String, orderID: String) throws {
        if try load(account: account)?.orderID == orderID {
            do { try FileManager.default.removeItem(at: fileURL(account: account)) }
            catch { throw EcardReceiptRecoveryError.storageUnavailable }
        }
    }

    private func fileURL(account: String) throws -> URL {
        guard let directory, !account.isEmpty else { throw EcardReceiptRecoveryError.storageUnavailable }
        let name = Data(account.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name + ".json")
    }

    private func decode(_ data: Data) throws -> EcardPaymentModel.Receipt {
        guard let receipt = try? JSONDecoder().decode(EcardPaymentModel.Receipt.self, from: data),
              receipt.status == .pending, let orderID = receipt.orderID, !orderID.isEmpty else {
            throw EcardReceiptRecoveryError.unreadable
        }
        return receipt
    }

    private func write(_ receipt: EcardPaymentModel.Receipt, to file: URL) throws {
        do {
            let parent = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            #if canImport(Darwin)
            var resource = parent
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try resource.setResourceValues(values)
            #endif
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
            #endif
            try JSONEncoder().encode(receipt).write(to: file, options: options)
        } catch { throw EcardReceiptRecoveryError.storageUnavailable }
    }
}
