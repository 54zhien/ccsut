import Foundation

@main struct LeaveTicketReceiptTests {
    static func main() {
        let old = LeaveTicketCandidate(id: "old", reason: "事由", begin: "2026-10-26 08:00", end: "2026-10-26 18:00")
        let new = LeaveTicketCandidate(id: "new", reason: "事由", begin: "2026-10-26 08:00:00", end: "2026-10-26 18:00:00")
        var receipt = LeaveTicketReceipt(baseline: ["old"], reason: "事由", begin: "2026-10-26 08:00", end: "2026-10-26 18:00")
        precondition(receipt.consume([old]) == nil)
        precondition(receipt.consume([LeaveTicketCandidate(id: "wrong", reason: "其他", begin: new.begin, end: new.end)]) == nil)
        let duplicate = LeaveTicketCandidate(id: "other", reason: new.reason, begin: new.begin, end: new.end)
        precondition(receipt.consume([new, duplicate]) == nil)
        precondition(receipt.consume([old, new]) == "new")
        precondition(receipt.consume([new]) == nil)
        var invalid = LeaveTicketReceipt(baseline: [], reason: "", begin: "", end: "")
        precondition(invalid.consume([LeaveTicketCandidate(id: "invalid", reason: "", begin: "", end: "")]) == nil)
        var zoned = LeaveTicketReceipt(baseline: [], reason: "事由", begin: "2026-10-26 08:00", end: "2026-10-26 18:00")
        precondition(zoned.consume([LeaveTicketCandidate(id: "iso", reason: "事由", begin: "2026-10-26T00:00:00Z", end: "2026-10-26T10:00:00Z")]) == "iso")
        print("PASS: baseline, mismatch, ambiguity, minute normalization, exactly once")
    }
}
