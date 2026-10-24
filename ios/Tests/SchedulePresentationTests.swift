import Foundation

@main
struct SchedulePresentationTests {
    static func main() {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        func slot(_ name: String, _ period: Int, weeks: [Int] = [7], room: String = "9-112") -> ScheduleSlot {
            ScheduleSlot(course: name, teacher: "教师", room: room, weekday: 1,
                         startPeriod: period, endPeriod: period, weeks: weeks)
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
        print("Schedule presentation failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
