# Leave Ticket Wallet Implementation Plan

> For agentic workers: use superpowers:executing-plans in this session.

Goal: Ship the approved leather wallet and one-time successful-submission ticket animation on codex/leave-ticket-wallet.
Architecture: Separate SwiftUI leave screen consuming CampusRecordsModel; pure submission-to-record matching policy; cancellable UIKit printer embedded only during emission.
Tech Stack: SwiftUI, UIKit, CoreHaptics, Foundation. No dependencies.
Spec: docs/superpowers/specs/2026-10-26-leave-ticket-wallet-design.md

## Constraints
Preserve travel pages and real submission logic. Use spring 0.52 / 0.06 / 0.08. Do not invent approval states or send real submissions. Retain pagination and authentication boundaries. No merge to main.

## Review focus
Ambiguous/new records must not print the wrong ticket; cancelled forms must not print; account changes invalidate pending animation; reduced motion and large text remain usable; interrupted animations stop haptics.

## Tasks
- [x] Test pure LeaveTicketReceipt matching (baseline exclusion, time/reason match, ambiguous records, exactly-once consume and reset), observe RED, implement and observe GREEN.
- [x] Add LeaveTicketWalletView with leather cover, adaptive tickets, background, expand/collapse, refresh/pagination/errors and sheet lifecycle. Add optional successful leave receipt callback in CampusFormView, preserve existing callers.
- [x] Add cancellable LeaveTicketPrinter UIViewRepresentable with clipped emission, visible lip, completion and haptic stop. Register files in Xcode project.
- [x] Add native wallet UI tests and workflow; run local checks and exact-branch macOS build/UI verification. Review whole diff and record remaining device-only acceptance.

## Execution ledger
User approved implementation. Execute inline. Current checkout is isolated. Main baseline is fe11d41; unrelated unmerged UI changes are excluded.


Review and verification ledger:
- Receipt RED: missing implementation, then GREEN on Windows Swift. Added malformed dates and ISO timezone cases: observed failing assertion, then GREEN after strict normalization.
- Fresh read-only review: corrected opaque scroll background and detached printer placement. Initial paper-layer finding was withdrawn after checking actual panel bounds. Moved continuous haptic stop to intake completion.
- Captured receipt from the approved form snapshot because CampusFormModel erases draft on success; callback runs after submit/reconcile success, independent of which dismissal control is used.
- ca9662f: native build, open/close/cancel, large text, dark capture and reduced-motion interaction passed in run 40308669148. Screenshots inspected; old background masking confirmed and fixed later.
- b4acb30: compile failure in debug conditional retained in runs 40309247360 / 40309247477. Corrected in f5fda59; no unchanged rerun used.
- 46adb92: run 40310331237 passed native build, 4/4 wallet interaction tests, dark capture and reduced-motion interaction. Business regressions passed in run 40310331258.
- No real application, attachment upload or payment was performed. Device haptics and frame pacing remain physical-device acceptance items.

- Final screenshot review: warm gradient and dark brown background visible; leather flap, stitches and paper edges visible; 8-ticket vertical layout and long reason wrapping inspected from native simulator output.
- c8a8173 changes only the retained refresh-test locator and its loaded-count assertion; Swift syntax parse passed. Its automatic CI is additional to the completed 46adb92 application-code checks and was still running at closeout.
- Branch remains separate and pushed; no merge or real school submission. No IPA was requested or produced in this task.

## Leather finish follow-up (2026-10-26)

User requested more refined shadows and stitching. Implementation commit: 150cafb.
- Added round thread strokes over darker needle holes, inset seam grooves, edge paint and fine bevel highlights.
- Replaced diagonal modular grain with deterministic scattered pores; detailed the brass clasp.
- Added narrow cover/contact shadows and a soft grouped ambient shadow. Geometry and animation parameters are unchanged.
- Native build, receipt policy, 4/4 UI tests, dark capture and reduced-motion interaction passed: run 40313022446.
- Existing business regressions passed: run 40313022375.
- Inspected native closed/open/light/dark screenshots: seams remain readable, paper edges remain visible, and shadows do not obscure the ticket content.
- Physical-device visual and haptic acceptance remains separate. Branch not merged.
