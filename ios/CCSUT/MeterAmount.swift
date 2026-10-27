import Foundation

/// Whole-yuan, three-drum display. Server validation and payment confirmation
/// remain authoritative; this only constrains what the amount control can pick.
enum MeterAmount {
    static let minimum = 10

    static func maximum(perPayment: Decimal?, perDay: Decimal?) -> Int {
        guard let perPayment, !perPayment.isNaN, perPayment > 0 else { return 0 }
        var limit = min(Decimal(400), perPayment)
        if let perDay {
            guard !perDay.isNaN, perDay > 0 else { return 0 }
            limit = min(limit, perDay)
        }
        let wholeYuan = NSDecimalNumber(decimal: limit).intValue
        return wholeYuan >= minimum ? wholeYuan : 0
    }

    static func clamp(_ amount: Int, maximum: Int) -> Int {
        guard maximum >= minimum else { return 0 }
        return min(max(minimum, amount), min(400, maximum))
    }

    static func digits(amount: Int, place: Int, maximum: Int) -> [Int] {
        guard [100, 10, 1].contains(place), maximum >= minimum else { return [0] }
        let amount = clamp(amount, maximum: maximum)
        let prefix = amount / (place * 10) * (place * 10)
        // A drum digit is available only if its represented interval intersects
        // the valid amount range. In 010, the tens drum cannot offer zero.
        return (0...9).filter { digit in
            let lower = prefix + digit * place
            let upper = lower + place - 1
            return lower <= min(400, maximum) && upper >= minimum
        }
    }

    static func replacing(amount: Int, place: Int, digit: Int, maximum: Int) -> Int {
        guard [100, 10, 1].contains(place) else { return clamp(amount, maximum: maximum) }
        let amount = clamp(amount, maximum: maximum)
        return clamp(amount - (amount / place % 10) * place + min(9, max(0, digit)) * place,
                     maximum: maximum)
    }
}
