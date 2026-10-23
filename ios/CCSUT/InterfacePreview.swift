import Foundation

/// Simulator-only screenshot fixtures. Release builds cannot enable this route.
enum InterfacePreview {
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-ui")
        #else
        false
        #endif
    }

    static var page: String {
        guard enabled else { return "" }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--preview-page"), args.indices.contains(index + 1) else { return "schedule" }
        return args[index + 1]
    }

    #if DEBUG
    static var schedule: ScheduleBundle {
        func course(_ name: String, _ teacher: String, _ room: String, _ day: Int, _ section: Int) -> ScheduleSlot {
            ScheduleSlot(course: name, teacher: teacher, room: room, weekday: day,
                         startPeriod: section * 2 - 1, endPeriod: section * 2, weeks: Array(1...16))
        }
        var bundle = ScheduleBundle(title: "2026–2027 学年 · 第一学期", slots: [
            course("高等数学", "示例教师", "9-112", 1, 1),
            course("大学英语", "示例教师", "6-208", 2, 1),
            course("工程制图", "示例教师", "9-205", 4, 1),
            course("大学物理", "示例教师", "8-302", 5, 1),
            course("机械设计基础", "示例教师", "9-112", 1, 2),
            course("工程材料", "示例教师", "9-305", 3, 2),
            course("高等数学", "示例教师", "9-112", 5, 2),
            course("思想道德与法治", "示例教师", "7-201", 2, 3),
            course("体育", "示例教师", "体育馆", 4, 3),
            course("大学物理实验", "示例教师", "实验楼 302", 3, 4),
            course("大学英语", "示例教师", "6-208", 5, 4),
        ], periods: [1, 2, 3, 4])
        if page == "conflict" {
            bundle.slots.append(ScheduleSlot(course: "高等数学", teacher: "另一位教师", room: "9-112", weekday: 1,
                                             startPeriod: 1, endPeriod: 2, weeks: [7]))
        }
        return bundle
    }

    static var exam: ExamItem {
        ExamItem(id: "preview", kcmc: "机械设计基础", ksrq: "2026-10-28", qssj: "14:20",
                 kssj: "2026-10-28 14:20~15:50", jxlmc: "9号栋", jsmc: "9-112", zwh: "18",
                 ksxs: "考试", kspcmc: "期末考试", dataXnxq: "2026-2027-1")
    }
    #endif
}
