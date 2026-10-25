import Foundation

enum CampusDisplayDate {
    private static func parsed(_ raw: String?) -> (Date, Bool)? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        // ISO8601DateFormatter normalizes impossible days and accepts suffixes.
        // Validate the complete input and calendar day before allowing conversion.
        let isoPattern = #"^\d{4}-(0[1-9]|1[0-2])-([0-2]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$"#
        let day = String(raw.prefix(10))
        let dayParser = formatter("yyyy-MM-dd")
        if raw.range(of: isoPattern, options: .regularExpression) != nil,
           let validDay = dayParser.date(from: day), dayParser.string(from: validDay) == day {
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                iso.formatOptions = options
                if let date = iso.date(from: raw) { return (date, true) }
            }
        }
        let parser = formatter("")
        for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            parser.dateFormat = pattern
            if let date = parser.date(from: raw), parser.string(from: date) == raw { return (date, pattern != "yyyy-MM-dd") }
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
    static func date(_ raw: String?, chinese: Bool = false) -> String {
        if let (date, _) = parsed(raw) { return formatter(chinese ? "yyyy年M月d日" : "yyyy.MM.dd").string(from: date) }
        let safe = CampusPrivacy.redact(raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        return safe.isEmpty ? "未设置" : safe
    }
    static func time(_ raw: String?) -> String {
        guard let (date, hasTime) = parsed(raw), hasTime else { return "" }
        return formatter("HH:mm").string(from: date)
    }
    static func timestamp(_ raw: String?, chinese: Bool = false) -> String {
        let clock = time(raw)
        return date(raw, chinese: chinese) + (clock.isEmpty ? "" : " " + clock)
    }
}
