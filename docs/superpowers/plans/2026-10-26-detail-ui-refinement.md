# Detail UI refinement implementation plan

> **For agentic workers:** execute the scoped UI tasks below in the existing owned worktree. Independent academic and campus tasks run in parallel; shared chrome/payment/login remain with the parent.

**Goal:** Apply the user's detailed 2026-10-26 UI request while preserving current authentication and business behavior.

**Architecture:** Keep SwiftUI, iOS 26 and existing theme/materials. Hide the bottom tab bar in pushed detail chrome, retain back navigation. Use native sheets/toolbars and wheel pickers; preserve APIs, payment confirmation, pending-order protection, form validation and refresh.

**Spec:** The user's current request is the binding visual specification. Delegated discretion: room selector layout, course hierarchy and native control spacing.

## Tasks

- [x] Shared chrome: `NagiPageChrome.swift` adds trailing actions and hides `.tabBar` in details; root pages retain tabs.
- [x] Academic: `ScoreView.swift`, `ExamView.swift` consolidate semester filtering at top right; clearer date/location; `EnrolledCourseView.swift`, `ElectiveView.swift` expose term selection and refine card hierarchy/capacity gap.
- [x] Campus: `CampusRecordViews.swift`, `CampusFormView.swift` use trailing circular add action, native sheet navigation/close, transparent blurred top, submit button without dock backing.
- [x] Payment: `EcardPaymentView.swift`, `CampusComponents.swift` use labeled room choices, three native amount wheels, rounded dock offset to home safe area. Amounts are whole yuan, 001–400, further restricted by positive configured limits. 400 only permits trailing 00; 000 cannot pay. Preserve backend validation and confirmation.
- [x] Login: `LoginView.swift` restore trailing spinner/countdown at the pre-centering location, preserving no-fade transitions and one sending task.
- [x] Verification: focused pure amount/date/location checks only where logic changes; simulator screenshot renders of affected pages in light/dark, inspect pixels/layout; compile/package exact source. No full suite, real payment or application submission.

## Review focus

Dynamic Type/wheel labels and 44pt touch targets; pop gesture restoring tabs; filters after refresh; 399→400 and configured limits; sheet dismissal during unknown/submitting state; pending payment guards.

## Decisions

The navigation bar request refers to bottom tabs, consistent with moving payment controls down. Preserve top back button/title. Spinner and countdown return to trailing alignment as in the source before the prior centering change. Final school daily cumulative cap remains server-authoritative; the UI does not invent remaining daily balance.
