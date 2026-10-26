import Foundation

@main
struct SchedulePresentationTests {
    static func main() {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        func slot(_ name: String, _ period: Int, weekday: Int = 1, weeks: [Int] = [7],
                  room: String = "9-112", teacher: String = "教师") -> ScheduleSlot {
            ScheduleSlot(course: name, teacher: teacher, room: room, weekday: weekday,
                         startPeriod: period, endPeriod: period, weeks: weeks)
        }
        func instant(_ value: String) -> Date {
            ISO8601DateFormatter().date(from: value)!
        }
        let paired = SchedulePresentation.cells([slot("工程制图", 1), slot("工程制图", 2)], week: 7)
        check(paired.count == 1 && paired[0].courses.count == 1, "paired periods produce one course card")
        check(paired.first?.courses.first?.startPeriod == 1 && paired.first?.courses.first?.endPeriod == 2,
              "merged course details preserve both source periods")
        let conflict = SchedulePresentation.cells([slot("工程制图", 1), slot("高等数学", 2)], week: 7)
        check(conflict.first?.courses.count == 2, "different courses in one cell remain accessible")
        let differentRoom = SchedulePresentation.cells([slot("工程制图", 1), slot("工程制图", 2, room: "实验楼")], week: 7)
        check(differentRoom.first?.courses.count == 2, "different locations are never merged")
        let differentWeeks = SchedulePresentation.cells([slot("工程制图", 1, weeks: [6, 7]), slot("工程制图", 2, weeks: [7, 8])], week: 7)
        check(differentWeeks.first?.courses.count == 2, "different week ranges retain their source meaning")
        check(SchedulePresentation.cells([slot("工程制图", 1, weeks: [8])], week: 7).isEmpty,
              "other weeks stay out of the selected timetable")
        check(SchedulePresentation.cells([slot("工程制图", 1, weeks: [])], week: 7).count == 1,
              "unspecified week ranges retain the existing visibility rule")
        let reverse = SchedulePresentation.cells([slot("工程制图", 2), slot("工程制图", 1)], week: 7)
        check(reverse.first?.courses.first?.startPeriod == 1 && reverse.first?.courses.first?.endPeriod == 2,
              "source ordering does not change merged periods")

        let sundayBeforeShanghaiMidnight = instant("2026-10-25T15:30:00Z")
        let mondayAfterShanghaiMidnight = instant("2026-10-25T16:30:00Z")
        let dayBoundarySlots = [slot("Sunday", 1, weekday: 7), slot("Monday", 1, weekday: 1)]
        let beforeBoundary = SchedulePresentation.todayCourses(dayBoundarySlots, week: 7,
                                                               on: sundayBeforeShanghaiMidnight)
        let afterBoundary = SchedulePresentation.todayCourses(dayBoundarySlots, week: 7,
                                                              on: mondayAfterShanghaiMidnight)
        check(beforeBoundary?.map(\.course) == ["Sunday"] && afterBoundary?.map(\.course) == ["Monday"],
              "today follows Shanghai weekday across UTC midnight")

        let sundayCourses = SchedulePresentation.todayCourses([
            slot("Sunday current", 1, weekday: 7, weeks: [7]),
            slot("Sunday other week", 2, weekday: 7, weeks: [8]),
            slot("Monday current", 3, weekday: 1, weeks: [7])
        ], week: 7, on: sundayBeforeShanghaiMidnight)
        check(sundayCourses?.map(\.course) == ["Sunday current"],
              "today filters by verified week and maps Sunday to weekday seven")

        check(SchedulePresentation.todayCourses([], week: nil, on: mondayAfterShanghaiMidnight) == nil,
              "an unavailable verified week is distinct from an empty day")
        check(SchedulePresentation.todayCourses([], week: 0, on: mondayAfterShanghaiMidnight) == nil &&
              SchedulePresentation.todayCourses([], week: 54, on: mondayAfterShanghaiMidnight) == nil,
              "invalid verified weeks are unavailable")
        let validEmptyDay = SchedulePresentation.todayCourses([
            slot("Sunday", 1, weekday: 7, weeks: [7])
        ], week: 7, on: mondayAfterShanghaiMidnight)
        check(validEmptyDay?.isEmpty == true,
              "a valid week with no courses today returns an empty list")

        let dailyPair = SchedulePresentation.todayCourses([
            slot("Paired course", 2), slot("Paired course", 1)
        ], week: 7, on: mondayAfterShanghaiMidnight)
        check(dailyPair?.count == 1 && dailyPair?.first?.startPeriod == 1 && dailyPair?.first?.endPeriod == 2,
              "today reuses timetable coalescing for adjacent periods")

        let conflicts = [slot("Beta", 1), slot("Alpha", 1), slot("Gamma", 3)]
        let chronological = SchedulePresentation.todayCourses(conflicts, week: 7,
                                                              on: mondayAfterShanghaiMidnight)
        let reversedChronological = SchedulePresentation.todayCourses(Array(conflicts.reversed()), week: 7,
                                                                      on: mondayAfterShanghaiMidnight)
        check(chronological?.map(\.course) == ["Alpha", "Beta", "Gamma"],
              "today retains conflicts and sorts chronologically with a deterministic tie break")
        check(chronological?.map(\.course) == reversedChronological?.map(\.course),
              "today course order does not depend on source ordering")
        print("Schedule presentation failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
