import Foundation

actor FormModelServer: CampusFormServing {
    let account: String
    let generation: UInt64
    var unknown = false, found = false, delayedLoad = false, changedConfig = false
    var writes = 0, checks = 0, candidateReads = 0
    var lastRecovery: CampusFormRecoveryDescriptor?
    var candidateFailure = false
    init(account: String = "fixture-account", generation: UInt64 = 1) {
        self.account = account; self.generation = generation
    }
    func failCandidates(_ value: Bool) { candidateFailure = value }
    func configure(unknown: Bool = false, found: Bool = false, delayedLoad: Bool = false) { self.unknown = unknown; self.found = found; self.delayedLoad = delayedLoad }
    func changeConfiguration(_ value: Bool) { changedConfig = value }
    func loadForm(_ kind: CampusFormKind) async throws -> CampusFormConfiguration {
        if delayedLoad { try? await Task.sleep(for: .milliseconds(100)) }
        var c = CampusFormConfiguration(kind: kind, account: account, userId: "fixture-user", generation: generation)
        c.choices = [.init(id:"sick",name:"病假"), .init(id:"slow",name:"示例类型")]; c.parentPhone = "18000000001"
        return c
    }
    func approvers(type: String, days: Double) async throws -> CampusApprovers {
        candidateReads += 1
        if candidateFailure { throw CampusError.authentication }
        if type == "slow" { try? await Task.sleep(for: .milliseconds(100)) }
        return .init(roleID: type, roleName: "审批", users: [.init(id:type+"-teacher",name:"示例审批人")])
    }
    func roleUsers(_ role: CampusApprovers) async throws -> CampusApprovers { role }
    func locate(latitude: Double, longitude: Double) async throws -> String { "示例地址" }
    func submit(_ submission: CampusSubmission) async throws {
        writes += 1; try? await Task.sleep(for: .milliseconds(30))
        if changedConfig { throw CampusFormError.configurationChanged }
        if unknown { throw CampusFormError.unknownOutcome }
    }
    func reconcile(_ attempt: CampusFormRecoveryDescriptor) async throws -> Bool {
        checks += 1; lastRecovery = attempt; return found
    }
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
        await model.refreshApprovers()
        check(await api.candidateReads == 0 && model.approvers == nil, "an unselected type cannot issue a candidate request")
        model.update { $0.typeID = "sick"; $0.leaving = false; $0.reason = "示例事由" }
        await api.failCandidates(true); await model.refreshApprovers()
        check(model.approvers == nil && model.error != nil, "candidate request failures retain a safe retryable error")
        await api.failCandidates(false)
        await model.refreshApprovers()
        check(model.error == nil, "successful candidate retry clears the previous failure message")
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

        let recoveryAPI = FormModelServer(), recoveryEpoch = FormEpoch()
        await recoveryAPI.configure(unknown:true)
        let beforeClose = CampusFormModel(kind:.leave, account:"fixture-account", api:recoveryAPI,
                                          currentGeneration:{recoveryEpoch.current()})
        await beforeClose.load()
        beforeClose.update { $0.typeID = "sick"; $0.leaving = false; $0.reason = "pending recovery" }
        await beforeClose.refreshApprovers()
        beforeClose.prepareConfirmation()
        let pendingSubmission = beforeClose.confirmation!
        await beforeClose.submit(pendingSubmission)
        check(beforeClose.state == .unknown, "timed-out attempt is marked unknown before dismissal")
        beforeClose.stop()
        let reopened = CampusFormModel(kind:.leave, account:"fixture-account", api:recoveryAPI,
                                       currentGeneration:{recoveryEpoch.current()})
        await reopened.load()
        check(reopened.state == .unknown, "closing and reopening restores an unresolved attempt in the same account generation")
        await reopened.checkResult()
        await reopened.submit(pendingSubmission)
        let recoveryWrites = await recoveryAPI.writes
        let recoveryChecks = await recoveryAPI.checks
        check(recoveryWrites == 1 && recoveryChecks == 1 && reopened.state == .unknown,
              "reopened recovery reconciles read-only and blocks a second write")
        let recoveredAttempt = await recoveryAPI.lastRecovery
        check(recoveredAttempt?.expectedFingerprint != nil && recoveredAttempt?.account == "fixture-account" &&
              recoveredAttempt?.generation == recoveryEpoch.current(),
              "recovery retains only matching metadata scoped to the active account generation")
        recoveryEpoch.change()
        let afterLogout = CampusFormModel(kind:.leave, account:"fixture-account", api:recoveryAPI,
                                          currentGeneration:{recoveryEpoch.current()})
        check(afterLogout.state == .loading, "a new account generation cannot recover an older unresolved attempt")

        let concurrentAPI = FormModelServer(account:"concurrent-account")
        await concurrentAPI.configure(unknown:true)
        let concurrentEpoch = FormEpoch()
        let firstModel = CampusFormModel(kind:.leave, account:"concurrent-account", api:concurrentAPI,
                                         currentGeneration:{concurrentEpoch.current()})
        let secondModel = CampusFormModel(kind:.leave, account:"concurrent-account", api:concurrentAPI,
                                          currentGeneration:{concurrentEpoch.current()})
        let idleModel = CampusFormModel(kind:.leave, account:"concurrent-account", api:concurrentAPI,
                                        currentGeneration:{concurrentEpoch.current()})
        await firstModel.load(); await secondModel.load(); await idleModel.load()
        for candidate in [firstModel, secondModel, idleModel] {
            candidate.update { $0.typeID = "sick"; $0.leaving = false; $0.reason = "concurrent attempt" }
            await candidate.refreshApprovers()
            candidate.prepareConfirmation()
        }
        let firstApproval = firstModel.confirmation!, secondApproval = secondModel.confirmation!
        await firstModel.submit(firstApproval)
        idleModel.stop()
        let reopenedConcurrent = CampusFormModel(kind:.leave, account:"concurrent-account", api:concurrentAPI,
                                                 currentGeneration:{concurrentEpoch.current()})
        await secondModel.submit(secondApproval)
        let concurrentWrites = await concurrentAPI.writes
        check(concurrentWrites == 1 && firstModel.state == .unknown && secondModel.state == .unknown &&
              reopenedConcurrent.state == .unknown,
              "concurrent models share one claim and an idle model cannot erase it on dismissal")
        await concurrentAPI.configure(found:true)
        await firstModel.checkResult()

        let closeAPI = FormModelServer(account:"close-in-flight-account")
        let closeEpoch = FormEpoch()
        let closingModel = CampusFormModel(kind:.leave, account:"close-in-flight-account", api:closeAPI,
                                           currentGeneration:{closeEpoch.current()})
        await closingModel.load()
        closingModel.update { $0.typeID = "sick"; $0.leaving = false; $0.reason = "closed while sending" }
        await closingModel.refreshApprovers(); closingModel.prepareConfirmation()
        let closingApproval = closingModel.confirmation!
        let closeRequest = Task { await closingModel.submit(closingApproval) }
        while await closeAPI.writes == 0 { await Task.yield() }
        closingModel.stop()
        let reopenedWhileSending = CampusFormModel(kind:.leave, account:"close-in-flight-account", api:closeAPI,
                                                   currentGeneration:{closeEpoch.current()})
        await closeRequest.value
        let reopenedAfterCallback = CampusFormModel(kind:.leave, account:"close-in-flight-account", api:closeAPI,
                                                    currentGeneration:{closeEpoch.current()})
        check(reopenedWhileSending.state == .unknown && reopenedAfterCallback.state == .unknown,
              "late completion after dismissal cannot erase the unresolved recovery claim")

        let cancelAPI = FormModelServer(account:"generation-cancel-account")
        let cancelEpoch = FormEpoch()
        let cancelModel = CampusFormModel(kind:.leave, account:"generation-cancel-account", api:cancelAPI,
                                          currentGeneration:{cancelEpoch.current()})
        await cancelModel.load()
        cancelModel.update { $0.typeID = "sick"; $0.leaving = false; $0.reason = "generation cancellation" }
        await cancelModel.refreshApprovers(); cancelModel.prepareConfirmation()
        let cancelApproval = cancelModel.confirmation!
        let inFlight = Task { await cancelModel.submit(cancelApproval) }
        while await cancelAPI.writes == 0 { await Task.yield() }
        cancelEpoch.change()
        await inFlight.value
        let afterGenerationChange = CampusFormModel(kind:.leave, account:"generation-cancel-account", api:cancelAPI,
                                                    currentGeneration:{cancelEpoch.current()})
        check(cancelModel.state == .cancelled && afterGenerationChange.state == .loading,
              "generation change cancels recovery state from the prior session")

        let delayed = FormModelServer(); await delayed.configure(delayedLoad:true)
        let stopped = CampusFormModel(kind:.leave,account:"fixture-account",api:delayed,currentGeneration:{1})
        let loading = Task { await stopped.load() }; try await Task.sleep(for:.milliseconds(5)); stopped.stop(); await loading.value
        check(stopped.configuration == nil && stopped.draft.contactPhone.isEmpty, "closing form discards late metadata and raw personal data")
        let changed = CampusFormModel(kind:.leave,account:"fixture-account",api:FormModelServer(),currentGeneration:{epoch.current()})
        await changed.load(); epoch.change(); changed.update { $0.reason = "must not apply" }
        check(changed.configuration == nil && changed.draft.contactPhone.isEmpty && changed.confirmation == nil, "account change clears draft and pending confirmation")
        let changingAPI = FormModelServer()
        let reload = CampusFormModel(kind:.leave,account:"fixture-account",api:changingAPI,currentGeneration:{1})
        await reload.load(); reload.update { $0.typeID = "sick"; $0.leaving = false; $0.reason = "retained draft" }
        await reload.refreshApprovers(); reload.prepareConfirmation()
        await changingAPI.changeConfiguration(true); await reload.submit(reload.confirmation!)
        check(reload.needsReload && !reload.canReview, "changed configuration requires reload before another confirmation")
        await changingAPI.changeConfiguration(false); await reload.load(preservingDraft:true); await reload.refreshApprovers()
        check(!reload.needsReload && reload.draft.reason == "retained draft" && reload.confirmation == nil, "reload keeps user input but invalidates prior approval and confirmation")
        reload.prepareConfirmation(); await reload.submit(reload.confirmation!)
        check(reload.state == .submitted, "freshly reloaded draft can be reviewed and submitted")
        if failures > 0 { exit(1) }
    }
}
