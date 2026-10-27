# Scoped Liquid Controls Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to execute the owned tasks. Do not revert others' edits.

**Goal:** Implement only the user's named Liquid Glass controls, meter, elective and tab transition changes.
**Architecture:** Retain native SwiftUI pages and system tab bar. Isolate geometry and navigation effects from business reads/mutations.
**Tech Stack:** SwiftUI/UIKit iOS 26, SF Symbols, existing Swift/Node runners and macOS CI.
**Spec:** docs/superpowers/specs/2026-10-26-scoped-liquid-controls-design.md

## Global Constraints

- Minimum recharge 10 yuan, existing 400/server maximum retained; no real payment or campus submission.
- Closed-channel copy exactly `选课通道暂未开启`; no removal or movement of filter/search controls by state.
- Preserve unrelated UI, current login/session fixes, system back gesture, payment safety and account ownership.
- Native public Liquid Glass controls; actual container corner centers, neutral form close controls.

## Review Focus

- Cancelled interactive pop restores the detail's tab-bar hidden state; completed pop restores home.
- Large text and home-indicator insets cannot hide submission controls or cause overlap.
- Server cap below 10 cannot yield a payable amount or an invalid wheel binding.
- Genuine elective transport/auth errors retain retries, distinct from channel closure.
- Enrolled/history reads remain independent of a closed catalog and retain stale-result ownership guards.

### Task 1: Academic filters and elective states (academic worker)

Own ScoreView.swift, ExamView.swift, ElectiveView.swift, ElectiveState.swift and scoped elective tests.
- [ ] Reproduce closed-channel handling with targeted failing production-state/load tests.
- [ ] Style score/exam filters as native glass symbol menus; preserve labels/term behavior.
- [ ] Anchor elective controls, classify closure precisely, refine elective controls/cards, retain enrolled/history.
- [ ] Run local relevant logic tests and Swift syntax checks; report modified files and evidence.

### Task 2: Campus controls and concentric forms (campus worker)

Own CampusRecordViews.swift, CampusFormView.swift; introduce a narrowly scoped helper only if needed.
- [ ] Make circular add controls native glass and align to the physical container corner centers.
- [ ] Neutralize form close controls and align submission/review capsules concentrically.
- [ ] Preserve all business/form behavior; validate layout logic and syntax, report geometry for simulator QA.

### Task 3: Meter and actual tab bar (parent)

Own MeterAmount.swift, EcardPaymentView.swift, EcardPaymentModel.swift, AcademicNavigation.swift,
NagiPageChrome.swift, CCSUTApp.swift if required, and scoped meter/navigation tests.
- [ ] Add failing 10-yuan boundary tests, then implement UI/model validation and valid digit ranges.
- [ ] Refine meter shell/readout while preserving wheel hit areas and payment state machine.
- [ ] Coordinate actual tab bar sink/fade using native navigation transitions, including cancellation/reduce motion.
- [ ] Review workers' diffs; add focused simulator checks/screenshots via existing dispatch workflows.
- [ ] Run final focused native validation and Release packaging, inspect images/IPA, record evidence.
