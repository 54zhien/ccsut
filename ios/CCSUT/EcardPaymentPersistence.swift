import Foundation

enum EcardReceiptRecoveryError: Error, LocalizedError, Equatable {
    case readUnavailable, unsupportedVersion(Int), corrupted, missingRecord
    case storageUnavailable, unresolvedOrder
    var errorDescription: String? {
        switch self {
        case .readUnavailable: return "无法读取待确认订单，请稍后重试读取；持续失败时请核实原订单，勿重复缴费"
        case .unsupportedVersion: return "待确认订单由不支持的版本保存，请更新 App 后重试，勿重复缴费"
        case .corrupted: return "待确认订单记录已损坏，请先核实原订单，勿重复缴费"
        case .missingRecord: return "本地待确认订单记录已缺失，请先核实原订单，勿重复缴费"
        case .storageUnavailable: return "无法保存或更新支付恢复记录，请稍后重试，勿重复缴费"
        case .unresolvedOrder: return "已有待确认订单，请先查询原订单，勿重复缴费"
        }
    }
}

/// Account-scoped recovery boundary. The regression runner supplies an isolated
/// directory/defaults suite, never the app's production records.
@MainActor final class EcardPendingReceiptStore {
    private struct Header: Decodable { let version: Int }
    private struct Journal: Codable {
        enum State: String, Codable { case pending, cleared }
        let version: Int
        let state: State
        let receipt: EcardPaymentModel.Receipt?
    }
    private let directory: URL?
    private let defaults: UserDefaults
    private var blockedAccounts: Set<String> = []

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CCSUT/PendingPayments", isDirectory: true)
        self.defaults = defaults
    }

    func load(account: String) throws -> EcardPaymentModel.Receipt? {
        do { return try read(account: account) }
        catch {
            // Never change the unreadable original. Remember failure separately
            // so a subsequent missing file cannot silently enable a new debit.
            blockedAccounts.insert(account)
            if let file = try? fileURL(account: account) {
                // When the volume itself cannot be written, only this process
                // can remember the failure. Do not erase the original evidence.
                try? writeData(Data("recovery-required".utf8), to: blockURL(file))
            }
            throw error
        }
    }

    private func read(account: String) throws -> EcardPaymentModel.Receipt? {
        let file = try fileURL(account: account)
        if let data = try readIfPresent(file) {
            guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
                throw EcardReceiptRecoveryError.corrupted
            }
            guard header.version == 1 else { throw EcardReceiptRecoveryError.unsupportedVersion(header.version) }
            guard let journal = try? JSONDecoder().decode(Journal.self, from: data) else {
                throw EcardReceiptRecoveryError.corrupted
            }
            let receipt: EcardPaymentModel.Receipt?
            switch journal.state {
            case .pending:
                guard let saved = journal.receipt else { throw EcardReceiptRecoveryError.corrupted }
                try validate(saved); receipt = saved
                blockedAccounts.insert(account)
            case .cleared:
                guard journal.receipt == nil else { throw EcardReceiptRecoveryError.corrupted }
                receipt = nil
            }
            // Migration can be interrupted between atomic write and removing
            // defaults. Retire that shadow copy before a later completion clears
            // the durable file, otherwise the completed order would resurrect.
            defaults.removeObject(forKey: "ecard.pending.\(account)")
            return receipt
        }
        if try blockedAccounts.contains(account) || readIfPresent(blockURL(file)) != nil {
            throw EcardReceiptRecoveryError.missingRecord
        }
        let key = "ecard.pending.\(account)"
        guard defaults.object(forKey: key) != nil else { return nil }
        guard let data = defaults.data(forKey: key) else { throw EcardReceiptRecoveryError.corrupted }
        let receipt = try decode(data)
        // Remove the old copy only after its atomic replacement exists.
        try write(receipt, to: file)
        blockedAccounts.insert(account)
        defaults.removeObject(forKey: key)
        return receipt
    }

    private func blockURL(_ file: URL) -> URL { file.appendingPathExtension("recovery-block") }

    private func readIfPresent(_ file: URL) throws -> Data? {
        do { return try Data(contentsOf: file) }
        catch {
            let failure = error as NSError
            // fileExists also returns false for inaccessible files. Only an
            // actual not-found read result permits the no-record/legacy path.
            if failure.domain == NSCocoaErrorDomain,
               failure.code == NSFileReadNoSuchFileError || failure.code == NSFileNoSuchFileError { return nil }
            throw EcardReceiptRecoveryError.readUnavailable
        }
    }

    func save(_ receipt: EcardPaymentModel.Receipt, account: String) throws {
        try validate(receipt)
        let orderID = receipt.orderID
        if let existing = try load(account: account), existing.orderID != orderID {
            throw EcardReceiptRecoveryError.unresolvedOrder
        }
        try write(receipt, to: fileURL(account: account))
        blockedAccounts.insert(account)
    }

    func clear(account: String, orderID: String) throws {
        if try load(account: account)?.orderID == orderID {
            // Keep an atomic tombstone: deleting the file would let an older,
            // not-yet-flushed defaults snapshot resurrect the completed order.
            // No room, amount or order information is retained in this marker.
            try write(nil, to: fileURL(account: account))
        }
    }

    private func fileURL(account: String) throws -> URL {
        guard let directory, !account.isEmpty else { throw EcardReceiptRecoveryError.storageUnavailable }
        let name = Data(account.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name + ".json")
    }

    private func decode(_ data: Data) throws -> EcardPaymentModel.Receipt {
        guard let receipt = try? JSONDecoder().decode(EcardPaymentModel.Receipt.self, from: data) else {
            throw EcardReceiptRecoveryError.corrupted
        }
        try validate(receipt)
        return receipt
    }

    private func validate(_ receipt: EcardPaymentModel.Receipt) throws {
        guard receipt.status == .pending, let orderID = receipt.orderID, !orderID.isEmpty else {
            throw EcardReceiptRecoveryError.corrupted
        }
    }

    private func write(_ receipt: EcardPaymentModel.Receipt?, to file: URL) throws {
        let journal = Journal(version: 1, state: receipt == nil ? .cleared : .pending, receipt: receipt)
        do { try writeData(JSONEncoder().encode(journal), to: file) }
        catch { throw EcardReceiptRecoveryError.storageUnavailable }
    }

    private func writeData(_ data: Data, to file: URL) throws {
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
            try data.write(to: file, options: options)
        } catch { throw EcardReceiptRecoveryError.storageUnavailable }
    }
}
