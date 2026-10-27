# Runtime and data-flow audit

**Audit snapshot:** d50b437 (codex/apple-design-refresh), read-only source review on 2026-10-26. At handoff, the root worktree is at 490eff9 and UI work is ongoing. Findings and checks below apply only to the audited d50b437 snapshot; subsequent source changes have not been audited here.

## Validated findings

### Medium: dismissing an ambiguous campus form submission discards its recovery state

A single form write can end with CampusFormError.unknownOutcome. CampusFormModel.submit keeps the approved submission only in the in-memory pending property and changes the state to .unknown (CampusFormModel.swift:117-133). In that state the close control and interactive sheet dismissal are enabled; onDisappear calls model.stop(), which clears pending (CampusFormView.swift:87-114, CampusFormModel.swift:166-179). A process exit also loses this state.

While the sheet stays open, the user can query records to reconcile a unique match. Reconciliation explicitly returns false whenever attachments were part of the submission (CampusFormsAPI.swift:234-242). After dismissing the unknown result or restarting the app, there is no saved submission to reconcile. The user can open a new form and manually submit another application. The app does not automatically resend the original write.

**Recommendation:** retain account-bound recovery state until the outcome is resolved, or provide a durable pending-operation path that prevents a new application from proceeding while the old result is unknown. Preserve the current single-send behavior.

### Low: a schedule cache retained the student ID after logout — fixed in the current worktree

TeachingWeekSnapshot includes the account string, and ScheduleView persists the encoded snapshot in UserDefaults under ccsut.teachingWeek.v1 (SchedulePresentation.swift:3-6, ScheduleView.swift:419-444). Logout removes the separate ccsut.student.name and ccsut.student.id entries, but does not remove this cache (Session.swift:534-544). The old student ID therefore remains in local preferences until a later successful schedule refresh replaces the snapshot.

**Resolution:** `SessionStore.logout()` now removes `ccsut.teachingWeek.v1` with the other account-bound profile data. `SessionRegressionTests.swift` asserts the cache is absent after logout. The focused `python ios/Tests/run-student-name-tests.py` harness first reproduced the failure from the extracted production logout method, then passed all 16 session-name/logout checks after the fix. `swiftc -frontend -parse ios/CCSUT/Session.swift` and `git diff --check` also passed. The WebKit-backed SessionRegressionTests binary was not run on this Windows host.

## Coverage

| Area | Evidence from this audit |
|---|---|
| Login, logout, account generations | Reviewed SessionStore, CookieJar, account-bound form/payment models, and historical regression coverage. Ran run-login-state-tests.py successfully. The WebKit-backed SessionRegressionTests.swift suite was not executable on this Windows host. |
| E-card payment and pending journal | Ran run-ecard-tests.py; API and model fixtures passed. The tests cover write-before-debit journaling, uncertain outcomes, account isolation, read recovery, and stale completion. |
| Campus records, forms, and validation | Ran the existing form model and API suites; both passed. Source review confirmed single-send writes, immutable confirmation, and read-only reconciliation. The ambiguous-result dismissal path above is not covered by those tests. |
| Schedule and academic periods | Ran AcademicReliabilityTests; all assertions passed. Reviewed official term parsing, schedule validation, retained snapshots on failed reads, and generation checks. |
| Electives and selected courses | Ran run-elective-load-tests.py; all assertions passed. Read paths retain prior results or mark snapshots unverified on failure; mutations reconcile by reading and do not automatically resubmit. |
| Navigation lifetime | Reviewed the page load gate and view tasks. Read-only loads may finish after a navigation caller disappears, but their publication paths check generation or request ownership; no cross-account publication issue was validated. No native navigation UI run was performed. |
| Privacy | Static review of local persistence and error/log paths. The schedule-cache account retention above is verified. Device backup, Keychain, and WebKit storage behavior were not exercised. |

## Verification limits

All executed checks used existing offline or synthetic fixtures on Windows and passed. No live school login, form submission, attachment upload, payment, native iOS build, simulator UI run, or physical-device run was performed in this audit. The results do not establish live school or device acceptance. This audit changed no product source.

## Follow-up review of the redesign

The initial findings above retain their original snapshot and evidence. A subsequent independent read-only review examined production changes from `d50b437` through `a52392b`: optional name/account-cookie generation isolation, Today versus selected-grid-week ownership, removed reminder requests, payment single-send/persisted recovery, record lifecycle and navigation routes. It found no new validated normal-use regression. The later physical-meter changes through `9ebbe3a` received a narrower review of amount limits, confirmation/recovery, selection retention, long balance rendering and actual control visibility. Those changes do not modify the application-submission recovery contract; the medium finding remains unresolved.

Native compilation, simulator interaction and Release package evidence are recorded separately in [Apple design verification](2026-10-26-apple-design-verification.md). They extend verification of the redesign without changing the original audit's evidence boundaries. Real account identity recovery, school writes, physical-device behavior and VoiceOver still require on-device acceptance.
