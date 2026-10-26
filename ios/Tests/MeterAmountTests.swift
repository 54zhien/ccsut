import Foundation

@main struct MeterAmountTests {
    static func main() {
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
        }
        check(MeterAmount.maximum(perPayment: 1000, perDay: 1000) == 400, "UI never exceeds 400")
        check(MeterAmount.maximum(perPayment: 275.99, perDay: 300) == 275, "whole yuan respects lower configured cap")
        check(MeterAmount.maximum(perPayment: 400, perDay: 150) == 150, "daily configured cap also applies")
        check(MeterAmount.maximum(perPayment: nil, perDay: nil) == 0, "unconfigured amount control is disabled")
        check(MeterAmount.maximum(perPayment: 400, perDay: -1) == 0, "invalid limit fails closed")
        check(MeterAmount.digits(amount: 399, place: 100, maximum: 400) == Array(0...4), "hundreds 0 through 4")
        check(MeterAmount.replacing(amount: 399, place: 100, digit: 4, maximum: 400) == 400, "399 to 400 clears invalid lower digits")
        check(MeterAmount.digits(amount: 400, place: 10, maximum: 400) == [0], "400 has no nonzero tens")
        check(MeterAmount.digits(amount: 400, place: 1, maximum: 400) == [0], "400 has no nonzero ones")
        check(MeterAmount.replacing(amount: 400, place: 100, digit: 3, maximum: 400) == 300, "moving below 400 restores lower digit choices")
        check(MeterAmount.digits(amount: 270, place: 1, maximum: 275) == Array(0...5), "configured cap restricts last digit")
        check(MeterAmount.clamp(399, maximum: 150) == 150, "configuration change clamps existing selection")
        check(MeterAmount.clamp(0, maximum: 400) == 10, "configured picker starts at the ten-yuan minimum")
        check(MeterAmount.clamp(9, maximum: 400) == 10, "amounts below ten clamp to ten")
        check(MeterAmount.maximum(perPayment: 9.99, perDay: 400) == 0, "cap below ten disables recharge")
        check(MeterAmount.clamp(10, maximum: 9) == 0, "unavailable range never invents an allowed amount")
        check(MeterAmount.digits(amount: 10, place: 10, maximum: 400) == Array(1...9), "zero tens cannot produce a sub-minimum amount")
        check(MeterAmount.digits(amount: 10, place: 1, maximum: 15) == Array(0...5), "narrow valid range retains exactly ten through fifteen")
        check(MeterAmount.replacing(amount: 10, place: 10, digit: 0, maximum: 400) == 10, "programmatic invalid digit cannot bypass the minimum")
        print("PASS: 19 meter amount boundary checks")
    }
}
