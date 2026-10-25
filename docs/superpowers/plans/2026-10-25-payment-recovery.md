# Payment Recovery Implementation Plan

> Execution: inline in this chat; one independent branch review after implementation.

**Goal:** Preserve pending orders before debit, retain uncertain order IDs, and repair payment startup/recovery states.
**Architecture:** Existing API and observable model, atomic per-account receipt store, injected offline boundaries; unchanged View.
**Tech Stack:** Swift Foundation/Observation, WebKit on macOS, standalone Swift runners and existing Actions gate.
**Spec:** `docs/superpowers/specs/2026-10-25-payment-recovery-design.md` (user-authorized scope above).

## Global Constraints
- No changes to View files, other features, real accounts, payments, repository visibility or history.
- Base 0ba6895; dedicated codex/payment-recovery branch.
- Preserve RED provenance. Every payment fixture is synthetic and every journal isolated.

## Review Focus
- Restart while payment is in flight must recover the original order.
- Storage errors must stop debit; corrupt/migrating records must not unlock payment.
- Business error, timeout, cancellation, and failed reconciliation must retain the order.
- Old login, initialization, query, or payment completions must not publish into replacement sessions.
- Checking/re-authentication must retain pending state and never create a replacement order.

### Task 1: Regressions and test boundaries
Files: `ios/Tests/EcardPaymentModelTests.swift`, `ios/Tests/EcardPaymentPlatformStubs.swift`, `ios/CCSUT/EcardPaymentModel.swift` (dependency seams only), `ios/CCSUT/EcardAPI.swift` (portable import only).
- [x] Record existing standalone baseline and prior-source behavioral failures.
- [x] Add injectable boundaries and offline fixtures; observe behavioral RED for journal timing, uncertain business errors, startup invalidation, corruption, and stale tasks.

### Task 2: Payment recovery and state repairs
Files: `ios/CCSUT/EcardPaymentPersistence.swift`, `ios/CCSUT/EcardAPI.swift`, `ios/CCSUT/EcardPaymentModel.swift`, Xcode source registration.
- [x] Add atomic account journal and legacy migration; test account isolation, corrupt data and conditional clear.
- [x] Add awaited before-payment checkpoint; no debit on checkpoint failure; reconcile uncertain errors while retaining ID.
- [x] Repair startup supersession/invalidation and pending recovery; prevent stale completion and duplicate submission.
- [x] Run new suite GREEN plus related existing regressions.

### Task 3: Native gate and review
Files: `.github/workflows/session-tests.yml`, this evidence record.
- [x] Add actual-WebKit model runner to existing regression gate; keep the app build.
- [x] Review allowlist and obtain independent code review, fixing material findings with regression evidence.
- [ ] Commit/push dedicated branch and draft PR; run full native gate on exact HEAD, preserve all failed runs, report native/device limits separately.

## Evidence and decisions
- Starting design is the accepted review scope, not the GLM document's action list.
- Temporary analysis probes reproduced journal absence during payment, lost order on business 500, and both invalid startup states before implementation.
- API RED: 5 behavioral failures (business 500, success=false, and reconciliation), not compile errors. API GREEN after conservative original-order reconciliation: 7 assertions.
- Model RED after dependency-only seams: 16 behavioral failures. Includes both startup invalidations, restart before response, failed storage, legacy migration/corruption, conflicting order replacement, and cross-account late check erasing the wrong receipt.
- The initial store deliberately retains the old defaults-backed behavior for this RED checkpoint; atomic persistence is the next task.
- Native RED confirmed at 05d44b7: https://github.com/54zhien/ccsut/actions/runs/40164094086. Actual WebKit runner reproduced the same 16 model failures; no rerun or failure removal.
- Atomic journal and scoped startup/payment/check repairs turned the original model suite GREEN locally. Added cancellation, late-payment completion, auth recovery, closed login, and corrupt-file cases.
- Boundary RED: interrupted legacy migration could resurrect a completed order (one failure); retire the legacy shadow after validating the durable file.
- Intermediate native GREEN at ae90c1c: https://github.com/54zhien/ccsut/actions/runs/40164422856 (all regression steps and iOS simulator app build). This predates the final review repairs below and is not final-head acceptance.
- Independent review identified the legacy-flush resurrection and stale login-sheet dismissal. Both are addressed: an atomic versioned cleared marker defeats restored older defaults (one new RED), and dismissal identity prevents A's delayed callback canceling B's login (two new RED assertions).
- Related local regressions: 33 native SSO, 39 academic, and 14 embedded-JavaScript assertions passed. No View file changed; no school writes, payments, or real credentials used.
- Ruling: business errors after debit remain pending unless the original-order query proves completion. This can conservatively require manual reconciliation for a declined order; no backend contract proves such error responses exclude side effects.
- Deferred review limitation: direct future callers of the API could omit its optional checkpoint; the only production recharge caller is this model and it supplies the checkpoint. Backend, real-device payment, and power-loss validation are outside this repair's evidence.
