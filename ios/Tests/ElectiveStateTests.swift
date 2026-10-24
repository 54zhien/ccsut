import Foundation

@main
struct ElectiveStateTests {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }

        func record(_ id: String, _ title: String, selected: Bool = false,
                    selectable: String? = "1", full: Bool = false) -> ElectiveCourseRecord<String> {
            ElectiveCourseRecord(
                id: id,
                value: title,
                actionFacts: ElectiveCourseActionFacts(
                    isSelected: selected,
                    selectionFlag: selectable,
                    isFull: full
                )
            )
        }

        var priorBuilder = ElectiveSnapshotBuilder<String>()
        priorBuilder.append([record("old", "旧课程")], batchID: "old-batch")
        var state = ElectiveState<String>()
        state.publish(priorBuilder.snapshot, generation: 1)
        state.refreshStarted(generation: 1)
        check(state.actionDecision(for: "old", kind: .enroll, generation: 1) == .denied(.snapshotUnverified),
              "writes are disabled while a refresh is still in progress")
        state.refreshFailed()
        check(state.snapshot?.courses == ["旧课程"], "failed batch refresh keeps the complete prior course list")
        check(state.snapshot?.batchIDsByCourse["old"] == ["old-batch"], "failed batch refresh keeps the prior batch mapping")
        check(state.actionDecision(for: "old", kind: .enroll, generation: 1) == .denied(.snapshotUnverified),
              "failed batch refresh disables writes until another snapshot verifies")

        var replacementBuilder = ElectiveSnapshotBuilder<String>()
        replacementBuilder.append([record("new", "新课程")], batchID: "new-batch")
        state.publish(replacementBuilder.snapshot, generation: 1)
        check(state.snapshot?.batchIDsByCourse["old"] == nil
              && state.snapshot?.batchIDsByCourse["new"] == ["new-batch"],
              "successful snapshot replacement removes obsolete batch mappings")
        check(state.actionDecision(for: "new", kind: .enroll, generation: 1) == .allowed(batchID: "new-batch"),
              "successful replacement re-enables writes for the newly verified snapshot")
        check(state.actionDecision(for: "old", kind: .enroll, generation: 1) == .denied(.courseMissing),
              "action confirmation rejects a course removed by the latest snapshot")

        var unbatchedBuilder = ElectiveSnapshotBuilder<String>()
        unbatchedBuilder.append([record("unmapped", "无批次课程")])
        var unbatchedState = ElectiveState<String>()
        unbatchedState.publish(unbatchedBuilder.snapshot, generation: 1)
        check(unbatchedState.actionDecision(for: "unmapped", kind: .enroll, generation: 1) == .denied(.missingBatch),
              "course without a pcid cannot be enrolled")

        var ambiguousBuilder = ElectiveSnapshotBuilder<String>()
        ambiguousBuilder.append([record("ambiguous", "跨批次课程")], batchID: "batch-a")
        ambiguousBuilder.append([record("ambiguous", "跨批次课程")], batchID: "batch-b")
        var ambiguousState = ElectiveState<String>()
        ambiguousState.publish(ambiguousBuilder.snapshot, generation: 1)
        check(ambiguousState.snapshot?.courses == ["跨批次课程"],
              "duplicate course rows are displayed once across batch responses")
        check(ambiguousState.snapshot?.batchIDsByCourse["ambiguous"] == ["batch-a", "batch-b"],
              "duplicate course rows retain every source batch for ambiguity checks")
        check(ambiguousState.actionDecision(for: "ambiguous", kind: .enroll, generation: 1) == .denied(.ambiguousBatch),
              "course present in multiple batches is never assigned an arbitrary pcid")

        var unavailableBuilder = ElectiveSnapshotBuilder<String>()
        unavailableBuilder.append([record("unavailable", "不可选", selectable: "0")], batchID: "batch")
        unavailableBuilder.append([record("full", "已满", full: true)], batchID: "batch")
        var availabilityState = ElectiveState<String>()
        availabilityState.publish(unavailableBuilder.snapshot, generation: 1)
        check(availabilityState.actionDecision(for: "unavailable", kind: .enroll, generation: 1) == .denied(.unavailable),
              "sfkxk other than one disables enrollment")
        check(availabilityState.actionDecision(for: "full", kind: .enroll, generation: 1) == .denied(.full),
              "full course disables enrollment")

        var selectedBuilder = ElectiveSnapshotBuilder<String>()
        selectedBuilder.append([record("selected", "已选课程", selected: true, selectable: "0", full: true)],
                               batchID: "batch")
        var selectedState = ElectiveState<String>()
        selectedState.publish(selectedBuilder.snapshot, generation: 1)
        check(selectedState.actionDecision(for: "selected", kind: .drop, generation: 1) == .allowed(batchID: "batch"),
              "selected course remains droppable when it is unavailable or full")

        var concurrentBuilder = ElectiveSnapshotBuilder<String>()
        concurrentBuilder.append([record("first", "第一门"), record("second", "第二门")], batchID: "batch")
        var concurrentState = ElectiveState<String>()
        concurrentState.publish(concurrentBuilder.snapshot, generation: 1)
        check(concurrentState.beginAction(for: "first", kind: .enroll, generation: 1) == .allowed(batchID: "batch"),
              "first eligible mutation acquires the global action gate")
        check(concurrentState.beginAction(for: "second", kind: .enroll, generation: 1) == .denied(.actionInProgress),
              "a second mutation is rejected while any write is in progress")
        concurrentState.finishAction()
        check(concurrentState.beginAction(for: "second", kind: .enroll, generation: 1) == .allowed(batchID: "batch"),
              "global action gate is released after a mutation finishes")
        concurrentState.finishAction()

        var staleActionBuilder = ElectiveSnapshotBuilder<String>()
        staleActionBuilder.append([record("changed", "状态已变化")], batchID: "batch")
        var staleActionState = ElectiveState<String>()
        staleActionState.publish(staleActionBuilder.snapshot, generation: 1)
        check(staleActionState.beginAction(for: "changed", kind: .drop, generation: 1) == .denied(.notSelected),
              "confirmation rechecks selected state from the current snapshot")

        var accountBuilder = ElectiveSnapshotBuilder<String>()
        accountBuilder.append([record("account-course", "账号课程")], batchID: "account-batch")
        var accountState = ElectiveState<String>()
        accountState.publish(accountBuilder.snapshot, generation: 41)
        check(accountState.actionDecision(for: "account-course", kind: .enroll, generation: 41)
              == .allowed(batchID: "account-batch"),
              "a verified snapshot can be used only by its owning cookie generation")
        check(accountState.beginAction(for: "account-course", kind: .enroll, generation: 42)
              == .denied(.snapshotUnverified) && !accountState.isActionInProgress,
              "confirmation rejects a snapshot after the account cookie generation changes")
        check(accountState.discardIfGenerationChanged(expected: 41, current: 42)
              && accountState.snapshot == nil,
              "an account switch discards the previous account snapshot")
        check(accountState.actionDecision(for: "account-course", kind: .enroll, generation: 42)
              == .denied(.snapshotUnverified),
              "discarded account data cannot be written until the new account is verified")

        var staleContinuationState = ElectiveState<String>()
        staleContinuationState.publish(accountBuilder.snapshot, generation: 41)
        let canReconcileOldMutation = ElectiveMutationRecovery.canContinueAfterAwait(
            expectedGeneration: 41,
            currentGeneration: 42,
            state: &staleContinuationState
        )
        check(!canReconcileOldMutation && staleContinuationState.snapshot == nil
              && !staleContinuationState.isSnapshotVerified,
              "a cancelled or completed mutation from the prior account cannot reconcile against the new session")

        var accountRefreshState = ElectiveState<String>()
        accountRefreshState.publish(accountBuilder.snapshot, generation: 41)
        check(accountRefreshState.refreshStarted(generation: 42)
              && accountRefreshState.snapshot?.courses == nil,
              "starting a refresh under a different cookie generation clears old account content")

        var sameAccountState = ElectiveState<String>()
        sameAccountState.publish(accountBuilder.snapshot, generation: 41)
        sameAccountState.refreshStarted(generation: 41)
        sameAccountState.refreshFailed()
        check(sameAccountState.snapshot?.courses == ["账号课程"]
              && sameAccountState.actionDecision(for: "account-course", kind: .enroll, generation: 41)
                    == .denied(.snapshotUnverified),
              "a failed refresh for the same account retains content but disables mutations")

        check(ElectiveMutationRecovery.isAuthenticationRejection("会话已失效，请重新登录"),
              "explicit business authentication rejection triggers renewal and a fresh read")
        check(!ElectiveMutationRecovery.isAuthenticationRejection("当前批次已选门数超过上限"),
              "ordinary business rejection is not treated as an authentication failure")

        print("Elective state failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
