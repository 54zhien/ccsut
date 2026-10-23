import Foundation

struct ElectiveCourseActionFacts: Equatable {
    let isSelected: Bool
    let selectionFlag: String?
    let isFull: Bool
}

struct ElectiveCourseRecord<Value> {
    let id: String
    let value: Value
    let actionFacts: ElectiveCourseActionFacts
}

struct ElectiveSnapshot<Value> {
    let courses: [Value]
    let courseIDs: Set<String>
    let batchIDsByCourse: [String: Set<String>]
    let actionFactsByCourse: [String: ElectiveCourseActionFacts]
}

/// Collects successful batch responses locally. The caller publishes this value only after every batch succeeds.
struct ElectiveSnapshotBuilder<Value> {
    private var courses: [Value] = []
    private var courseIDs = Set<String>()
    private var batchIDsByCourse: [String: Set<String>] = [:]
    private var actionFactsByCourse: [String: ElectiveCourseActionFacts] = [:]

    mutating func append(_ records: [ElectiveCourseRecord<Value>], batchID: String? = nil) {
        let normalizedBatchID = batchID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validBatchID = normalizedBatchID.flatMap { $0.isEmpty ? nil : $0 }

        for record in records {
            guard !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let validBatchID {
                batchIDsByCourse[record.id, default: []].insert(validBatchID)
            }
            guard courseIDs.insert(record.id).inserted else { continue }
            courses.append(record.value)
            actionFactsByCourse[record.id] = record.actionFacts
        }
    }

    var snapshot: ElectiveSnapshot<Value> {
        ElectiveSnapshot(
            courses: courses,
            courseIDs: courseIDs,
            batchIDsByCourse: batchIDsByCourse,
            actionFactsByCourse: actionFactsByCourse
        )
    }
}

enum ElectiveActionKind {
    case enroll
    case drop
}

enum ElectiveActionBlockReason: Equatable {
    case snapshotUnverified
    case courseMissing
    case missingBatch
    case ambiguousBatch
    case unavailable
    case full
    case alreadySelected
    case notSelected
    case actionInProgress
}

enum ElectiveActionDecision: Equatable {
    case allowed(batchID: String)
    case denied(ElectiveActionBlockReason)
}

enum ElectiveMutationRecovery {
    static func isAuthenticationRejection(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let explicitSignals = [
            "未登录", "请先登录", "请重新登录", "登录已失效", "登录过期", "登录超时",
            "会话失效", "会话过期", "session expired", "authentication required", "unauthorized"
        ]
        return explicitSignals.contains(where: normalized.contains)
    }

    /// Used after every awaited mutation/session/read continuation, regardless of its result.
    static func canContinueAfterAwait<Value>(expectedGeneration: UInt64, currentGeneration: UInt64,
                                             state: inout ElectiveState<Value>) -> Bool {
        !state.discardIfGenerationChanged(expected: expectedGeneration, current: currentGeneration)
    }
}

struct ElectiveState<Value> {
    private(set) var snapshot: ElectiveSnapshot<Value>?
    private(set) var snapshotGeneration: UInt64?
    private(set) var isSnapshotVerified = false
    private(set) var isActionInProgress = false

    /// A refresh retains same-account content, but an account switch must drop it.
    @discardableResult
    mutating func refreshStarted(generation: UInt64) -> Bool {
        let discardedPreviousAccount = snapshotGeneration != nil && snapshotGeneration != generation
        if discardedPreviousAccount {
            snapshot = nil
            snapshotGeneration = nil
        }
        isSnapshotVerified = false
        return discardedPreviousAccount
    }

    mutating func refreshFailed() {
        isSnapshotVerified = false
    }

    mutating func publish(_ snapshot: ElectiveSnapshot<Value>, generation: UInt64) {
        self.snapshot = snapshot
        snapshotGeneration = generation
        isSnapshotVerified = true
    }

    /// Returns true when the request crossed a cookie-generation boundary.
    /// Any retained snapshot not owned by the current generation is discarded.
    @discardableResult
    mutating func discardIfGenerationChanged(expected: UInt64, current: UInt64) -> Bool {
        guard expected != current else { return false }
        if snapshotGeneration != current {
            snapshot = nil
            snapshotGeneration = nil
            isSnapshotVerified = false
        }
        return true
    }

    func actionDecision(for courseID: String, kind: ElectiveActionKind,
                        generation: UInt64) -> ElectiveActionDecision {
        guard !isActionInProgress else { return .denied(.actionInProgress) }
        guard isSnapshotVerified, snapshotGeneration == generation,
              let snapshot else { return .denied(.snapshotUnverified) }
        guard snapshot.courseIDs.contains(courseID),
              let facts = snapshot.actionFactsByCourse[courseID] else {
            return .denied(.courseMissing)
        }

        let batchIDs = snapshot.batchIDsByCourse[courseID, default: []]
        guard !batchIDs.isEmpty else { return .denied(.missingBatch) }
        guard batchIDs.count == 1, let batchID = batchIDs.first else {
            return .denied(.ambiguousBatch)
        }

        switch kind {
        case .enroll:
            guard !facts.isSelected else { return .denied(.alreadySelected) }
            guard facts.selectionFlag == "1" else { return .denied(.unavailable) }
            guard !facts.isFull else { return .denied(.full) }
        case .drop:
            guard facts.isSelected else { return .denied(.notSelected) }
        }
        return .allowed(batchID: batchID)
    }

    @discardableResult
    mutating func beginAction(for courseID: String, kind: ElectiveActionKind,
                              generation: UInt64) -> ElectiveActionDecision {
        let decision = actionDecision(for: courseID, kind: kind, generation: generation)
        if case .allowed = decision { isActionInProgress = true }
        return decision
    }

    mutating func finishAction() {
        isActionInProgress = false
    }
}
