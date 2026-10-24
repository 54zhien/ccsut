import Foundation

@main struct CampusPresentationTests {
    static func main() {
        var failures = 0
        func check(_ value: Bool, _ title: String) { print("\(value ? "PASS" : "FAIL") \(title)"); if !value { failures += 1 } }
        check(CampusDisplayDate.date("2026-10-24T00:00:00.000Z") == "2026.10.24" && CampusDisplayDate.time("2026-10-24T00:00:00.000Z") == "08:00", "ISO timestamps display the school timezone")
        check(CampusDisplayDate.timestamp("2026-10-24 08:30:00") == "2026.10.24 08:30", "local timestamps retain date and time")
        check(CampusDisplayDate.date("2025-12-31") == "2025.12.31" && CampusDisplayDate.time("2025-12-31").isEmpty, "date-only records retain year without inventing midnight")
        check(CampusDisplayDate.date(nil) == "未设置" && CampusDisplayDate.time(nil).isEmpty, "missing dates have a clear neutral placeholder")
        check(CampusDisplayDate.date("not a date") == "not a date", "unknown date formats remain readable")
        check(!CampusDisplayDate.timestamp("联系电话 18000000000").contains("18000000000"), "unexpected date strings still redact sensitive digits")
        check(CampusDisplayDate.date("2026-15-40") == "2026-15-40", "invalid dates are not silently normalized")
        check(["2026-02-30T08:00:00Z", "2026-02-30T08:00:00.000Z", "2026-02-29T08:00:00Z"].allSatisfy { CampusDisplayDate.date($0) == $0 && CampusDisplayDate.time($0).isEmpty }, "invalid ISO calendar days retain the original text")
        check(CampusDisplayDate.date("2026-10-24T08:00:00Zgarbage") == "2026-10-24T08:00:00Zgarbage", "ISO input must consume the entire string")
        check(CampusDisplayDate.timestamp("2026-10-24T08:30:00+08:00") == "2026.10.24 08:30", "valid ISO offsets still display the school timezone")
        if failures > 0 { exit(1) }
    }
}
