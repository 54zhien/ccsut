import Foundation

struct TeachingWeekSnapshot: Codable {
    let term: String
    let account: String
    let week: Int
    let verifiedAt: Date

    func week(on date: Date, term: String, account: String) -> Int? {
        guard !account.isEmpty, !term.isEmpty, date >= verifiedAt,
              date.timeIntervalSince(verifiedAt) <= 28 * 86400,
              self.term == term, self.account == account, (1...53).contains(week) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: verifiedAt)?.start,
              let end = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let days = calendar.dateComponents([.day], from: start, to: end).day,
              (0...28).contains(days) else { return nil }
        let result = week + days / 7
        return (1...53).contains(result) ? result : nil
    }
}

struct ScheduleCell: Identifiable {
    let weekday: Int
    let section: Int
    let courses: [ScheduleSlot]
    var id: String { "\(weekday)-\(section)" }
}

enum SchedulePresentation {
    static func periodCaption(_ slot: ScheduleSlot) -> String {
        slot.startPeriod == slot.endPeriod
            ? "第 \(slot.startPeriod) 节"
            : "第 \(slot.startPeriod)–\(slot.endPeriod) 节"
    }

    /// The API keeps its raw term code; only the visible caption is normalized.
    static func termTitle(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 4,
              Int(parts[0]) != nil, Int(parts[1]) != nil,
              let term = Int(parts[2]), (1...3).contains(term) else { return raw }
        let names = ["第一学期", "第二学期", "第三学期"]
        return "\(parts[0])–\(parts[1]) 学年 · \(names[term - 1])"
    }

    static func cells(_ slots: [ScheduleSlot], week: Int) -> [ScheduleCell] {
        let visible = slots.filter { $0.weeks.isEmpty || $0.weeks.contains(week) }
        return Dictionary(grouping: visible) { "\($0.weekday)-\($0.bigSection)" }.values.compactMap { group in
            guard let first = group.first else { return nil }
            return ScheduleCell(weekday: first.weekday, section: first.bigSection, courses: coalesced(group))
        }.sorted { ($0.weekday, $0.section) < ($1.weekday, $1.section) }
    }

    private struct CourseKey: Hashable {
        let name: String
        let teacher: String
        let room: String
        let weeks: [Int]
    }

    /// Only join adjacent periods with identical course, place and week information.
    /// Conflicting courses remain separate, so the UI can expose every source record.
    private static func coalesced(_ slots: [ScheduleSlot]) -> [ScheduleSlot] {
        let groups = Dictionary(grouping: slots) {
            CourseKey(name: $0.course, teacher: $0.teacher, room: $0.room, weeks: $0.weeks.sorted())
        }
        var result: [ScheduleSlot] = []
        for group in groups.values {
            let ordered = group.sorted { $0.startPeriod < $1.startPeriod }
            guard var current = ordered.first else { continue }
            for next in ordered.dropFirst() {
                if next.startPeriod <= current.endPeriod + 1 {
                    current = ScheduleSlot(course: current.course, teacher: current.teacher, room: current.room,
                                           weekday: current.weekday, startPeriod: current.startPeriod,
                                           endPeriod: max(current.endPeriod, next.endPeriod), weeks: current.weeks)
                } else {
                    result.append(current)
                    current = next
                }
            }
            result.append(current)
        }
        return result.sorted {
            if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
            return ($0.course, $0.room, $0.teacher) < ($1.course, $1.room, $1.teacher)
        }
    }
}
