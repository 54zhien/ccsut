# Complete selected courses implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show complete personal courses including past terms and unavailable batches without enlarging mutation authority.
**Architecture:** Add a strict read-only grid client and independent account/term snapshot. The selected filter consumes that snapshot; only exact verified current catalog matches reuse existing action decisions.
**Tech Stack:** Swift/Foundation, SwiftUI, standalone Swift runners, Xcode simulator UI tests.
**Spec:** docs/superpowers/specs/2026-10-25-complete-selected-courses-design.md

## Global Constraints

- No changes to enrollment/withdrawal request formats, authentication protections, payment, or unrelated pages.
- Only official page-advertised terms; historical terms always read-only.
- No credentials or personal captures in git. Draft PR only; never merge.

## Review Focus

- A result page with absent/malformed rows or inconsistent totals must not become an empty success.
- A later page failure must not replace a complete prior result.
- Account/term changes must discard old content and late continuations.
- Unknown status, missing identifiers or conflicting active selection must not enable writes.
- Empty active batches must not hide complete personal courses; history must not overwrite current summary.

### Task 1: Read-only contract and state

**Files:** Create ios/CCSUT/EnrolledCourses.swift, ios/Tests/EnrolledCoursesTests.swift; modify ios/CCSUT/API.swift and project registration/CI sources.
**Interfaces:** EnrolledCourse; EnrolledCoursesContext.parse(html:); EnrolledCoursesLoader.load(term:fetch:); EnrolledCoursesState; APIClient.enrolledCourses(term:expectedGeneration:).

- [ ] Write literal-fixture tests for terms, strict flat-grid status/pages, complete current/history results, bad later page, term mismatch, duplicate ids, owner/term/request changes and conservative current-course matching.
- [ ] Run tests against minimal missing-feature scaffolding and retain actual failing assertions.
- [ ] Implement strict parser/loader/state and API integration; retain generic APIResponseDecoder rules.
- [ ] Run local Foundation runners and existing elective state/API response suites; expect zero failures.
- [ ] Commit exact allowlist.

### Task 2: Selected filter and history UI

**Files:** Modify ios/CCSUT/ElectiveView.swift, ios/CCSUT/InterfacePreview.swift, ios/Tests/PageInteractionUITests.swift; add focused read-only presentation file if needed; wire CI preview checks.
**Interfaces:** Task 1 record/context/state; exact current catalog matching; existing ElectiveState actionDecision remains authority.

- [ ] Add regression for selected-only closed-batch/assigned rows and historical selection without action controls. Exercise empty catalog and failed selected load.
- [ ] Route selected filter/search/header to independent records and add official-term menu. Use read-only cards/details for unmatched/history records; preserve current catalog views and action requests.
- [ ] Refresh both sources after existing mutation reconciliation; keep independent errors and generation/request guards.
- [ ] Run full session CI and simulator build/UI checks at exact head; preserve any failed runs. Inspect light/dark/large-text captures.
- [ ] Review whole diff with a fresh read-only reviewer; fix demonstrated important defects with RED/GREEN evidence.
- [ ] Create and attach standalone draft PR based on codex/journal-recovery-entry, never merge.
