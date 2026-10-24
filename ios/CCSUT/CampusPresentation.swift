import Foundation

enum CampusDisplayDate {
    private static func parsed(_ raw: String?) -> (Date, Bool)? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            iso.formatOptions = options
            if let date = iso.date(from: raw) { return (date, true) }
        }
        let parser = formatter("")
        for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            parser.dateFormat = pattern
            if let date = parser.date(from: raw) { return (date, pattern != "yyyy-MM-dd") }
        }
        return nil
    }
    private static func formatter(_ pattern: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")
        value.dateFormat = pattern; value.isLenient = false
        return value
    }
    static func date(_ raw: String?) -> String {
        if let (date, _) = parsed(raw) { return formatter("yyyy.MM.dd").string(from: date) }
        let safe = CampusPrivacy.redact(raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        return safe.isEmpty ? "未设置" : safe
    }
    static func time(_ raw: String?) -> String {
        guard let (date, hasTime) = parsed(raw), hasTime else { return "" }
        return formatter("HH:mm").string(from: date)
    }
    static func timestamp(_ raw: String?) -> String {
        let clock = time(raw)
        return date(raw) + (clock.isEmpty ? "" : " " + clock)
    }
}
