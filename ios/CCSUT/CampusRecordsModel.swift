import Foundation
import Observation

@Observable @MainActor
final class CampusRecordsModel {
    private(set) var leave = CampusPageState()
    private(set) var leaveError: CampusError?
    private(set) var leaveFailureWasRefresh = true
    private(set) var isLoadingLeave = false
    private(set) var travel: [CampusTravelKind: [CampusTravelRecord]] = [:]
    private(set) var travelErrors: [CampusTravelKind: CampusError] = [:]
    private(set) var loadingTravel: Set<CampusTravelKind> = []
    private let api: any CampusReading
    private let currentGeneration: @Sendable () -> UInt64
    private let generation: UInt64
    private var revision: UInt64 = 0
    @ObservationIgnored private var leaveTask: Task<CampusLeavePage, Error>?
    @ObservationIgnored private var travelTasks: [CampusTravelKind: Task<[CampusTravelRecord], Error>] = [:]

    init(api: any CampusReading, currentGeneration: @escaping @Sendable () -> UInt64) {
        self.api = api
        self.currentGeneration = currentGeneration
        generation = currentGeneration()
    }

    func loadLeave(reset: Bool) async {
        guard verifyAccount(), !isLoadingLeave, reset || leave.hasMore else { return }
        let requestRevision = revision
        let page = reset ? 1 : leave.page + 1
        let api = api
        isLoadingLeave = true
        leaveError = nil
        let task = Task { try await api.leaveRecords(page: page, size: 20) }
        leaveTask = task
        defer {
            if revision == requestRevision { isLoadingLeave = false; leaveTask = nil }
        }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard verifyAccount(), requestRevision == revision, !Task.isCancelled else { return }
            try leave.apply(result, reset: reset)
        } catch {
            guard verifyAccount(), requestRevision == revision, !(error is CancellationError), !Task.isCancelled else { return }
            leaveFailureWasRefresh = reset
            leaveError = error as? CampusError ?? .serviceUnavailable
        }
    }

    func loadTravel(kind: CampusTravelKind) async {
        guard verifyAccount(), !loadingTravel.contains(kind) else { return }
        let requestRevision = revision
        let api = api
        loadingTravel.insert(kind)
        travelErrors[kind] = nil
        let task = Task { try await api.travelRecords(kind: kind) }
        travelTasks[kind] = task
        defer {
            if revision == requestRevision { loadingTravel.remove(kind); travelTasks[kind] = nil }
        }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard verifyAccount(), requestRevision == revision, !Task.isCancelled else { return }
            travel[kind] = result
        } catch {
            guard verifyAccount(), requestRevision == revision, !(error is CancellationError), !Task.isCancelled else { return }
            travelErrors[kind] = error as? CampusError ?? .serviceUnavailable
        }
    }

    func cancel() {
        revision &+= 1
        leaveTask?.cancel()
        leaveTask = nil
        for task in travelTasks.values { task.cancel() }
        travelTasks.removeAll()
        isLoadingLeave = false
        loadingTravel.removeAll()
    }

    @discardableResult private func verifyAccount() -> Bool {
        guard currentGeneration() == generation else {
            cancel()
            leave = CampusPageState()
            leaveError = nil
            travel.removeAll()
            travelErrors.removeAll()
            return false
        }
        return true
    }
}
