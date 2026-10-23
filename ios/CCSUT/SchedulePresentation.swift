import Foundation

struct ScheduleCell: Identifiable {
    let weekday: Int
    let section: Int
    let courses: [ScheduleSlot]
    var id: String { "\(weekday)-\(section)" }
}

enum SchedulePresentation {
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
