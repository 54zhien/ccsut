//
//  Models.swift
//  CCSUT
//
//  数据结构全部按实测响应定义（2026-10-22 抓包）
//

import Foundation

// MARK: - 统一响应壳

/// 所有 /admin/** 接口都返回 {"ret":0,"msg":"success","data":...}
struct APIEnvelope<T: Decodable>: Decodable {
    let ret: Int
    let msg: String?
    let data: T?
}

// MARK: - 字典项

/// kcgsList / kclxList / kcxzList / jxmsList / kkxqList 的统一形状
struct DictItem: Decodable, Identifiable, Hashable {
    let id: String?
    let dictname: String?
    let dictcode: String?
    let sort: Int?

    var uid: String { id ?? dictcode ?? dictname ?? UUID().uuidString }
    var name: String { dictname ?? dictcode ?? "—" }
}

// MARK: - 选课页初始化（/admin/xsd/xk/listV2）

struct ElectiveInit: Decodable {
    let xsxm: String?          // 学生姓名
    let xsxh: String?          // 学号
    let xkxnxq: String?        // 选课学期，如 2026-2027-1
    let dbname: String?
    let cxxkwkcts: String?     // "暂无课程"
    let sfwjxb: Bool?
    let pcencs: [String: String]?   // 选课批次 id → 加密串

    let kcgsList: [DictItem]?  // 课程归属
    let kclxList: [DictItem]?  // 课程类型
    let kcxzList: [DictItem]?  // 课程性质
    let jxmsList: [DictItem]?  // 教学方式
    let kkxqList: [DictItem]?  // 开课校区
    let mapsList: [DictItem]?
}

// MARK: - 教学班（/admin/xsd/xk/listjxbDataV2 的 initData）

struct TeachingClass: Decodable, Identifiable, Hashable {
    let id: String
    let jxbmc: String?       // 教学班名称（含课程+性质+序号）
    let kcmc: String?        // 课程名称
    let kcid: String?        // 课程代码
    let kcbh: String?        // 课程编号
    let teacher: String?     // 教师
    let xf: String?          // 学分
    let kclb: String?
    let kclbname: String?    // 通识教育课程 …
    let kclx: String?        // 理论课程
    let kcxz: String?        // 课程性质
    let kcgs: String?        // 课程归属
    let jxms: String?        // 教学方式
    let yxrl: String?        // 已选/容量，如 "40/40"
    let bjrs: String?        // 班级人数
    let sksjdd: String?      // 上课时间地点（人类可读）
    let sksjddstr: String?   // 上课时间编码，如 "8403,9403"
    let kkxqmc: String?      // 校区
    let sfkxk: String?       // "1" 可选
    let ksxs: String?        // 考核方式
    let bz: String?          // 备注

    var creditValue: Double { Double(xf ?? "") ?? 0 }

    var enrolled: Int {
        Int((yxrl ?? "").split(separator: "/").first ?? "") ?? 0
    }

    var capacity: Int {
        Int((yxrl ?? "").split(separator: "/").last ?? "") ?? 0
    }

    var isFull: Bool { capacity > 0 && enrolled >= capacity }

    var canSelect: Bool { sfkxk == "1" && !isFull }

    var fillRatio: Double {
        guard capacity > 0 else { return 0 }
        return min(1, Double(enrolled) / Double(capacity))
    }
}

struct TeachingClassPage: Decodable {
    let mysksjd: [String]?
    let initData: [TeachingClass]?
    let kfrlbfb: Int?
    let condition: ClassCondition?

    struct ClassCondition: Decodable {
        let jxms: String?
        let kclx: String?
        let kcgs: String?
        let kcxz: String?
        let kkxq: String?
        let kclb: String?
    }
}

// MARK: - 课表

/// 从课表 HTML 解析出来的一个格子
struct ScheduleSlot: Identifiable, Hashable {
    let id = UUID()
    let course: String
    let teacher: String
    let room: String
    let weekday: Int        // 1 = 周一 … 7 = 周日
    let startPeriod: Int
    let endPeriod: Int
    let weeks: [Int]

    /// 该格子在网格里的行（节次）跨度
    var periodSpan: Int { max(1, endPeriod - startPeriod + 1) }
}

/// 课表接口（/admin/xsd/pkgl/xskb/sdpkkbList）返回的一条记录
struct ScheduleItem: Decodable {
    let kcmc: String?      // 课程名（含 <a> 标签）
    let tmc: String?       // 教师
    let croommc: String?   // 教室
    let zc: String?        // 周次，如 "1-4,6-11"
    let xingqi: Int?       // 星期 1-7
    let djc: Int?          // 第几大节 1-8
    let ksxs: String?      // 考核方式
    let kcxz: String?      // 课程性质
    let jsxq: String?      // 校区
    let xf: String?        // 学分
    let jxbzc: String?     // 教学班组成
    let croombh: String?   // 教室编号

    var slot: ScheduleSlot {
        let p = djc ?? 1
        return ScheduleSlot(
            course: (kcmc ?? "").strippingHTML,
            teacher: (tmc ?? "").strippingHTML,
            room: (croommc ?? "").strippingHTML,
            weekday: min(7, max(1, xingqi ?? 1)),
            startPeriod: p,
            endPeriod: p,
            weeks: WeekParser.parse(zc ?? "")
        )
    }
}

/// 课表页信息
struct ScheduleBundle {
    var title: String = ""
    var slots: [ScheduleSlot] = []
    var periods: [Int] = Array(1...12)

    var isEmpty: Bool { slots.isEmpty }
}

// MARK: - sksjddstr 解码

/// 教学班的 sksjddstr 形如 "8403,9403,10403,8404,9404"
/// 编码规则：{周次}{星期}{节次两位}，星期固定 1 位，节次固定 2 位
enum ScheduleCodec {
    struct Decoded {
        var weekday: Int
        var period: Int
        var week: Int
    }

    static func decode(_ raw: String) -> [Decoded] {
        raw.split(separator: ",").compactMap { token in
            let s = token.trimmingCharacters(in: .whitespaces)
            guard s.count >= 4, let digits = Int(s) else { return nil }
            _ = digits
            // 末 3 位 = 星期(1) + 节次(2)，前面是周次
            let chars = Array(s)
            guard let period = Int(String(chars[(chars.count - 2)...])),
                  let weekday = Int(String(chars[chars.count - 3])),
                  let week = Int(String(chars[..<(chars.count - 3)]))
            else { return nil }
            guard (1...7).contains(weekday), (1...20).contains(period), week > 0 else { return nil }
            return Decoded(weekday: weekday, period: period, week: week)
        }
    }

    /// 把编码串压缩成"周四 3-4节 第8-15周"
    static func humanize(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let items = decode(raw)
        guard !items.isEmpty else { return raw }

        // 按 (星期, 节次) 分组，合并连续周次
        var buckets: [String: (weekday: Int, period: Int, weeks: Set<Int>)] = [:]
        for it in items {
            let k = "\(it.weekday)-\(it.period)"
            var b = buckets[k] ?? (it.weekday, it.period, [])
            b.weeks.insert(it.week)
            buckets[k] = b
        }

        let weekdayNames = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return buckets.values
            .sorted { ($0.weekday, $0.period) < ($1.weekday, $1.period) }
            .map { b in
                let weeks = compress(Array(b.weeks).sorted())
                return "\(weekdayNames[b.weekday]) 第\(b.period)节 周次\(weeks)"
            }
            .joined(separator: "；")
    }

    /// [8,9,10,11,12,13,14,15] → "8-15"
    static func compress(_ weeks: [Int]) -> String {
        guard !weeks.isEmpty else { return "" }
        var parts: [String] = []
        var start = weeks[0]
        var prev = weeks[0]

        for w in weeks.dropFirst() {
            if w == prev + 1 {
                prev = w
            } else {
                parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
                start = w
                prev = w
            }
        }
        parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
        return parts.joined(separator: ",")
    }
}


// MARK: - HTML 剥离

extension String {
    /// 课表接口里的字段都包了一层 <a href="javascript:...">
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 周次解析

enum WeekParser {
    /// "1-4,6-11" → [1,2,3,4,6,7,8,9,10,11]
    /// "1-3,5-7,9-9,11-11" → 单双周也在这里展开
    static func parse(_ raw: String) -> [Int] {
        var set = Set<Int>()
        for part in raw.split(separator: ",") {
            let p = part.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { continue }
            if p.contains("-") {
                let nums = p.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if nums.count == 2, nums[0] <= nums[1], nums[1] - nums[0] < 60 {
                    set.formUnion(nums[0]...nums[1])
                }
            } else if let n = Int(p), n > 0 {
                set.insert(n)
            }
        }
        return set.sorted()
    }

    /// "1-4,6-11" → "1-4,6-11"（保留原样，只做校验）
    static func describe(_ raw: String) -> String {
        let weeks = parse(raw)
        guard !weeks.isEmpty else { return raw }
        return compress(weeks)
    }

    static func compress(_ weeks: [Int]) -> String {
        guard !weeks.isEmpty else { return "" }
        var parts: [String] = []
        var start = weeks[0], prev = weeks[0]
        for w in weeks.dropFirst() {
            if w == prev + 1 { prev = w }
            else {
                parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
                start = w; prev = w
            }
        }
        parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
        return parts.joined(separator: ",")
    }
}
