import Foundation

@main struct CampusFormRulesTests {
    static func main() throws {
        var failures = 0
        func check(_ value: Bool, _ name: String) { print("\(value ? "PASS" : "FAIL") \(name)"); if !value { failures += 1 } }
        let start = Date(timeIntervalSince1970: 1_790_812_800)
        check(CampusFormDraft.days(from: start, to: start.addingTimeInterval(60)) == 0.5, "one minute rounds to half a day")
        check(CampusFormDraft.days(from: start, to: start.addingTimeInterval(43_200)) == 0.5, "exact half day remains half")
        check(CampusFormDraft.days(from: start, to: start.addingTimeInterval(43_201)) == 1, "over half day rounds up")
        check(CampusFormDraft.days(from: start, to: start.addingTimeInterval(86_400)) == 1, "exact day remains one")
        var config = CampusFormConfiguration(kind: .leave, account: "fixture-account", userId: "fixture-user", generation: 1)
        config.choices = [CampusFormChoice(id: "sick", name: "病假")]
        var draft = CampusFormDraft(begin: start, end: start.addingTimeInterval(3600))
        draft.typeID = "sick"; draft.reason = "事由 18000000000"; draft.contactPhone = "180 0000 0000"
        draft.leaving = false
        let approvers = CampusApprovers(roleID: "role", roleName: "辅导员", users: [.init(id: "teacher", name: "测试审批人")])
        draft.approverID = "teacher"
        let snapshot = try draft.snapshot(configuration: config, approvers: approvers)
        draft.reason = "改后的事由"
        let payload = try snapshot.payload(uploaded: [])
        check(payload["reason"] as? String == "事由 18000000000", "confirmation retains immutable original raw values")
        check(payload["linkmanPhone"] as? String == "18000000000", "formatted contact submits canonical original number")
        check(payload["applyUserId"] as? String == "fixture-user" && payload["leaveSchool"] as? String == "1", "identity derived from config and non-leaving maps to one")
        draft.leaving = true
        check(try draft.snapshot(configuration: config, approvers: approvers).payload(uploaded: [])["leaveSchool"] as? String == "0", "leaving maps to zero")
        func rejected(_ d: CampusFormDraft, _ c: CampusFormConfiguration, _ a: CampusApprovers? = approvers) -> Bool {
            do { _ = try d.snapshot(configuration: c, approvers: a); return false } catch { return true }
        }
        var bad = draft; bad.end = bad.begin
        check(rejected(bad, config), "zero and negative durations rejected")
        bad = draft; bad.approverID = "outside-role"
        check(rejected(bad, config), "arbitrary approver cannot be submitted")
        bad = draft; bad.contactPhone = "bad"
        check(rejected(bad, config), "malformed contact rejected")
        config.needsLocation = true
        check(rejected(draft, config), "mandatory missing location rejected")
        draft.locationAddress = "测试地址"; config.needsLocation = false; config.needsDestination = true
        check(rejected(draft, config), "mandatory destination is not silently omitted")
        draft.destinationTypeID = "home"; draft.destinationDetails = "测试去向"; config.destinationTypes = [.init(id: "home", name: "回家")]
        check(!rejected(draft, config), "verified destination accepted")
        config.needsDestination = false; config.choices[0].requiresImage = true
        check(rejected(draft, config), "required evidence image cannot be omitted")
        draft.attachments = [.init(name: "证明.png", mime: "image/png", data: Data([1,2,3]), isImage: true)]
        check(!rejected(draft, config), "in-memory evidence satisfies requirement")
        config.needsFiles = true
        check(rejected(draft, config), "generic required attachment is distinct from evidence images")
        config.needsFiles = false; config.choices[0].requiresImage = false
        config.choices[0].window = CampusTimeWindow(startMinute: 0, endMinute: 1)
        check(rejected(draft, config), "type-specific official time window enforced")

        var travel = CampusFormConfiguration(kind: .departure, account: "fixture-account", userId: "fixture-user", generation: 1)
        travel.choices = [.init(id: "holiday", name: "示例假期")]
        var departure = CampusFormDraft(begin: start, end: start.addingTimeInterval(86_400))
        departure.typeID = "holiday"; departure.leaving = true; departure.phone = "18000000000"; departure.parentPhone = "18000000001"
        check(rejected(departure, travel, nil), "departure requires verified destination")
        departure.area = ["测试省", "测试市", "测试区"]
        let dep = try departure.snapshot(configuration: travel, approvers: nil).payload(uploaded: [])
        check(dep["type"] as? String == "holiday" && dep["isLeave"] as? String == "是", "departure sends active holiday and official yes string")
        check(dep["openid"] is NSNull && dep["status"] is NSNull, "new registration never edits an existing record")
        departure.leaving = false; departure.reason = "old reason"; departure.tripNumber = "old trip"
        let stay = try departure.snapshot(configuration: travel, approvers: nil).payload(uploaded: [])
        check(["reason","jtgj","tjcs","xxdz","txdz","startDate","endDate"].allSatisfy { stay[$0] is NSNull }, "stay-at-school payload clears departure-only fields")
        departure.leaving = nil
        check(rejected(departure, travel, nil), "leaving or staying must be explicitly chosen")
        check(!CampusFormError.unknownOutcome.localizedDescription.contains("private"), "submission errors use safe fixed copy")
        if failures > 0 { exit(1) }
    }
}
