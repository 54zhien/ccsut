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
                let record: [String:Any] = ["id":"new-id", "leaveType":"sick", "reason":savedDraft.reason,
                    "beginTime":CampusSubmission.date(savedDraft.begin), "endTime":CampusSubmission.date(savedDraft.end), "applyTime":CampusSubmission.date(Date())]
                return (200,String(data:try JSONSerialization.data(withJSONObject:["data":["list":[record],"hasNextPage":false]]),encoding:.utf8)!)
            }; return nil
        }
        let reconcileAPI = CampusClient(account: "fixture-account", credentials: FormCredentials(), transport: reconcileTransport)
        let rc = try await reconcileAPI.loadForm(.leave), ra = try await reconcileAPI.approvers(type: "sick", days: 0.5)
        let rs = try draft.snapshot(configuration: rc, approvers: ra)
        do { try await reconcileAPI.submit(rs) } catch {}
        check(try await reconcileAPI.reconcile(rs), "unknown outcome confirms only a unique new matching record")
        check(await reconcileTransport.requests.filter { $0.url!.path.hasSuffix("submitLeaveApply") }.count == 1, "reconciliation performs reads without repeating submission")
        if failures > 0 { exit(1) }
    }
}
