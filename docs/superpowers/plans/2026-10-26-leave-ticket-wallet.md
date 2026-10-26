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
- [ ] Test pure LeaveTicketReceipt matching (baseline exclusion, time/reason match, ambiguous records, exactly-once consume and reset), observe RED, implement and observe GREEN.
- [ ] Add LeaveTicketWalletView with leather cover, adaptive tickets, background, expand/collapse, refresh/pagination/errors and sheet lifecycle. Add optional successful leave receipt callback in CampusFormView, preserve existing callers.
- [ ] Add cancellable LeaveTicketPrinter UIViewRepresentable with clipped emission, visible lip, completion and haptic stop. Register files in Xcode project.
- [ ] Add native wallet UI tests and workflow; run local checks and exact-branch macOS build/UI verification. Review whole diff and record remaining device-only acceptance.

## Execution ledger
User approved implementation. Execute inline. Current checkout is isolated. Main baseline is fe11d41; unrelated unmerged UI changes are excluded.
