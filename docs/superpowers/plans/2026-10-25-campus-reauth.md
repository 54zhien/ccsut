# Campus automatic reauthentication repair

> Execute inline with systematic-debugging, test-driven-development and verification-before-completion. The user authorized investigation and repair in this chat.

**Goal:** Recover expired campus read sessions before asking the user to authenticate manually.

**Scope:** `CampusAPI.swift`, `EcardPaymentModel.swift`, their regression runners, CI and authentication documentation. Preserve UI, account-generation guards, cookie persistence and single-attempt writes. Do not merge another branch or perform school mutations.

## Evidence and design

- Baseline `0ba6895`: 25 campus API checks and 41 form API checks pass locally on Swift 6.4.1.
- Stateless public probes on 2026-10-25: `validate_full` returns HTTP 200 / `errcode: 2001`; ehall CAS entry returns HTTP 302 to the official CAS login; both record APIs reject missing credentials with HTTP 401. No private responses or credentials are saved.
- Current retry calls `identity(force: true)`, but `force` only bypasses the in-memory dictionary. A successful validation response prevents the CAS renewal even after the business service rejected its token. Repeated validation can therefore resend the rejected credential and end at manual authentication.
- Trusted login redirects from read APIs throw the terminal authentication error instead of entering the bounded retry.
- E-card has a separate failure: `handleLoadError` clears rejected credentials but never starts the existing background SSO. Recover authentication failures from initial/selection reads once per loading cycle; leave payment failures terminal/pending. Factories isolate the external HTTP and SSO boundaries in model tests, without changing their production defaults.
- Device-specific expired-session responses remain unavailable; synthetic RED/GREEN evidence establishes these code failure paths, not the school's exact session timeout.

Repair the existing recovery path rather than adding prewarming: a forced retry must obtain a new CAS service session and validate the requested subsystem; recognize only official login redirects as a recoverable read-auth failure. Never redirect a business POST to CAS or replay submissions, uploads or payments.

## Steps

- [x] Isolate from the existing campus branch and run baseline API/form checks.
- [x] Add failing tests for stale validation credentials, bounded retries, trusted read-login redirects, rejected foreign redirects and form metadata recovery.
- [x] Verify campus RED before product edits; retain logs outside the worktree.
- [x] Make force-renewal and read-redirect changes; preserve cancellation/account isolation and terminal failures.
- [ ] Verify e-card model RED on macOS, then add bounded background read recovery and verify GREEN.
- [ ] Verify GREEN, run all locally supported Foundation/JS suites, and review the complete diff.
- [ ] Compile the exact change with macOS CI where available; report build and device acceptance separately.

## Review focus

- A valid CAS identity must match the App account before any resumed read.
- Failed/cancelled CAS must not publish stale credentials or continue sending business requests.
- Limit recovery to one attempt; never turn 403, arbitrary redirects or server errors into auth retry loops.
- Tests for form submissions and uploads must still prove single-attempt behavior.
- A real interactive CAS requirement must remain visible as an authentication failure, not an empty result.
