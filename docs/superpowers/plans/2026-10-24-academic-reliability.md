# Academic reliability implementation plan

> **For agentic workers:** Use test-first implementation with scoped ownership and independent review. The user's instruction to implement the accepted audit authorizes execution; no additional design approval is pending.

**Goal:** Correct protocol errors, incomplete results, academic dates/terms and enrollment recovery while preserving the current UI effects.

**Architecture:** Decode response envelopes explicitly before payloads. Publish multi-request results atomically so failed refreshes retain the previous complete snapshot with a visible status. Read academic terms from the official academic pages, independent of elective batch terms. Keep mutations single-flight and never automatically replay them after an uncertain response.

**Tech Stack:** Swift/SwiftUI iOS26; Foundation-only regression runners on Windows and macOS; existing macOS CI for Apple-framework compilation.

**Spec:** The user's 2026-10-24 approval of the 2026-10-23 audit, specifically protocol, data completeness, academic terms/weeks and enrollment. Excludes visual redesign, Flutter/tool cleanup, offline database and unrelated branding.

## Global constraints

- Preserve layout, glass, navigation, animation and established refresh-control behavior.
- No real SMS, enrollment or withdrawal requests for testing.
- Retain failed checks and distinguish pure-logic tests, macOS compilation and physical-device acceptance.
- Work from 24e3d3c in a dedicated worktree; retain the original checkout and audit artifact.
- Use existing verified endpoints. Invalid/missing official context must become an explicit error, never a fabricated semester or week.
- Do not automatically retry mutation POSTs.

## Review focus

- Error envelopes with data, or malformed payloads, must never become successful empty lists.
- A single failed batch/term must not replace a complete snapshot or enable writes with stale batch identifiers.
- Opening next-term enrollment must not move the current timetable/nearby exams into that term.
- Midnight/week changes, failed week refresh and account changes must not preserve a false 'today/current week'.
- Mutation timeout/authentication failure must not cause duplicate submissions or stale success messages.

## Task 1 — Response contracts (protocol worker)

Files: API.swift; new APIResponse.swift and APIResponseTests.swift. Root owns project/workflow registration.

- [x] Reproduce old decode behavior with error-with-data and malformed wrapped payload fixtures; record RED.
- [x] Introduce a Foundation-only decoder and move shared APIError there. Check ret before decoding payload. Never fall back to bare decoding after recognizing an envelope. Preserve existing supported bare endpoints.
- [x] Validate required list containers at score/exam/teaching-class boundaries; distinguish explicit empty arrays from missing data.
- [x] Verify normal wrapped/bare, empty, malformed, and nonzero ret responses; record GREEN.

## Task 2 — Elective snapshots and actions (elective worker)

Files: ElectiveView.swift; new ElectiveState.swift and ElectiveStateTests.swift. Do not edit Models/API/project files.

- [x] Add behavior tests for partial batch failure retaining a prior complete snapshot, removal of obsolete mappings, missing/ambiguous batch, unavailable/full course, and concurrent operation gating.
- [x] Commit classes and batchMap together only after all requested batches succeed. Failed refresh keeps content but invalidates mutation eligibility until verified again.
- [x] Render PageStatusNotice(message:retry:) only on exceptional paths; root provides this component.
- [x] Validate operation against the current snapshot on confirmation; globally block simultaneous writes. Renew authentication after rejection, refresh state and require new confirmation. On uncertain outcome reconcile with a read, never replay the write.
- [x] Keep existing card/details/dialog styling; rerun isolated behavior tests and preserve evidence.

## Task 3 — Academic context, dates and completeness (root)

Files: new AcademicCalendar.swift, AcademicAPI.swift and AcademicReliabilityTests.swift; Models.swift, SchedulePresentation.swift, ScheduleView.swift, ExamView.swift, AcademicView.swift, ScoreView.swift, PageSurface.swift; Session.swift if verified identity reuse is needed.

- [x] Pin RED fixtures for official page semester selection, dynamic term discovery, malformed weeks and stale teaching-week snapshots.
- [x] Parse current semester/xhid from the default timetable page (existing _p2 probe reads id=xnxq); parse exam terms from the official exam page's semester controls, with explicit failure on missing context.
- [x] Fetch calendar/current-week context without electiveInit.xkxnxq. Validate schedule week ranges before publishing. Use verified studentId for snapshot ownership.
- [x] Recompute current-day/current-week on foreground/date boundary, preserve manually selected week, invalidate stale verified-week fallback.
- [x] Replace hardcoded exam terms; publish complete exam results atomically and retain old data visibly on failure. Refresh nearby exams from the teaching semester.
- [x] Add an unobtrusive shared status row for failed refreshes; use it in all four existing content views.
- [x] Run behavior tests for semester rollover, odd/even weeks, invalid input, time boundaries, account mismatch and incomplete refresh.

## Task 4 — Integration and verification

- [x] Register new production files and standalone tests in Xcode/workflows; keep UI effects untouched.
- [x] Run Foundation regression runners, existing login-script and presentation/release checks, source whitespace checks, then independent review.
- [ ] Validate full iOS compilation and Apple session tests at the actual final SHA using macOS CI if available. Record failures rather than replacing them with unrelated green evidence.
- [ ] Deliver implementation status, exact verification evidence and remaining device acceptance boundaries. No main merge or publication is required.


## Implementation checkpoint before macOS CI

- Protocol regressions: old decoder reproduced accepting nonzero status with data and silently falling back on malformed payloads. New short-message and authentication classification checks first failed, then passed. Current runner: 28 checks pass.
- Elective state: initial test-first compilation required the new policy; a deliberate mutation restoring writes after a failed refresh failed its assertion. Current runner: 27 checks pass, including cookie-generation ownership and stale continuation rejection.
- Academic logic: original parser/cache failed 6 checks; new missing/blank-week cases failed 3 checks; a 30-day cache inside the fourth calendar-week boundary failed 1 check. All are now green: 24 checks pass.
- Existing regressions remain green: 8 timetable presentation checks, 1 release-preview guard, 6 embedded login-script tests. All production Swift files pass frontend parsing and git diff --check.
- Independent review identified and closed cross-request cookie-generation mixing, missing week data becoming all-weeks courses, old-account timetable retention, and disappearing exam reminders after a failed refresh.
- No change to normal page geometry, glass, navigation or animation definitions. Exceptional states gain a retry/status row; invalid or unverified elective actions are disabled.
- All network behavior tests use the URLProtocol fake. No school credentials, SMS, enrollment or withdrawal requests were sent.
- The two remaining checklist items are validation/delivery steps after this checkpoint. Their authoritative outcomes are the GitHub checks on the implementation commit and the task closeout; this document does not claim preemptive macOS or device acceptance.
- Final send-boundary review: mutations now carry the confirmation cookie generation into transport; generation validation and Cookie selection happen under the same lock. Stale A-to-B mutations must make zero network requests. TGC-only CAS redirect behavior is explicitly preserved by a fake-network regression.
