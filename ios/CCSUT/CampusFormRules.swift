import Foundation

enum CampusFormPrivacy {
    static func ranges(_ text: String) -> [NSRange] {
        let pattern = #"(?<![0-9])[0-9](?:[ \t-]?[0-9]){10,24}[Xx]?(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }
    static func masked(_ text: String) -> String {
        let result = NSMutableString(string: text)
        for range in ranges(text).reversed() { result.replaceCharacters(in: range, with: String(repeating: "•", count: range.length)) }
        return result as String
    }
}

enum CampusCoordinates {
    /// Forward conversion for the school's GCJ-02 address lookup; Core Location supplies GPS coordinates.
    static func gcj02(latitude lat: Double, longitude lon: Double) -> (latitude: Double, longitude: Double) {
        guard lon >= 72.004, lon <= 137.8347, lat >= 0.8293, lat <= 55.8271 else { return (lat, lon) }
        let x = lon - 105, y = lat - 35, pi = Double.pi
        var dy = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        dy += (20*sin(6*x*pi) + 20*sin(2*x*pi)) * 2/3
        dy += (20*sin(y*pi) + 40*sin(y*pi/3)) * 2/3
        dy += (160*sin(y*pi/12) + 320*sin(y*pi/30)) * 2/3
        var dx = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        dx += (20*sin(6*x*pi) + 20*sin(2*x*pi)) * 2/3
        dx += (20*sin(x*pi) + 40*sin(x*pi/3)) * 2/3
        dx += (150*sin(x*pi/12) + 300*sin(x*pi/30)) * 2/3
        let radians = lat / 180 * pi, magic = 1 - 0.00669342162296594323 * pow(sin(radians), 2)
        dy = dy * 180 / ((6378245 * (1 - 0.00669342162296594323)) / pow(magic, 1.5) * pi)
        dx = dx * 180 / (6378245 / sqrt(magic) * cos(radians) * pi)
        return (lat + dy, lon + dx)
    }
}

enum CampusFormKind: String, Sendable, Identifiable { case leave, departure
    var id: String { rawValue }
    var title: String { self == .leave ? "申请请假" : "离校登记" }
}

enum CampusFormError: Error, LocalizedError, Equatable, Sendable {
    case validation(String), unavailable, invalidResponse, rejected, unknownOutcome, configurationChanged
    var errorDescription: String? {
        switch self {
        case .validation(let field): return CampusPrivacy.redact(field)
        case .unavailable: return "当前暂不能办理，请检查开放类型与学校配置"
        case .invalidResponse: return "学校表单配置无法识别，请稍后重新加载"
        case .rejected: return "学校未接受此次申请，请检查填写内容与现有记录"
        case .unknownOutcome: return "提交结果待确认，请先查询记录，勿重复提交"
        case .configurationChanged: return "学校配置或记录已变化，请刷新配置后重新核对"
        }
    }
}

struct CampusTimeWindow: Sendable, Equatable { let startMinute: Int; let endMinute: Int }
struct CampusFormChoice: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    var requiresImage = false
    var window: CampusTimeWindow?
}
struct CampusApprovers: Sendable, Equatable {
    let roleID: String
    let roleName: String
    let users: [CampusFormChoice]
}
struct CampusFormConfiguration: Sendable, Equatable {
    let kind: CampusFormKind
    let account: String
    let userId: String
    let generation: UInt64
    var displayName = ""
    var phone = ""
    var parentPhone = ""
    var choices: [CampusFormChoice] = []
    var contacts: [CampusFormChoice] = []
    var destinationTypes: [CampusFormChoice] = []
    var needsLocation = false
    var showLocation = false
    var needsDestination = false
    var needsFiles = false
    var canLeaveSchool = true
    var needsLeaveTime = false
    var roleFallback = false
    var photoLimit = 1
    var baselineRecordIDs: Set<String> = []
}

struct CampusAttachment: Identifiable, Sendable, Equatable {
    let id = UUID()
    let name: String
    let mime: String
    let data: Data
    let isImage: Bool
}
struct CampusUploadedFile: Sendable, Equatable { let id: String; let name: String; let isImage: Bool }

struct CampusFormDraft: Sendable, Equatable {
    var typeID = ""
    var begin: Date
    var end: Date
    var reason = ""
    var contactPhone = ""
    var phone = ""
    var parentPhone = ""
    var approverID = ""
    var leaving: Bool?
    var actualLeaveTime: Date?
    var destinationTypeID = ""
    var destinationDetails = ""
    var area: [String] = []
    var detailAddress = ""
    var travelMethod = ""
    var tripNumber = ""
    var locationAddress: String?
    var attachments: [CampusAttachment] = []

    static func days(from start: Date, to end: Date) -> Double {
        let interval = end.timeIntervalSince(start)
        guard interval.isFinite, interval > 0 else { return 0 }
        return ceil(interval / 43_200) / 2
    }
    static func phone(_ value: String) -> String {
        value.filter { !$0.isWhitespace && $0 != "-" }
    }
    static func validPhone(_ value: String) -> Bool {
        let value = phone(value)
        return value.utf8.count == 11 && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    var duration: Double { Self.days(from: begin, to: end) }

    func snapshot(configuration c: CampusFormConfiguration, approvers a: CampusApprovers?) throws -> CampusSubmission {
        func require(_ condition: Bool, _ text: String) throws { if !condition { throw CampusFormError.validation(text) } }
        guard !c.account.isEmpty, !c.userId.isEmpty, let type = c.choices.first(where: { $0.id == typeID }) else {
            throw CampusFormError.validation("请选择当前开放的类型")
        }
        try require(leaving != nil || (c.kind == .leave && !c.canLeaveSchool), "请选择是否离校")
        if c.kind == .leave || leaving == true {
            try require(duration > 0, "结束时间必须晚于开始时间")
        }
        try require(attachments.allSatisfy { !$0.data.isEmpty && $0.data.count <= 20 * 1024 * 1024 }
                    && attachments.reduce(0, { $0 + $1.data.count }) <= 50 * 1024 * 1024,
                    "附件每个最多 20 MiB，合计最多 50 MiB")
        if c.kind == .leave {
            try require(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "请填写请假事由")
            try require(Self.validPhone(contactPhone), "请填写有效的 11 位紧急联系人电话")
            guard let a, !a.roleID.isEmpty, a.users.contains(where: { $0.id == approverID }) else {
                throw CampusFormError.validation("请选择当前有效的审批人")
            }
            if let window = type.window {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
                func minutes(_ date: Date) -> Int { calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date) }
                try require(minutes(begin) > window.startMinute && minutes(end) < window.endMinute,
                            "请假时间不在学校设置的可申请时段内")
            }
            if c.needsLocation { try require(locationAddress?.isEmpty == false, "请先完成学校要求的定位") }
            if c.needsDestination {
                try require(c.destinationTypes.contains(where: { $0.id == destinationTypeID }), "请选择去向类型")
                try require(!destinationDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "请填写去向明细")
            }
            if c.canLeaveSchool && leaving == true && c.needsLeaveTime {
                try require(actualLeaveTime != nil && actualLeaveTime! >= begin && actualLeaveTime! <= end, "请选择请假时段内的离校时间")
            }
            let images = attachments.filter(\.isImage)
            if type.requiresImage { try require(!images.isEmpty, "此类型必须上传证明图片") }
            try require(images.count <= c.photoLimit, "证明图片数量超过学校限制")
            if c.needsFiles { try require(attachments.contains(where: { !$0.isImage }), "请添加学校要求的附件") }
        } else if leaving == true {
            try require(area.count == 3 && area.allSatisfy { !$0.isEmpty }, "请选择目的地省、市、区")
            try require(Self.validPhone(phone) && Self.validPhone(parentPhone), "请填写有效的本人及家长联系电话")
            try require(travelMethod.isEmpty || ["飞机", "火车", "汽车", "步行", "骑行"].contains(travelMethod), "请选择有效交通方式")
        }
        return CampusSubmission(kind: c.kind, configuration: c, draft: self, approvers: a)
    }
}

struct CampusSubmission: Identifiable, Sendable, Equatable {
    let id = UUID()
    let createdAt = Date()
    let kind: CampusFormKind
    let configuration: CampusFormConfiguration
    let draft: CampusFormDraft
    let approvers: CampusApprovers?

    static func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
    func payload(uploaded: [CampusUploadedFile]) throws -> [String: Any] {
        guard uploaded.count == draft.attachments.count else { throw CampusFormError.invalidResponse }
        let c = configuration, d = draft
        if kind == .departure {
            var values: [String: Any] = ["openid": NSNull(), "status": NSNull(), "studentId": c.userId,
                "type": d.typeID, "isLeave": d.leaving == true ? "是" : "否",
                "phone": CampusFormDraft.phone(d.phone), "jzPhone": CampusFormDraft.phone(d.parentPhone)]
            for field in ["reason", "jtgj", "tjcs", "xxdz", "txdz", "startDate", "endDate"] { values[field] = NSNull() }
            if d.leaving == true {
                values["reason"] = d.reason; values["jtgj"] = d.travelMethod; values["tjcs"] = d.tripNumber
                values["xxdz"] = d.detailAddress; values["txdz"] = d.area.joined(separator: "-")
                values["startDate"] = Self.date(d.begin); values["endDate"] = Self.date(d.end)
            }
            return values
        }
        let images = uploaded.filter(\.isImage).map { ["fileId": $0.id, "fileName": $0.name] }
        let documents = uploaded.filter { !$0.isImage }.map { ["fileId": $0.id, "fileName": $0.name] }
        let fileJSON = try JSONSerialization.data(withJSONObject: documents, options: .sortedKeys)
        return ["applyUserId": c.userId, "applyUserName": c.displayName, "applyUserAccount": c.account,
            "applyUserDept": "", "applyUserClass": "", "leaveType": d.typeID,
            "leaveTypeName": c.choices.first(where: { $0.id == d.typeID })?.name ?? "",
            "leaveSchool": c.canLeaveSchool && d.leaving == true ? "0" : "1",
            "beginTime": Self.date(d.begin), "endTime": Self.date(d.end), "leaveDay": d.duration,
            "leaveTime": c.canLeaveSchool && d.leaving == true && c.needsLeaveTime ? d.actualLeaveTime.map(Self.date) ?? "" : "",
            "qxlx": c.needsDestination ? d.destinationTypeID : "", "qxmx": c.needsDestination ? d.destinationDetails : "",
            "reason": d.reason, "linkmanPhone": CampusFormDraft.phone(d.contactPhone),
            "approver": d.approverID, "roleId": approvers?.roleID ?? "",
            "address": c.needsLocation ? d.locationAddress ?? "" : "", "applyFiles": images,
            "fileList": c.needsFiles ? String(data: fileJSON, encoding: .utf8)! : ""]
    }
}
