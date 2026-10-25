# Reviewed integration fixes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Repair all five premerge findings, validate the combined latest feature heads, and merge the verified result into main as authorized by the user.

**Architecture:** Keep the existing integrated feature history. Stage campus authentication cookies until account validation succeeds; preserve request ownership and explicit authentication recovery boundaries. Retain approved UI and payment semantics.

**Tech Stack:** Swift, SwiftUI, WebKit, offline protocol fixtures, native macOS GitHub Actions.

**Spec:** The user's 2026-10-25 request to fix the five findings from the preceding premerge review, test, independently review, and merge if clean.

## Global Constraints

- No live school login, payment, application, upload, or automatic mutation retry.
- No history rewriting, source-branch deletion, or removal/rerun of failed CI evidence.
- Preserve the approved material top blur, native refresh interaction, selected-course history, and payment journal fail-closed behavior.
- Main may change only after the final combined source revision passes relevant checks and independent review.

## Review Focus

- Wrong-account, invalid, canceled, and generation-replaced authentication must publish no staged cookies.
- Successful authentication must use staged rotations/deletions across hops and commit them only after identity validation.
- Only default/80 HTTP and default/443 HTTPS ports are trusted.
- A joined selected-course refresh must preserve its owner's completed result; catalog failures remain visible in the selected filter.
- 403 and arbitrary redirects must not trigger background authentication or replay payment; explicit login rejection remains recoverable.

### Task 1: Campus cookie transaction and URL policy

**Files:** ios/CCSUT/CampusAPI.swift; ios/Tests/CampusAPITests.swift; related campus fixture tests only if required.

- [ ] Add offline failing fixtures for wrong identity with Set-Cookie, failed/canceled renewal, successful staged rotation, cookie deletion/scope, explicit HTTP :80 and rejected ports.
- [ ] Run and preserve behavioral RED output, then stage cookie changes per authentication attempt and commit only after matching identity/token validation.
- [ ] Normalize trusted HTTP nil/80 to HTTPS without changing encoded query/path; reject abnormal ports and credentials/fragments.
- [ ] Run the campus API/forms regressions and independently review the diff.

### Task 2: Selected-course refresh ownership and error visibility

**Files:** ios/CCSUT/ElectiveView.swift; ios/Tests/PageInteractionUITests.swift; narrow test fixture/runner files as needed.

- [ ] Preserve the already reproduced load-gate race as a runnable test against the production load path; confirm it fails before fixing.
- [ ] Move enrolled invalidation inside the owning gate action so joined calls cannot invalidate its request.
- [ ] Add a synthetic catalog failure with successful selected results, require visible catalog error/retry and read-only records, then show that notice in the selected filter.
- [ ] Run selected-results and relevant native UI checks; preserve existing layout and action permissions.

### Task 3: E-card read error classification and combined validation

**Files:** ios/CCSUT/EcardAPI.swift; ios/Tests/EcardReadRecoveryTests.swift; relevant workflows/test runners; integration evidence document.

- [ ] Add failing synthetic read fixtures for 403, arbitrary redirects, exact trusted login redirects and 401; assert only explicit authentication failures renew once, and mutation requests never replay.
- [ ] Narrow authentication classification while retaining uncertain-payment handling.
- [ ] Resolve test/build integration issues without discarding either branch's regressions; run all local supported regressions.
- [ ] Push a reviewable integration branch/PR; run native full regressions, Debug/Release builds, selected-results, payment recovery and focused refresh UI checks on the final combined revision.
- [ ] Perform independent final review, address actionable findings, reverify any changed source, then merge with an expected-head lease and verify remote main.
