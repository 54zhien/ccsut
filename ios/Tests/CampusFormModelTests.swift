import Foundation

actor FormModelServer: CampusFormServing {
    var unknown = false, found = false, delayedLoad = false
    var writes = 0, checks = 0
    func configure(unknown: Bool = false, found: Bool = false, delayedLoad: Bool = false) { self.unknown = unknown; self.found = found; self.delayedLoad = delayedLoad }
    func loadForm(_ kind: CampusFormKind) async throws -> CampusFormConfiguration {
        if delayedLoad { try? await Task.sleep(for: .milliseconds(100)) }
        var c = CampusFormConfiguration(kind: kind, account: "fixture-account", userId: "fixture-user", generation: 1)
        c.choices = [.init(id:"sick",name:"病假"), .init(id:"slow",name:"示例类型")]; c.parentPhone = "18000000001"
        return c
    }
    func approvers(type: String, days: Double) async throws -> CampusApprovers {
        if type == "slow" { try? await Task.sleep(for: .milliseconds(100)) }
        return .init(roleID: type, roleName: "审批", users: [.init(id:type+"-teacher",name:"示例审批人")])
    }
    func roleUsers(_ role: CampusApprovers) async throws -> CampusApprovers { role }
    func locate(latitude: Double, longitude: Double) async throws -> String { "示例地址" }
    func submit(_ submission: CampusSubmission) async throws {
        writes += 1; try? await Task.sleep(for: .milliseconds(30))
        if unknown { throw CampusFormError.unknownOutcome }
    }
    func reconcile(_ submission: CampusSubmission) async throws -> Bool { checks += 1; return found }
}
final class FormEpoch: @unchecked Sendable {
    private let lock = NSLock(); private var value: UInt64 = 1
    func current() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func change() { lock.lock(); value += 1; lock.unlock() }
}

@main struct CampusFormModelTests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ ok: Bool, _ name: String) { print("\(ok ? "PASS" : "FAIL") \(name)"); if !ok { failures += 1 } }
        let api = FormModelServer(), epoch = FormEpoch()
        let model = CampusFormModel(kind:.leave, account:"fixture-account", api:api, currentGeneration:{epoch.current()})
        await model.load()
        check(model.configuration != nil && model.draft.contactPhone == "18000000001", "form publishes minimal prefill after account verification")
        model.update { $0.typeID = "sick"; $0.leaving = false; $0.reason = "示例事由" }
        await model.refreshApprovers()
        check(model.draft.approverID == "sick-teacher", "only eligible unique approver is auto-selected")
        model.prepareConfirmation(); let first = model.confirmation!
        model.update { $0.reason = "新事由" }
        check(model.confirmation == nil, "editing a draft invalidates the approved confirmation")
        await model.submit(first)
        check(await api.writes == 0, "stale confirmation cannot submit a changed draft")
        model.update { $0.typeID = "slow" }
        let old = Task { await model.refreshApprovers() }
        try await Task.sleep(for: .milliseconds(5))
        model.update { $0.typeID = "sick" }
        await model.refreshApprovers(); await old.value
        check(model.approvers?.roleID == "sick" && model.draft.approverID == "sick-teacher", "late candidate response cannot restore a previous type")
        await api.configure(unknown:true)
        model.prepareConfirmation(); let approved = model.confirmation!
        let submitting = Task { await model.submit(approved) }
        try await Task.sleep(for:.milliseconds(5)); await model.submit(approved); await submitting.value
        let writes = await api.writes
        check(model.state == .unknown && writes == 1, "repeated taps issue one mutation and preserve unknown outcome")
        await model.checkResult()
        let checks = await api.checks, writesAfterCheck = await api.writes
        check(model.state == .unknown && checks == 1 && writesAfterCheck == 1, "unmatched outcome stays pending without resubmission")
        await api.configure(found:true); await model.checkResult()
        check(model.state == .submitted, "unique matching record confirms submitted state, never approval")
        let delayed = FormModelServer(); await delayed.configure(delayedLoad:true)
        let stopped = CampusFormModel(kind:.leave,account:"fixture-account",api:delayed,currentGeneration:{1})
        let loading = Task { await stopped.load() }; try await Task.sleep(for:.milliseconds(5)); stopped.stop(); await loading.value
        check(stopped.configuration == nil && stopped.draft.contactPhone.isEmpty, "closing form discards late metadata and raw personal data")
        let changed = CampusFormModel(kind:.leave,account:"fixture-account",api:FormModelServer(),currentGeneration:{epoch.current()})
        await changed.load(); epoch.change(); changed.update { $0.reason = "must not apply" }
        check(changed.configuration == nil && changed.draft.contactPhone.isEmpty && changed.confirmation == nil, "account change clears draft and pending confirmation")
        if failures > 0 { exit(1) }
    }
}
