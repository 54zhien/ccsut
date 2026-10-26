# Apple design refresh implementation plan

> Execute in the current session using executing-plans; independent identity diagnosis and read-only usage audit run under dispatching-parallel-agents.

**Goal:** Deliver the requested coherent native redesign with reliable identity, centered record states and short-distance tab transitions.
**Architecture:** Preserve existing data ownership and native navigation; introduce shared content presentation in PageSurface. Use current school identity evidence for optional names. Keep payment and application actions unchanged.
**Tech Stack:** SwiftUI/UIKit, iOS 26, Swift 6; Windows pure Swift tests and macOS GitHub Actions.
**Spec:** ../specs/2026-10-26-apple-design-refresh.md

## Global constraints

- Start at d50b437 and preserve all existing authentication/payment repairs.
- Native controls, semantic colors, SF Symbols. No decorative content glass.
- Keep API/write semantics stable and preserve failed-run provenance.
- Keep no-name login valid and never transfer a name between accounts.

## Review focus

1. Rapid back and cancelled interactive pop must restore a usable tab bar.
2. First loading, empty results, and record refresh must share usable viewport geometry.
3. Long text, accessibility font sizes and landscape must retain reachable controls.
4. Selection-closed login must show an available verified name without blocking login.
5. Room changes/pending payment must never allow duplicate or mismatched payment.

## Task 1: Regressions and identity
- [ ] Add and run identity/name regressions before repair; preserve account-generation checks.
- [ ] Add native record-loading and short tab-travel assertions; run against baseline where supported.
- [ ] Audit existing session/payment/forms/data ownership and record validated findings.
Files: Session.swift, Models.swift, API.swift, relevant identity tests; PageInteractionUITests.swift.

## Task 2: Main pages and detail system
- [ ] Add reusable content helpers in PageSurface.swift (section headings, service entries, detail information, loading indicator).
- [ ] Apply to AcademicView, CampusView, ScheduleView and all their detail sheets.
- [ ] Rework score/exam/elective content hierarchy and native control consistency.
- [ ] Center CampusRecordViews loading and empty states using measured viewport/header.
Consumes: existing data models and navigation IDs. Produces: presentation only; preserves IDs/actions.

## Task 3: Meter and navigation controls
- [ ] Restyle EcardPaymentView with semantic content surfaces and native amount wheels; preserve 10–400 limits and server limits.
- [ ] Make WebLoginSheet refresh and dismiss controls share symbol metrics and circle dimensions.
- [ ] Change AcademicNavigation displacement to 20pt while retaining transition coordination and cancellation.
Verification: meter regression, native selection UI, tab restore/cancel/Reduce Motion tests.

## Task 4: Verify and deliver
- [ ] Run appropriate local regression suites, native source CI and screenshot/UI checks.
- [ ] Inspect actual light/dark screenshots and fix visual defects before delivery.
- [ ] Fresh branch review with focus list above; validate any important fixes.
- [ ] Commit, publish reviewable branch/draft PR, compile Release package and record evidence. Do not merge without a user request.

## Execution notes

Pre-flight: common presentation helpers are owned by the main implementer; the identity worker owns Session/Models/API and identity tests only; usage audit is read-only. Shared models remain source-compatible. User delegated design choices and implementation in the current request; no additional design approval loop is introduced.
