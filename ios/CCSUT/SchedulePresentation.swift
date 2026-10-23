import Foundation

struct ScheduleCell: Identifiable {
    let weekday: Int
    let section: Int
    let courses: [ScheduleSlot]
    var id: String { "\(weekday)-\(section)" }
}

enum SchedulePresentation {
    // Baseline extraction from ScheduleView.cells; regression tests precede the fix.
    static func cells(_ slots: [ScheduleSlot], week: Int) -> [ScheduleCell] {
        let visible = slots.filter { $0.weeks.isEmpty || $0.weeks.contains(week) }
        return Dictionary(grouping: visible) { "\($0.weekday)-\($0.bigSection)" }.values.compactMap { group in
            guard let first = group.first else { return nil }
            return ScheduleCell(weekday: first.weekday, section: first.bigSection, courses: [first])
        }.sorted { ($0.weekday, $0.section) < ($1.weekday, $1.section) }
    }
}
