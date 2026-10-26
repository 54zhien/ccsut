import Foundation

struct LeaveTicketCandidate {
    let id: String
    let reason: String
    let begin: String
    let end: String
}

/// A successful POST alone is not a ticket. Match exactly one new server record.
struct LeaveTicketReceipt {
    let baseline: Set<String>
    let reason: String
    let begin: String
    let end: String
    private(set) var consumed = false

    mutating func consume(_ records: [LeaveTicketCandidate]) -> String? {
        guard !consumed, let start = Self.minute(begin), let finish = Self.minute(end) else { return nil }
        let matches = records.filter {
            !baseline.contains($0.id) && $0.reason.trimmingCharacters(in: .whitespacesAndNewlines) == reason.trimmingCharacters(in: .whitespacesAndNewlines)
                && Self.minute($0.begin) == start && Self.minute($0.end) == finish
        }
        guard matches.count == 1 else { return nil }
        consumed = true
        return matches[0].id
    }

    static func timestamp(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.string(from: date)
    }

    private static func minute(_ text: String) -> String? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return timestamp(date) }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return timestamp(date) }
        let local = text.replacingOccurrences(of: "T", with: " ")
        guard local.count == 16 || local.count == 19 else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")
        format.isLenient = false
        format.dateFormat = local.count == 16 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd HH:mm:ss"
        guard let date = format.date(from: local), format.string(from: date) == local else { return nil }
        return timestamp(date)
    }
}
