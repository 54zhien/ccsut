import Foundation

/// Whole-yuan, three-drum display. Server validation and payment confirmation
/// remain authoritative; this only constrains what the amount control can pick.
enum MeterAmount {
    static func maximum(perPayment: Decimal?, perDay: Decimal?) -> Int {
        guard let perPayment, !perPayment.isNaN, perPayment > 0 else { return 0 }
        var limit = min(Decimal(400), perPayment)
        if let perDay {
            guard !perDay.isNaN, perDay > 0 else { return 0 }
            limit = min(limit, perDay)
        }
        return NSDecimalNumber(decimal: limit).intValue
    }

    static func clamp(_ amount: Int, maximum: Int) -> Int {
        min(max(0, amount), max(0, min(400, maximum)))
    }

    static func digits(amount: Int, place: Int, maximum: Int) -> [Int] {
        guard [100, 10, 1].contains(place) else { return [0] }
        let amount = clamp(amount, maximum: maximum)
        let prefix = amount / (place * 10) * (place * 10)
        let largest = min(9, max(0, (clamp(maximum, maximum: 400) - prefix) / place))
        return Array(0...largest)
    }

    static func replacing(amount: Int, place: Int, digit: Int, maximum: Int) -> Int {
        guard [100, 10, 1].contains(place) else { return clamp(amount, maximum: maximum) }
        let amount = clamp(amount, maximum: maximum)
        return clamp(amount - (amount / place % 10) * place + min(9, max(0, digit)) * place,
                     maximum: maximum)
    }
}
