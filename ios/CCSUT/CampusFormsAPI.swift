import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol CampusFormServing: Sendable {
    func loadForm(_ kind: CampusFormKind) async throws -> CampusFormConfiguration
    func approvers(type: String, days: Double) async throws -> CampusApprovers
    func roleUsers(_ role: CampusApprovers) async throws -> CampusApprovers
    func locate(latitude: Double, longitude: Double) async throws -> String
    func submit(_ submission: CampusSubmission) async throws
    func reconcile(_ submission: CampusSubmission) async throws -> Bool
}

extension CampusClient: CampusFormServing {
    private func formIdentity(_ kind: CampusFormKind, force: Bool = false) async throws -> Identity {
        try await identity(for: kind == .leave ? .leave : .travel,
                           callback: kind == .leave ? Self.leavePage : CampusTravelKind.departure.page, force: force)
    }
    private func formRead(_ kind: CampusFormKind, path: String,
                          json: ((String) -> [String: Any])? = nil, fields: [String: String]? = nil,
                          query: [URLQueryItem] = []) async throws -> Data {
        for attempt in 0...1 {
            let identity = try await formIdentity(kind, force: attempt == 1)
            var req = request(path, query: query)
            req.setValue(identity.authorization, forHTTPHeaderField: "Authorization")
            if let fields {
                let multipart = CampusMultipart(fields: fields)
                req.httpMethod = "POST"; req.httpBody = multipart.body
                req.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
            } else if let json {
                req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: json(identity.userId))
                req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            }
            do { return try await send(req).0 }
            catch Failure.unauthorized { if attempt == 1 { throw CampusError.authentication } }
        }
        throw CampusError.authentication
    }

    func loadForm(_ kind: CampusFormKind) async throws -> CampusFormConfiguration {
        let identity = try await formIdentity(kind)
        var c = CampusFormConfiguration(kind: kind, account: account, userId: identity.userId, generation: generation)
        c.displayName = identity.realName ?? ""
        if kind == .leave {
            guard !c.displayName.isEmpty else { throw CampusFormError.invalidResponse }
            let keys = ["leave_address_config", "leaveApplyDateCheck", "leave_date_title", "leave_date_content", "fileNum",
                        "dataAddressShow", "leave_qxlx_config", "leaveSchoolTimeSelect", "linkmanPhone", "leaveadminApplyPowerUser",
                        "leaveadmin_show_files", "leaveadmin_userExtra", "leaveadmin_sflx"]
            let configs = try Self.formArray(formReadData: await formRead(kind, path: "/backstage/baseinfo/sysConfig/querySysConfigItems", json: { _ in ["configKeys": keys] }))
            var values: [String: String] = [:]
            for item in configs {
                guard let key = item["configKey"] as? String, let value = item["configContent"] as? String else { continue }
                values[key] = value
            }
            func flag(_ key: String, fallback: Bool = false) throws -> Bool {
                guard let value = values[key] else { return fallback }
                guard ["显示", "隐藏"].contains(value) else { throw CampusFormError.invalidResponse }
                return value == "显示"
            }
            c.needsLocation = try flag("leave_address_config")
            c.showLocation = try flag("dataAddressShow") || c.needsLocation
            c.needsDestination = try flag("leave_qxlx_config")
            c.needsFiles = try flag("leaveadmin_show_files")
            c.canLeaveSchool = try flag("leaveadmin_sflx", fallback: true)
            c.needsLeaveTime = try flag("leaveSchoolTimeSelect")
            c.roleFallback = try !flag("leaveadminApplyPowerUser")
            if let count = values["fileNum"] { guard let count = Int(count), (1...100).contains(count) else { throw CampusFormError.invalidResponse }; c.photoLimit = count }
            for page in 1...50 {
                let data = try await formRead(kind, path: "/backstage/leaveadmin/LeaveType/queryListForPage", json: {
                    ["pageNum": page, "pageSize": 100, "pageParam": ["typeName": NSNull(), "studentId": $0, "power": true]]
                })
                let list = try Self.formDictionary(data)
                guard let rows = list["list"] as? [[String: Any]] else { throw CampusFormError.invalidResponse }
                for row in rows where Self.integer(row["enableStatus"]) == 0 {
                    guard let id = Self.text(row["id"]), let name = Self.text(row["name"]),
                          let upload = Self.integer(row["isUploadFile"]), [0,1].contains(upload) else { throw CampusFormError.invalidResponse }
                    var option = CampusFormChoice(id: id, name: name, requiresImage: upload == 0)
                    if Self.integer(row["timeConfig"]) == 1 {
                        guard let start = Self.minute(row["timeConfigStartTime"]), let end = Self.minute(row["timeConfigEndTime"]), end > start else { throw CampusFormError.invalidResponse }
                        option.window = CampusTimeWindow(startMinute: start, endMinute: end)
                    }
                    c.choices.append(option)
                }
                if !Self.morePages(list, count: rows.count, page: page) { break }
                if page == 50 { throw CampusFormError.invalidResponse }
            }
            let student = try Self.formDictionary(await formRead(kind, path: "/backstage/baseinfo/studentInfo/queryStudentById", json: { ["studentId": $0] }))
            c.parentPhone = student["jtdh"] as? String ?? ""
            let family = try Self.formArray(formReadData: await formRead(kind, path: "/backstage/baseinfo/studentFamily/queryByid", json: { ["studentId": $0] }))
            c.contacts = family.compactMap { item in
                guard let phone = Self.text(item["mobile"]) else { return nil }
                return .init(id: phone, name: (item["name"] as? String ?? "联系人") + " " + CampusPrivacy.redact(phone))
            }
            if c.needsDestination {
                let rows = try Self.formArray(formReadData: await formRead(kind, path: "/backstage/baseinfo/common/queryAreaLabel", json: { _ in ["level": 2] }))
                c.destinationTypes = try rows.map { row in
                    guard let id = Self.text(row["value"]), let name = Self.text(row["label"]) else { throw CampusFormError.invalidResponse }
                    return .init(id: id, name: name)
                }
            }
        } else {
            for page in 1...50 {
                let list = try Self.formDictionary(await formRead(kind, path: "/backstage/returnschool/leaveType/page", json: { _ in
                    ["name": NSNull(), "status": "是", "pageNum": page, "pageSize": 100]
                }))
                guard let rows = list["records"] as? [[String: Any]] else { throw CampusFormError.invalidResponse }
                c.choices += try rows.map { row in
                    guard let id = Self.text(row["openid"]), let name = Self.text(row["name"]) else { throw CampusFormError.invalidResponse }
                    return .init(id: id, name: name)
                }
                if !Self.morePages(list, count: rows.count, page: page) { break }
                if page == 50 { throw CampusFormError.invalidResponse }
            }
            let student = try Self.formDictionary(await formRead(kind, path: "/backstage/returnschool/studentGqleave/queryStudentInfo", json: { ["studentId": $0] }))
            c.displayName = student["xm"] as? String ?? c.displayName
            c.phone = student["phone"] as? String ?? ""; c.parentPhone = student["jzPhone"] as? String ?? ""
        }
        guard Set(c.choices.map(\.id)).count == c.choices.count else { throw CampusFormError.invalidResponse }
        c.baselineRecordIDs = Set(try await formRecords(kind).compactMap { Self.text($0[kind == .leave ? "id" : "openid"]) })
        try checkState()
        return c
    }

    func approvers(type: String, days: Double) async throws -> CampusApprovers {
        guard !type.isEmpty, days.isFinite, days > 0 else { throw CampusFormError.validation("请先选择类型和有效时间") }
        let result = try Self.formDictionary(await formRead(.leave, path: "/backstage/leaveadmin/leaveTask/getFirstRoleUsers",
                                                          fields: ["leaveDay": String(days), "leaveTypeId": type, "realName": ""]))
        guard let role = Self.text(result["roleId"]), let rows = result["users"] as? [[String: Any]] else { throw CampusFormError.unavailable }
        return CampusApprovers(roleID: role, roleName: result["roleName"] as? String ?? "审批人", users: try Self.users(rows))
    }

    func locate(latitude: Double, longitude: Double) async throws -> String {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { throw CampusFormError.validation("定位坐标无效") }
        let result = try Self.formDictionary(await formRead(.leave, path: "/backstage/app-manager/platformData/geocoder", query: [
            .init(name: "geoType", value: "gcj02"), .init(name: "lat", value: String(latitude)), .init(name: "lon", value: String(longitude))]))
        guard let address = Self.text(result["formattedAddress"]) else { throw CampusFormError.validation("学校暂时无法解析定位地址") }
        return address
    }

    func submit(_ submission: CampusSubmission) async throws {
        try checkState()
        guard submission.configuration.account == account, submission.configuration.generation == generation,
              formAttemptIDs.insert(submission.id).inserted else { throw CampusFormError.validation("此确认已使用，请重新核对表单") }
        let fresh = try await loadForm(submission.kind)
        guard fresh == submission.configuration else { throw CampusFormError.validation("学校配置或记录已变化，请重新加载后核对") }
        _ = try submission.draft.snapshot(configuration: fresh, approvers: submission.approvers)
        if submission.kind == .leave {
            var reviewers = try await approvers(type: submission.draft.typeID, days: submission.draft.duration)
            if fresh.roleFallback { reviewers = try await roleUsers(reviewers) }
            guard reviewers.roleID == submission.approvers?.roleID,
                  reviewers.users.contains(where: { $0.id == submission.draft.approverID }) else {
                throw CampusFormError.validation("审批规则已变化，请重新选择审批人")
            }
        }
        let identity = try await formIdentity(submission.kind)
        guard identity.userId == fresh.userId else { throw CampusError.identityMismatch }
        var files: [CampusUploadedFile] = []
        for attachment in submission.draft.attachments {
            do { files.append(try await upload(attachment, identity: identity)) }
            catch is CancellationError { throw CancellationError() }
            catch { throw CampusFormError.validation("附件上传未完成，申请尚未提交，请重新核对") }
        }
        let body = try JSONSerialization.data(withJSONObject: submission.payload(uploaded: files), options: .sortedKeys)
        let path = submission.kind == .leave ? "/backstage/leaveadmin/leaveApply/submitLeaveApply" : "/backstage/returnschool/studentGqleave/applyGqleave"
        let data = try await formWrite(path, body: body, contentType: "application/json;charset=UTF-8", identity: identity)
        try Self.confirmWrite(data, kind: submission.kind)
    }

    func roleUsers(_ role: CampusApprovers) async throws -> CampusApprovers {
        guard !role.roleID.contains("/"), !role.roleID.contains("?"), !role.roleID.contains("#") else { throw CampusFormError.invalidResponse }
        let rows = try Self.formArray(formReadData: await formRead(.leave, path: "/backstage/auth/baserole/users/" + role.roleID))
        return CampusApprovers(roleID: role.roleID, roleName: role.roleName, users: try Self.users(rows))
    }

    private func upload(_ file: CampusAttachment, identity: Identity) async throws -> CampusUploadedFile {
        let multipart: CampusMultipart
        let path: String
        if file.isImage {
            multipart = CampusMultipart(fields: ["file": "data:\(file.mime);base64," + file.data.base64EncodedString(), "name": "zmcl.png"])
            path = "/backstage/filecenter/file/base64"
        } else {
            multipart = CampusMultipart(fields: [:], file: file)
            path = "/backstage/filecenter/file"
        }
        let result = try Self.formDictionary(await formWrite(path, body: multipart.body, contentType: multipart.contentType, identity: identity))
        guard let id = Self.text(result["id"]), let name = Self.text(result["filename"]) else { throw CampusFormError.invalidResponse }
        return .init(id: id, name: name, isImage: file.isImage)
    }

    /// Intentionally separate from retrying reads. A write has exactly one network attempt.
    private func formWrite(_ path: String, body: Data, contentType: String, identity: Identity) async throws -> Data {
        try checkState()
        var req = request(path); req.httpMethod = "POST"; req.httpBody = body; req.httpShouldHandleCookies = false
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue(identity.authorization, forHTTPHeaderField: "Authorization")
        req.setValue(try credentials.header(for: req.url!, expectedGeneration: generation), forHTTPHeaderField: "Cookie")
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.data(for: req) }
        catch { try checkState(); throw CampusFormError.unknownOutcome }
        try checkState()
        if let fields = response.allHeaderFields as? [String: String] {
            credentials.accept(HTTPCookie.cookies(withResponseHeaderFields: fields, for: req.url!), generation: generation)
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw CampusError.authentication
        case 403: throw CampusError.forbidden
        case 400, 404, 409, 422: throw CampusFormError.rejected
        default: throw CampusFormError.unknownOutcome
        }
    }

    func reconcile(_ submission: CampusSubmission) async throws -> Bool {
        try checkState()
        guard submission.configuration.generation == generation, submission.configuration.account == account else { throw CancellationError() }
        let rows = try await formRecords(submission.kind)
        let d = submission.draft, c = submission.configuration
        let matching = rows.filter { row in
            guard let id = Self.text(row[submission.kind == .leave ? "id" : "openid"]), !c.baselineRecordIDs.contains(id),
                  let time = Self.parseDate(row[submission.kind == .leave ? "applyTime" : "applyDate"] as? String),
                  time >= submission.createdAt.addingTimeInterval(-2) else { return false }
            if submission.kind == .leave {
                return row["leaveType"] as? String == d.typeID && row["reason"] as? String == d.reason
                    && Self.sameTime(row["beginTime"], d.begin) && Self.sameTime(row["endTime"], d.end)
            }
            guard row["type"] as? String == d.typeID, row["isLeave"] as? String == (d.leaving == true ? "是" : "否") else { return false }
            return d.leaving != true || (Self.sameTime(row["startDate"], d.begin) && Self.sameTime(row["endDate"], d.end)
                && row["txdz"] as? String == d.area.joined(separator: "-") && row["phone"] as? String == CampusFormDraft.phone(d.phone))
        }
        return matching.count == 1
    }

    private func formRecords(_ kind: CampusFormKind) async throws -> [[String: Any]] {
        if kind == .leave {
            let page = try Self.formDictionary(await formRead(kind, path: "/backstage/leaveadmin/leaveApply/queryListForPage", json: {
                ["pageNum": 1, "pageSize": 100, "pageParam": ["userId": $0]]
            }))
            guard let rows = page["list"] as? [[String: Any]] else { throw CampusFormError.invalidResponse }; return rows
        }
        return try Self.formArray(formReadData: await formRead(kind, path: "/backstage/returnschool/studentGqleave/queryStuGqleaveInfo", json: { ["studentId": $0] }))
    }

    private static func root(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CampusFormError.invalidResponse }
        if let error = root["errorMessage"] as? String, !error.isEmpty { throw CampusFormError.rejected }
        if root["success"] as? Bool == false { throw CampusFormError.rejected }
        if let value = root["code"], !(value is NSNull) {
            guard let code = integer(value) else { throw CampusFormError.invalidResponse }
            if code == 401 { throw CampusError.authentication }
            if code == 403 { throw CampusError.forbidden }
            guard [200,2000].contains(code) else { throw CampusFormError.rejected }
        }
        return root
    }
    private static func formDictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try root(data)["data"] as? [String: Any] else { throw CampusFormError.invalidResponse }; return value
    }
    private static func formArray(formReadData data: Data) throws -> [[String: Any]] {
        guard let value = try root(data)["data"] as? [[String: Any]] else { throw CampusFormError.invalidResponse }; return value
    }
    private static func confirmWrite(_ data: Data, kind: CampusFormKind) throws {
        let value: [String: Any]
        do { value = try root(data) }
        catch let error as CampusFormError where error == .invalidResponse { throw CampusFormError.unknownOutcome }
        let code = integer(value["code"])
        if [200,2000].contains(code ?? 0) { return }
        if kind == .leave, let text = value["message"] as? String,
           ["success","提交成功","申请成功","操作成功","保存成功","请假申请成功","请假成功"].contains(text.trimmingCharacters(in: CharacterSet(charactersIn: " !！。\n\r"))) { return }
        throw CampusFormError.unknownOutcome
    }
    private static func users(_ rows: [[String: Any]]) throws -> [CampusFormChoice] {
        try rows.map { row in
            guard let id = text(row["userId"]), let name = text(row["userName"]) ?? text(row["realName"]) else { throw CampusFormError.invalidResponse }
            return .init(id: id, name: name)
        }
    }
    private static func text(_ value: Any?) -> String? { guard let s = value as? String, !s.isEmpty else { return nil }; return s }
    private static func integer(_ value: Any?) -> Int? { if let n = value as? Int { return n }; return (value as? String).flatMap(Int.init) }
    private static func morePages(_ value: [String: Any], count: Int, page: Int) -> Bool {
        if let hasNext = value["hasNextPage"] as? Bool { return hasNext }
        if let total = integer(value["total"]) { return page * 100 < total }
        if let pages = integer(value["pages"]) { return page < pages }
        return count == 100
    }
    private static func minute(_ raw: Any?) -> Int? {
        guard let text = raw as? String else { return nil }
        if let date = parseDate(text) {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
        let parts = text.split(separator: ":"); guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }; iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            format.dateFormat = pattern; if let date = format.date(from: value) { return date }
        }
        return nil
    }
    private static func sameTime(_ value: Any?, _ expected: Date) -> Bool {
        guard let date = parseDate(value as? String) else { return false }; return abs(date.timeIntervalSince(expected)) < 1
    }
}

private struct CampusMultipart {
    let body: Data
    let contentType: String
    init(fields: [String: String], file: CampusAttachment? = nil) {
        let boundary = "CCSUT-" + UUID().uuidString
        contentType = "multipart/form-data; boundary=" + boundary
        var data = Data()
        func append(_ text: String) { data.append(Data(text.utf8)) }
        for key in fields.keys.sorted() {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key]!)\r\n")
        }
        if let file {
            let name = file.name.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(file.mime)\r\n\r\n")
            data.append(file.data); append("\r\n")
        }
        append("--\(boundary)--\r\n"); body = data
    }
}
