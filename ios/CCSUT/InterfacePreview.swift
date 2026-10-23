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
    static var longList: Bool {
        ProcessInfo.processInfo.arguments.contains("--preview-long-list")
    }

    static var emptyPage: Bool {
        ProcessInfo.processInfo.arguments.contains("--preview-empty")
    }

    static var electiveInit: ElectiveInit {
        decode("""
        {"xsxm":"预览同学","xkxnxq":"2026-2027-1"}
        """)
    }

    static var scores: [ScoreItem] {
        if longList {
            return (1...18).map { index in
                ScoreItem(id: "long-\(index)", kcmc: "示例课程 \(index)", kcbh: String(format: "%02d", index),
                          xf: "3", zhcj: "90", jd: 4, cjfxms: nil, kcxz: nil,
                          xnxq: "2026-2027-1", sfjg: "1")
            }
        }
        return decode("""
        [{"id":"1","kcmc":"高等数学","kcbh":"01","xf":"4","zhcj":"92","jd":4.2,"xnxq":"2026-2027-1","sfjg":"1"},
         {"id":"2","kcmc":"大学英语","kcbh":"02","xf":"3","zhcj":"86","jd":3.6,"xnxq":"2026-2027-1","sfjg":"1"},
         {"id":"3","kcmc":"机械设计基础","kcbh":"03","xf":"3.5","zhcj":"88","jd":3.8,"xnxq":"2025-2026-2","sfjg":"1"}]
        """)
    }

    static var classes: [TeachingClass] {
        decode("""
        [{"id":"1","kcmc":"工程制图","teacher":"示例教师","xf":"3","yxrl":"28/40","sksjdd":"周四 1–2节 · 9-205","sfkxk":"1","status":"1"},
         {"id":"2","kcmc":"大学英语","teacher":"示例教师","xf":"3","yxrl":"32/40","sksjdd":"周二 1–2节 · 6-208","sfkxk":"1","status":"0"},
         {"id":"3","kcmc":"机械设计基础","teacher":"示例教师","xf":"3.5","yxrl":"40/40","sksjdd":"周一 3–4节 · 9-112","sfkxk":"1","status":"0"}]
        """)
    }

    private static func decode<T: Decodable>(_ json: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static var schedule: ScheduleBundle {
        func course(_ name: String, _ teacher: String, _ room: String, _ day: Int, _ section: Int) -> ScheduleSlot {
            ScheduleSlot(course: name, teacher: teacher, room: room, weekday: day,
                         startPeriod: section * 2 - 1, endPeriod: section * 2, weeks: Array(1...16))
        }
        var bundle = ScheduleBundle(title: "2026-2027-1", slots: [
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

    static var exams: [ExamItem] {
        guard longList else { return [exam] }
        return (1...18).map { index in
            ExamItem(id: "long-\(index)", kcmc: "示例考试 \(index)", ksrq: exam.ksrq, qssj: exam.qssj,
                     kssj: exam.kssj, jxlmc: exam.jxlmc, jsmc: exam.jsmc, zwh: exam.zwh,
                     ksxs: exam.ksxs, kspcmc: exam.kspcmc, dataXnxq: exam.dataXnxq)
        }
    }
    #endif
}
