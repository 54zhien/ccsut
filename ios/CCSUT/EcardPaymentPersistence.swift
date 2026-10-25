import Foundation

/// Account-scoped recovery boundary. The regression runner supplies an isolated
/// directory/defaults suite, never the app's production records.
@MainActor final class EcardPendingReceiptStore {
    let directory: URL
    let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CCSUT/PendingPayments", isDirectory: true)
        self.defaults = defaults
    }

    func load(account: String) throws -> EcardPaymentModel.Receipt? {
        guard let data = defaults.data(forKey: "ecard.pending.\(account)"),
              let receipt = try? JSONDecoder().decode(EcardPaymentModel.Receipt.self, from: data),
              receipt.status == .pending else { return nil }
        return receipt
    }

    func save(_ receipt: EcardPaymentModel.Receipt, account: String) throws {
        defaults.set(try JSONEncoder().encode(receipt), forKey: "ecard.pending.\(account)")
    }

    func clear(account: String, orderID: String) throws {
        if try load(account: account)?.orderID == orderID {
            defaults.removeObject(forKey: "ecard.pending.\(account)")
        }
    }
}
