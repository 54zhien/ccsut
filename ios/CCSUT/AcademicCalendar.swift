import Foundation

enum AcademicContextError: LocalizedError {
    case missingTerm, missingStudentKey, missingExamTerms, invalidSchedule

    var errorDescription: String? {
        switch self {
        case .missingTerm: return "暂时无法确认教学学期，请稍后重试"
        case .missingStudentKey: return "课表信息不完整，请重新加载"
        case .missingExamTerms: return "暂时无法获取考试学期，请稍后重试"
        case .invalidSchedule: return "课表中的周次或节次无法识别，已保留原有数据"
        }
    }
}

struct TimetableContext {
    let term: String
    let studentKey: String
}

/// The default timetable page identifies the teaching term. Elective terms are unrelated.
enum AcademicCalendarParser {
    static func isTerm(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 4,
              let year = Int(parts[0]), let next = Int(parts[1]), let term = Int(parts[2]) else { return false }
        return (1900...2200).contains(year) && next == year + 1 && (1...3).contains(term)
    }

    static func timetable(_ html: String) throws -> TimetableContext {
        var selectedTerms: [String] = []
        var keys: [String] = []
        for input in matches(#"<input\b([^>]*)>"#, in: html) {
            let attrs = attributes(input[1])
            let fields = [attrs["id"], attrs["name"]].compactMap { $0?.lowercased() }
            if fields.contains("xnxq"), let value = attrs["value"], isTerm(value) { selectedTerms.append(value) }
            if fields.contains("xhid"), let value = attrs["value"], !value.isEmpty { keys.append(value) }
        }
        for select in matches(#"<select\b([^>]*)>([\s\S]*?)</select>"#, in: html) {
            let attrs = attributes(select[1])
            guard [attrs["id"], attrs["name"]].compactMap({ $0?.lowercased() }).contains("xnxq") else { continue }
            let options = matches(#"<option\b([^>]*)>"#, in: select[2])
            let selected = options.filter { hasSelected($0[1]) }
            for option in selected.isEmpty ? Array(options.prefix(1)) : selected {
                if let value = attributes(option[1])["value"], isTerm(value) { selectedTerms.append(value) }
            }
        }
        let uniqueTerms = Set(selectedTerms)
        guard uniqueTerms.count == 1, let term = uniqueTerms.first else { throw AcademicContextError.missingTerm }
        let uniqueKeys = Set(keys)
        guard uniqueKeys.count == 1, let key = uniqueKeys.first else { throw AcademicContextError.missingStudentKey }
        return TimetableContext(term: term, studentKey: key)
    }

    static func examTerms(_ html: String) throws -> [String] {
        // Only semester-shaped option values and explicit changeXn calls are accepted.
        // Never infer a term from arbitrary page text or a fixed year range.
        var terms = Set<String>()
        for option in matches(#"<option\b([^>]*)>"#, in: html) {
            if let value = attributes(option[1])["value"], isTerm(value) { terms.insert(value) }
        }
        for call in matches(#"changeXn\s*\(\s*["']([^"']+)["']\s*\)"#, in: html) {
            if isTerm(call[1]) { terms.insert(call[1]) }
        }
        guard !terms.isEmpty else { throw AcademicContextError.missingExamTerms }
        return terms.sorted(by: >)
    }

    private static func hasSelected(_ attrs: String) -> Bool {
        attrs.range(of: #"(?:^|\s)selected(?:\s|=|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for attr in matches(#"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, in: text) {
            let value = attr[2...4].first { !$0.isEmpty } ?? ""
            result[attr[1].lowercased()] = value.replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { i in
                match.range(at: i).location == NSNotFound ? "" : ns.substring(with: match.range(at: i))
            }
        }
    }
}

enum ScheduleValidation {
    static func slots(_ items: [ScheduleItem]) throws -> [ScheduleSlot] {
        try items.map { item in
            guard let day = item.xingqi, (1...7).contains(day),
                  let period = item.djc, (1...8).contains(period),
                  let name = item.kcmc, !name.strippingHTML.isEmpty,
                  let rawWeeks = item.zc, !rawWeeks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw AcademicContextError.invalidSchedule }
            let weeks: [Int]
            do { weeks = try WeekParser.parseValidated(rawWeeks) }
            catch { throw AcademicContextError.invalidSchedule }
            return ScheduleSlot(course: name.strippingHTML, teacher: (item.tmc ?? "").strippingHTML,
                                room: (item.croommc ?? "").strippingHTML, weekday: day,
                                startPeriod: period, endPeriod: period, weeks: weeks)
        }
    }
}

enum ExamSnapshotLoader {
    /// Returns only complete results. A caller can replace its snapshot atomically on success.
    static func load(terms: [String], fetch: (String) async throws -> [ExamItem]) async throws -> [ExamItem] {
        guard !terms.isEmpty, terms.allSatisfy(AcademicCalendarParser.isTerm) else { throw AcademicContextError.missingExamTerms }
        var collected: [ExamItem] = []
        for term in Array(Set(terms)).sorted(by: >) {
            try Task.checkCancellation()
            var list = try await fetch(term)
            for index in list.indices { list[index].term = term }
            collected.append(contentsOf: list)
        }
        try Task.checkCancellation()
        return collected.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }
}
