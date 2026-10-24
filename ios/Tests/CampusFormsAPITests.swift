import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FormCredentials: CampusSessionCredentials, @unchecked Sendable {
    private let lock = NSLock(); private var revision: UInt64 = 1
    var generation: UInt64 { lock.lock(); defer { lock.unlock() }; return revision }
    func change() { lock.lock(); revision += 1; lock.unlock() }
    func header(for url: URL, expectedGeneration: UInt64) throws -> String? {
        guard expectedGeneration == generation else { throw CancellationError() }; return "fixture=session"
    }
    func accept(_ cookies: [HTTPCookie], generation: UInt64) {}
}
actor FormTransport: CampusTransport {
    let override: @Sendable (URLRequest, Int) throws -> (Int, String)?
    var requests: [URLRequest] = []
    init(_ override: @escaping @Sendable (URLRequest, Int) throws -> (Int, String)? = {_,_ in nil}) { self.override = override }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url!.path
        let result = try override(request, requests.filter { $0.url!.path == path }.count) ?? Self.reply(path)
        return (Data(result.1.utf8), HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: nil, headerFields: [:])!)
    }
    static func reply(_ path: String) -> (Int,String) {
        if path.hasSuffix("validate_full") { return (200,#"{"errcode":2000,"account":"fixture-account","userId":"fixture-user","realName":"示例学生","data":{"access_token":"fixture-token","token_type":"bearer"}}"#) }
        if path.hasSuffix("querySysConfigItems") { return (200,#"{"message":"success","data":[{"configKey":"leaveadminApplyPowerUser","configContent":"显示"}]}"#) }
        if path.contains("LeaveType/") { return (200,#"{"data":{"list":[{"id":"sick","name":"病假","enableStatus":0,"isUploadFile":1}],"hasNextPage":false}}"#) }
        if path.hasSuffix("leaveType/page") { return (200,#"{"data":{"records":[{"openid":"holiday","name":"示例假期"}],"total":1}}"#) }
        if path.hasSuffix("studentInfo/queryStudentById") { return (200,#"{"data":{"jtdh":"18000000001","sfzh":"private-unneeded-field"}}"#) }
        if path.hasSuffix("studentFamily/queryByid") { return (200,#"{"data":[{"name":"家长","mobile":"18000000001"}]}"#) }
        if path.hasSuffix("queryAreaLabel") { return (200,#"{"data":[{"value":"home","label":"回家"}]}"#) }
        if path.hasSuffix("getFirstRoleUsers") { return (200,#"{"data":{"roleId":"role","roleName":"辅导员","users":[{"userId":"teacher","userName":"示例审批人"}]}}"#) }
        if path.hasSuffix("queryListForPage") { return (200,#"{"data":{"list":[],"hasNextPage":false,"pageNum":1,"pageSize":100,"total":0}}"#) }
        if path.hasSuffix("queryStuGqleaveInfo") { return (200,#"{"code":"2000","data":[]}"#) }
        if path.hasSuffix("queryStudentInfo") { return (200,#"{"data":{"xm":"示例学生","phone":"18000000000","jzPhone":"18000000001","sfzh":"private-unneeded-field"}}"#) }
        if path.contains("filecenter/file") { return (200,#"{"data":{"id":"uploaded-file","filename":"证明.png"}}"#) }
        if path.hasSuffix("applyGqleave") { return (200,#"{"code":"2000","msg":"成功"}"#) }
        if path.hasSuffix("submitLeaveApply") { return (200,#"{"message":"提交成功","errorMessage":null}"#) }
        return (200,#"{"data":{"formattedAddress":"示例地址"}}"#)
    }
}

@main struct CampusFormsAPITests {
    static func main() async throws {
        var failures = 0
        func check(_ ok: Bool, _ name: String) { print("\(ok ? "PASS" : "FAIL") \(name)"); if !ok { failures += 1 } }
        let credentials = FormCredentials(), transport = FormTransport()
        let client = CampusClient(account: "fixture-account", credentials: credentials, transport: transport)
        let config = try await client.loadForm(.leave)
        check(config.choices.map(\.id) == ["sick"] && config.parentPhone == "18000000001", "form loads verified choices and minimal masked-contact source")
        let role = try await client.approvers(type: "sick", days: 0.5)
        var draft = CampusFormDraft(begin: Date(), end: Date().addingTimeInterval(3600))
        draft.typeID = "sick"; draft.contactPhone = "18000000001"; draft.reason = "示例事由"; draft.approverID = "teacher"; draft.leaving = false
        let submission = try draft.snapshot(configuration: config, approvers: role)
        try await client.submit(submission)
        let requests = await transport.requests
        let writes = requests.filter { $0.url!.path.hasSuffix("submitLeaveApply") }
        check(writes.count == 1, "explicit confirmation issues a single leave mutation")
        let body = try JSONSerialization.jsonObject(with: writes[0].httpBody!) as! [String: Any]
        check(body["applyUserId"] as? String == "fixture-user" && body["approver"] as? String == "teacher", "submission uses validated identity and selected eligible reviewer")
        let multipart = requests.first { $0.url!.path.hasSuffix("getFirstRoleUsers") }!
        check(multipart.value(forHTTPHeaderField: "Content-Type")!.contains("multipart/form-data") && String(data: multipart.httpBody!, encoding: .utf8)!.contains("leaveTypeId"), "approvers use official multipart encoding")
        check(requests.filter { !$0.url!.path.hasSuffix("validate_full") }.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" }, "metadata and mutations carry the validated bearer")
        do { try await client.submit(submission); check(false, "duplicate snapshot rejected") }
        catch { check(await transport.requests.filter { $0.url!.path.hasSuffix("submitLeaveApply") }.count == 1, "same confirmation can never send twice") }
        let departure = try await client.loadForm(.departure)
        check(departure.choices.first?.id == "holiday" && departure.phone == "18000000000", "departure uses active holiday type and required minimal contact prefill")
        var stay = CampusFormDraft(begin: Date(), end: Date()); stay.typeID = "holiday"; stay.leaving = false
        try await client.submit(stay.snapshot(configuration: departure, approvers: nil))
        check(await transport.requests.filter { $0.url!.path.hasSuffix("applyGqleave") }.count == 1, "new registration uses create endpoint only")

        let locationTransport = FormTransport { req,_ in
            if req.url!.path.hasSuffix("querySysConfigItems") {
                return (200,#"{"data":[{"configKey":"dataAddressShow","configContent":"显示"},{"configKey":"leave_address_config","configContent":"隐藏"}]}"#)
            }
            return nil
        }
        let locationAPI = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: locationTransport)
        let locationConfig = try await locationAPI.loadForm(.leave)
        var locationDraft = draft; locationDraft.locationAddress = "示例定位地址"
        let locationRole = try await locationAPI.approvers(type: "sick", days: 0.5)
        try await locationAPI.submit(locationDraft.snapshot(configuration: locationConfig, approvers: locationRole))
        let locationWrite = await locationTransport.requests.last { $0.url!.path.hasSuffix("submitLeaveApply") }!
        let locationBody = try JSONSerialization.jsonObject(with: locationWrite.httpBody!) as! [String: Any]
        check(locationConfig.showLocation && !locationConfig.needsLocation && locationBody["address"] as? String == "示例定位地址", "visible optional location survives school configuration loading and JSON submission")

        for status in [401, 302, 500] {
            let t = FormTransport { req,_ in req.url!.path.hasSuffix("submitLeaveApply") ? (status,"private-server-error") : nil }
            let api = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: t)
            let c = try await api.loadForm(.leave), a = try await api.approvers(type: "sick", days: 0.5)
            do { try await api.submit(draft.snapshot(configuration: c, approvers: a)); check(false, "failed mutation surfaced") }
            catch { check(await t.requests.filter { $0.url!.path.hasSuffix("submitLeaveApply") }.count == 1 && !error.localizedDescription.contains("private"), "mutation HTTP failure is safe and never automatically retried") }
        }
        let timeout = FormTransport { req,_ in if req.url!.path.hasSuffix("submitLeaveApply") { throw URLError(.timedOut) }; return nil }
        let slow = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: timeout)
        let sc = try await slow.loadForm(.leave), sa = try await slow.approvers(type: "sick", days: 0.5)
        do { try await slow.submit(draft.snapshot(configuration: sc, approvers: sa)); check(false, "timeout is unknown") }
        catch { let count = await timeout.requests.filter { $0.url!.path.hasSuffix("submitLeaveApply") }.count; check(error as? CampusFormError == .unknownOutcome && count == 1, "timeout remains unknown without resend") }
        let stale = FormCredentials(), other = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: FormTransport())
        let own = CampusClient(account: "fixture-account", credentials: stale, transport: FormTransport())
        let before = try await own.loadForm(.leave); stale.change()
        do { try await own.submit(draft.snapshot(configuration: before, approvers: role)); check(false,"old account rejected") }
        catch { check(error is CancellationError, "account generation invalidates native form submission") }
        _ = other
        let read401 = FormTransport { req, count in req.url!.path.hasSuffix("querySysConfigItems") && count == 1 ? (401, "") : nil }
        _ = try await CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: read401).loadForm(.leave)
        let renewals = await read401.requests.filter { $0.url!.path.hasSuffix("validate_full") }
        check(renewals.count == 2, "metadata 401 revalidates once before retrying the read")
        let changedConfig = FormTransport { req, count in
            if req.url!.path.contains("LeaveType/") && count > 1 { return (200,#"{"data":{"list":[],"hasNextPage":false}}"#) }; return nil
        }
        let changeAPI = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: changedConfig)
        let cc = try await changeAPI.loadForm(.leave), ca = try await changeAPI.approvers(type: "sick", days: 0.5)
        do { try await changeAPI.submit(draft.snapshot(configuration: cc, approvers: ca)); check(false, "changed form blocked") }
        catch { check(await changedConfig.requests.allSatisfy { !$0.url!.path.hasSuffix("submitLeaveApply") }, "changed official configuration cannot mutate an approved snapshot") }

        let uploads = FormTransport { req,_ in
            if req.url!.path.contains("LeaveType/") { return (200,#"{"data":{"list":[{"id":"sick","name":"病假","enableStatus":0,"isUploadFile":0}],"hasNextPage":false}}"#) }; return nil
        }
        let uploadAPI = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: uploads)
        let uc = try await uploadAPI.loadForm(.leave), ua = try await uploadAPI.approvers(type: "sick", days: 0.5)
        check(await uploads.requests.allSatisfy { !$0.url!.path.contains("filecenter") }, "loading forms never uploads attachments")
        var evidence = draft; evidence.attachments = [.init(name: "证明.png", mime: "image/png", data: Data([1,2,3]), isImage: true)]
        try await uploadAPI.submit(evidence.snapshot(configuration: uc, approvers: ua))
        let uploadedRequests = await uploads.requests
        let upload = uploadedRequests.first { $0.url!.path.hasSuffix("file/base64") }!
        check(String(data: upload.httpBody!, encoding: .utf8)!.contains("data:image/png;base64,"), "confirmed evidence uses official base64 multipart upload")
        let uploadedPayload = try JSONSerialization.jsonObject(with: uploadedRequests.last!.httpBody!) as! [String:Any]
        check((uploadedPayload["applyFiles"] as? [[String:String]])?.first?["fileId"] == "uploaded-file", "submission references verified upload identifiers")

        for (reply, expected) in [(#"{"data":{}}"#,CampusFormError.unknownOutcome), (#"{"code":"5000","errorMessage":"private-contact-data"}"#,.rejected)] {
            let t = FormTransport { req,_ in req.url!.path.hasSuffix("submitLeaveApply") ? (200,reply) : nil }
            let api = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: t)
            let c = try await api.loadForm(.leave), a = try await api.approvers(type: "sick", days: 0.5)
            do { try await api.submit(draft.snapshot(configuration: c, approvers: a)); check(false,"unconfirmed response rejected") }
            catch { check(error as? CampusFormError == expected && !error.localizedDescription.contains("private"), "only recognized business success is accepted and errors remain private") }
        }
        let savedDraft = draft
        let reconcileTransport = FormTransport { req, count in
            if req.url!.path.hasSuffix("submitLeaveApply") { throw URLError(.timedOut) }
            if req.url!.path.hasSuffix("queryListForPage") && count > 2 {
                var record = try CampusSubmission(kind: .leave, configuration: config, draft: savedDraft, approvers: role).payload(uploaded: [])
                record["id"] = "new-id"; record["applyTime"] = CampusSubmission.date(Date())
                return (200,String(data:try JSONSerialization.data(withJSONObject:["data":["list":[record],"hasNextPage":false]]),encoding:.utf8)!)
            }; return nil
        }
        let reconcileAPI = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: reconcileTransport)
        let rc = try await reconcileAPI.loadForm(.leave), ra = try await reconcileAPI.approvers(type: "sick", days: 0.5)
        let rs = try draft.snapshot(configuration: rc, approvers: ra)
        do { try await reconcileAPI.submit(rs) } catch {}
        check(try await reconcileAPI.reconcile(rs), "unknown outcome confirms only a unique new matching record")
        check(await reconcileTransport.requests.filter { $0.url!.path.hasSuffix("submitLeaveApply") }.count == 1, "reconciliation performs reads without repeating submission")

        let destinations = FormTransport { req,_ in
            if req.url!.path.hasSuffix("querySysConfigItems") { return (200,#"{"data":[{"configKey":"leave_qxlx_config","configContent":"显示"}]}"#) }
            if req.url!.path.hasSuffix("queryAreaLabel") { return (200,#"{"data":[{"value":"inside","label":"市内","children":[{"value":"home","label":"回家"}]}]}"#) }
            return nil
        }
        let destinationAPI = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: destinations)
        let dc = try await destinationAPI.loadForm(.leave)
        var destinationDraft = draft; destinationDraft.destinationTypeID = "inside-home"; destinationDraft.destinationDetails = "示例地址"
        do {
            let ds = try destinationDraft.snapshot(configuration: dc, approvers: role)
            check(try ds.payload(uploaded: [])["qxlx"] as? String == "inside-home" && dc.destinationTypes.first?.name == "市内 / 回家", "two-level destinations encode the official parent-child path")
        } catch { check(false, "two-level destinations encode the official parent-child path") }
        let defaults = FormTransport { req,_ in req.url!.path.hasSuffix("querySysConfigItems") ? (200,#"{"data":[]}"#) : nil }
        let defaultsConfig = try await CampusClient(account:"fixture-account", credentials:FormCredentials(), transport:defaults).loadForm(.leave)
        check(defaultsConfig.needsLeaveTime && !defaultsConfig.roleFallback, "missing optional flags preserve official required-time and narrow reviewer defaults")
        let unknownWindow = FormTransport { req,_ in
            req.url!.path.contains("LeaveType/") ? (200,#"{"data":{"list":[{"id":"sick","name":"病假","enableStatus":0,"isUploadFile":1,"timeConfig":"future-rule"}],"hasNextPage":false}}"#) : nil
        }
        do { _ = try await CampusClient(account:"fixture-account",credentials:FormCredentials(),transport:unknownWindow).loadForm(.leave); check(false,"unknown time rule blocks loading") }
        catch { check(error as? CampusFormError == .invalidResponse,"unknown time rule blocks loading") }
        let savedStay = stay
        for complete in [false, true] {
            let t = FormTransport { req,count in
                if req.url!.path.hasSuffix("queryStuGqleaveInfo") && count > 1 {
                    var row = try CampusSubmission(kind:.departure,configuration:departure,draft:savedStay,approvers:nil).payload(uploaded:[])
                    row["openid"] = "new-stay"; row["applyDate"] = CampusSubmission.date(Date())
                    row["phone"] = complete ? "" : "18000000009"
                    return (200,String(data:try JSONSerialization.data(withJSONObject:["code":2000,"data":[row]]),encoding:.utf8)!)
                }; return nil
            }
            let api = CampusClient(account:"fixture-account",credentials:FormCredentials(),transport:t)
            let c = try await api.loadForm(.departure), s = try stay.snapshot(configuration:c,approvers:nil)
            check(try await api.reconcile(s) == complete, "stay reconciliation requires complete matching submitted contact semantics")
        }
        var trip = savedStay
        trip.leaving = true; trip.end = trip.begin.addingTimeInterval(3600)
        trip.phone = "18000000000"; trip.parentPhone = "18000000001"
        trip.area = ["示例省","示例市","示例区"]; trip.travelMethod = "火车"; trip.reason = "示例事由"
        trip.tripNumber = "G1"; trip.detailAddress = "示例地址"
        let savedTrip = trip
        for changedField in ["phone", "jzPhone", "reason", "jtgj", "tjcs", "xxdz", "txdz", "startDate", "endDate", "none"] {
            let t = FormTransport { req,count in
                if req.url!.path.hasSuffix("queryStuGqleaveInfo") && count > 1 {
                    var row = try CampusSubmission(kind:.departure,configuration:departure,draft:savedTrip,approvers:nil).payload(uploaded:[])
                    row["openid"] = "new-trip"; row["applyDate"] = CampusSubmission.date(Date())
                    if changedField != "none" { row[changedField] = "different" }
                    return (200,String(data:try JSONSerialization.data(withJSONObject:["code":2000,"data":[row]]),encoding:.utf8)!)
                }; return nil
            }
            let api = CampusClient(account:"fixture-account",credentials:FormCredentials(),transport:t)
            let c = try await api.loadForm(.departure), s = try savedTrip.snapshot(configuration:c,approvers:nil)
            check(try await api.reconcile(s) == (changedField == "none"), "departure reconciliation rejects a different submitted field: " + changedField)
        }
        let ambiguous = FormTransport { req,_ in req.url!.path.hasSuffix("applyGqleave") ? (200,#"{"code":200,"data":false}"#) : nil }
        let ambiguousAPI = CampusClient(account:"fixture-account",credentials:FormCredentials(),transport:ambiguous)
        let ac = try await ambiguousAPI.loadForm(.departure)
        do { try await ambiguousAPI.submit(stay.snapshot(configuration:ac,approvers:nil)); check(false,"unproven departure success code stays unknown") }
        catch { check(error as? CampusFormError == .unknownOutcome,"unproven departure success code stays unknown") }
        let paddedHidden = FormTransport { req,_ in
            if req.url!.path.hasSuffix("querySysConfigItems") {
                return (200,#"{"data":[{"configKey":"leaveadmin_show_files","configContent":"\r\n 隐藏\t"}]}"#)
            }; return nil
        }
        do {
            let c = try await CampusClient(account:"fixture-account",credentials:FormCredentials(),transport:paddedHidden).loadForm(.leave)
            check(!c.needsFiles && c.needsLeaveTime && !c.roleFallback, "padded hidden optional flag loads without weakening required-time or reviewer defaults")
        } catch { check(false, "padded hidden optional flag loads without weakening required-time or reviewer defaults") }
        let paddedScope = FormTransport { req,_ in
            req.url!.path.hasSuffix("querySysConfigItems") ? (200,#"{"data":[{"configKey":"leaveadminApplyPowerUser","configContent":" 隐藏 "}]}"#) : nil
        }
        do { _ = try await CampusClient(account:"fixture-account",credentials:FormCredentials(),transport:paddedScope).loadForm(.leave); check(false,"noncanonical reviewer scope never broadens eligibility") }
        catch { check(error as? CampusFormError == .invalidResponse,"noncanonical reviewer scope never broadens eligibility") }
        if failures > 0 { exit(1) }
    }
}
