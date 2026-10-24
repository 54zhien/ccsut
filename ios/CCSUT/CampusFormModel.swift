import Foundation
import Observation

@Observable @MainActor
final class CampusFormModel {
    enum State: Equatable { case loading, editing, submitting, unknown, submitted, cancelled }
    let kind: CampusFormKind
    let account: String
    private(set) var configuration: CampusFormConfiguration?
    private(set) var approvers: CampusApprovers?
    private(set) var draft: CampusFormDraft
    private(set) var state: State = .loading
    private(set) var error: String?
    private(set) var isLoadingApprovers = false
    private(set) var isChecking = false
    var confirmation: CampusSubmission?
    private let api: any CampusFormServing
    private let currentGeneration: @Sendable () -> UInt64
    private let generation: UInt64
    private var active = true
    private var revision: UInt64 = 0
    private var candidateRevision: UInt64 = 0
    private var configurationRevision: UInt64 = 0
    private var pending: CampusSubmission?
    @ObservationIgnored private var loadTask: Task<CampusFormConfiguration, Error>?
    @ObservationIgnored private var candidateTask: Task<CampusApprovers, Error>?
    @ObservationIgnored private var submitTask: Task<Void, Error>?

    init(kind: CampusFormKind, account: String, api: any CampusFormServing,
         currentGeneration: @escaping @Sendable () -> UInt64) {
        self.kind = kind; self.account = account; self.api = api
        self.currentGeneration = currentGeneration; generation = currentGeneration()
        let start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        draft = CampusFormDraft(begin: start, end: start.addingTimeInterval(14_400))
    }
    var candidateKey: String { "\(configurationRevision)|\(draft.typeID)|\(draft.begin.timeIntervalSince1970)|\(draft.end.timeIntervalSince1970)" }
    var canReview: Bool { state == .editing && configuration?.choices.isEmpty == false && !isLoadingApprovers }

    func load() async {
        guard verifyAccount(), state != .submitting, state != .unknown else { return }
        loadTask?.cancel(); candidateTask?.cancel(); revision &+= 1; candidateRevision &+= 1
        let rev = revision
        configuration = nil; approvers = nil; confirmation = nil; error = nil; state = .loading
        let api = api, kind = kind
        let task = Task { try await api.loadForm(kind) }; loadTask = task
        do {
            let c = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard verifyAccount(), rev == revision, !Task.isCancelled else { return }
            guard c.account == account, c.generation == generation else { throw CampusError.identityMismatch }
            configuration = c; state = .editing
            var fresh = CampusFormDraft(begin: draft.begin, end: draft.end)
            fresh.phone = c.phone; fresh.parentPhone = c.parentPhone; fresh.contactPhone = c.parentPhone
            if c.choices.count == 1 { fresh.typeID = c.choices[0].id }
            if kind == .leave && !c.canLeaveSchool { fresh.leaving = false }
            draft = fresh
            configurationRevision &+= 1
            if c.choices.isEmpty { error = "当前没有开放的可办理类型" }
        } catch {
            guard verifyAccount(), rev == revision, !Task.isCancelled else { return }
            state = .editing; report(error)
        }
        if rev == revision { loadTask = nil }
    }

    func update(_ change: (inout CampusFormDraft) -> Void) {
        guard verifyAccount(), state == .editing else { return }
        let key = candidateKey, type = draft.typeID
        change(&draft); revision &+= 1; confirmation = nil; error = nil
        if draft.typeID != type { draft.attachments.removeAll(where: \.isImage) }
        if key != candidateKey {
            candidateRevision &+= 1; candidateTask?.cancel(); candidateTask = nil
            approvers = nil; draft.approverID = ""; isLoadingApprovers = false
        }
        if kind == .departure && draft.leaving == false {
            draft.area = []; draft.detailAddress = ""; draft.travelMethod = ""; draft.tripNumber = ""; draft.reason = ""
        }
    }

    func refreshApprovers() async {
        guard verifyAccount(), state == .editing, kind == .leave, let c = configuration,
              c.choices.contains(where: { $0.id == draft.typeID }), draft.duration > 0 else { return }
        candidateTask?.cancel(); candidateRevision &+= 1
        let rev = candidateRevision, key = candidateKey, type = draft.typeID, days = draft.duration, api = api
        isLoadingApprovers = true; approvers = nil; draft.approverID = ""; confirmation = nil
        let task = Task {
            let role = try await api.approvers(type: type, days: days)
            return try await c.roleFallback ? api.roleUsers(role) : role
        }
        candidateTask = task
        defer { if rev == candidateRevision { isLoadingApprovers = false; candidateTask = nil } }
        do {
            let role = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard verifyAccount(), rev == candidateRevision, key == candidateKey, !Task.isCancelled else { return }
            approvers = role
            if role.users.count == 1 { draft.approverID = role.users[0].id }
            if role.users.isEmpty { error = "学校暂未配置可用审批人，请联系辅导员" }
        } catch {
            guard verifyAccount(), rev == candidateRevision, key == candidateKey, !Task.isCancelled else { return }
            report(error)
        }
    }

    func prepareConfirmation() {
        guard verifyAccount(), canReview, let c = configuration else { return }
        do { confirmation = try draft.snapshot(configuration: c, approvers: approvers); error = nil }
        catch { report(error) }
    }

    func submit(_ approved: CampusSubmission) async {
        guard verifyAccount(), state == .editing, confirmation?.id == approved.id,
              approved.draft == draft, approved.configuration == configuration else { return }
        let rev = revision, api = api
        state = .submitting; error = nil
        let task = Task { try await api.submit(approved) }; submitTask = task
        do {
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard verifyAccount(), rev == revision else { return }
            finishSubmitted()
        } catch {
            guard verifyAccount(), rev == revision else { return }
            if error as? CampusFormError == .unknownOutcome {
                state = .unknown; pending = approved
            } else { state = .editing }
            report(error)
        }
        confirmation = nil; submitTask = nil
    }

    func checkResult() async {
        guard verifyAccount(), state == .unknown, let pending, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let found = try await api.reconcile(pending)
            guard verifyAccount() else { return }
            if found { finishSubmitted() }
            else { error = CampusFormError.unknownOutcome.localizedDescription }
        } catch { if verifyAccount() { report(error) } }
    }

    func locate(latitude: Double, longitude: Double) async {
        guard verifyAccount(), state == .editing else { return }
        let rev = revision
        do {
            let address = try await api.locate(latitude: latitude, longitude: longitude)
            guard verifyAccount(), rev == revision else { return }
            update { $0.locationAddress = address }
        } catch { if verifyAccount() { report(error) } }
    }
    func report(_ error: Error) {
        guard verifyAccount() else { return }
        self.error = (error as? CampusFormError)?.localizedDescription ?? (error as? CampusError)?.localizedDescription
            ?? "暂时无法完成操作，请稍后重试"
    }
    func stop() {
        active = false; revision &+= 1; candidateRevision &+= 1
        loadTask?.cancel(); candidateTask?.cancel(); submitTask?.cancel()
        clear(); state = .cancelled
    }
    private func finishSubmitted() {
        state = .submitted; error = nil; pending = nil; confirmation = nil
        draft = CampusFormDraft(begin: draft.begin, end: draft.end)
    }
    private func clear() {
        configuration = nil; approvers = nil; confirmation = nil; pending = nil; error = nil
        isLoadingApprovers = false
        draft = CampusFormDraft(begin: Date(), end: Date())
    }
    @discardableResult private func verifyAccount() -> Bool {
        guard active, currentGeneration() == generation else { clear(); state = .cancelled; return false }
        return true
    }
}
