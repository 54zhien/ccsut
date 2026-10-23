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
    let status: String?      // "1" = 已选
    let bmzt: String?        // 报名状态
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

    /// 已选（退课按钮能点的那些）
    var isSelected: Bool { status == "1" }

    var fillRatio: Double {
        guard capacity > 0 else { return 0 }
        return min(1, Double(enrolled) / Double(capacity))
    }
}

/// POST /admin/xsd/xk/listjxbDataV2 的响应
///
/// 只声明真正用到的两个字段。
/// 服务端返回的另外两个字段类型和直觉不符，解析它们会让整个结构解码失败：
///   "kfrlbfb": "100"                              ← 字符串，不是数字
///   "condition": { "jxms": ["中文教学"], ... }     ← 值是数组，不是字符串
/// Decodable 会忽略未声明的键，所以不写它们最省事。
struct TeachingClassPage: Decodable {
    let mysksjd: [String]?
    let initData: [TeachingClass]?
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

    /// 学校按「2 小节 = 1 大节」排课：djc 1,2 → 第1大节 …
    var bigSection: Int { max(1, min(4, (startPeriod + 1) / 2)) }
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


// MARK: - 成绩

/// GET /admin/ydd/inf/getXscjJson?xnxq=111  （111 = 全部学期）
struct ScoreItem: Decodable, Identifiable, Hashable {
    let id: String?
    let kcmc: String?      // "[01BJ001]画法几何"
    let kcbh: String?
    let xf: String?        // 学分
    let zhcj: String?      // 总成绩，可能是 "85" / "67.6" / "良"
    let jd: Double?        // 绩点
    let cjfxms: String?    // 平时(40%):91,期末(60%):80
    let kcxz: String?      // 课程性质
    let xnxq: String?
    let sfjg: String?      // "1" 及格

    /// 去掉 "[01BJ001]" 前缀
    var courseName: String {
        guard let k = kcmc, !k.isEmpty else { return "" }
        if let close = k.firstIndex(of: "]") {
            return String(k[k.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return k
    }

    var credit: Double { Double(xf ?? "") ?? 0 }
    var point: Double { jd ?? 0 }
    var passed: Bool { sfjg == "1" }
    var scoreText: String { (zhcj?.isEmpty == false) ? zhcj! : "—" }

    /// 成绩分项拆成可读的键值对
    var breakdown: [(String, String)] {
        guard let raw = cjfxms, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { part in
            let s = String(part)
            guard let colon = s.firstIndex(of: ":") else { return nil }
            let key = String(s[s.startIndex..<colon])
            let val = String(s[s.index(after: colon)...])
            guard !val.isEmpty, val != "0" else { return nil }
            return (key, val)
        }
    }
}

/// 一个学期的汇总
struct ScoreTerm: Identifiable {
    let name: String
    let items: [ScoreItem]

    var id: String { name }
    var credits: Double { items.reduce(0) { $0 + $1.credit } }

    /// 加权平均绩点
    var gpa: Double {
        let weighted = items.reduce(0.0) { $0 + $1.point * $1.credit }
        let total = credits
        return total > 0 ? weighted / total : 0
    }

    var failedCount: Int { items.filter { !$0.passed }.count }
}
