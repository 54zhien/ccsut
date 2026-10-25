# Campus automatic reauthentication repair

> Execute inline with systematic-debugging, test-driven-development and verification-before-completion. The user authorized investigation and repair in this chat.

**Goal:** Recover expired campus read sessions before asking the user to authenticate manually.

**Scope:** `CampusAPI.swift`, `EcardPaymentModel.swift`, `EcardTokenBridge.swift`, their regression runners, CI and authentication documentation. Preserve UI, account-generation guards, cookie persistence and single-attempt writes. Do not merge another branch or perform school mutations.

## Evidence and design

- Baseline `0ba6895`: 25 campus API checks and 41 form API checks pass locally on Swift 6.4.1.
- Stateless public probes on 2026-10-25: `validate_full` returns HTTP 200 / `errcode: 2001`; ehall CAS entry returns HTTP 302 to the official CAS login; both record APIs reject missing credentials with HTTP 401. No private responses or credentials are saved.
- Current retry calls `identity(force: true)`, but `force` only bypasses the in-memory dictionary. A successful validation response prevents the CAS renewal even after the business service rejected its token. Repeated validation can therefore resend the rejected credential and end at manual authentication.
- Trusted login redirects from read APIs throw the terminal authentication error instead of entering the bounded retry.
- E-card has a separate failure: `handleLoadError` clears rejected credentials but never starts the existing background SSO. Recover authentication failures from initial/selection reads once per loading cycle; leave payment failures terminal/pending. Factories isolate the external HTTP and SSO boundaries in model tests, without changing their production defaults.
- Independent review found that a recovery budget must rearm after a successful complete read, or a later idle expiry in the same page will still need manual recovery. For a single campus, initial metadata leads immediately to an automatic building read; do not rearm between those two reads, or a permanently rejected building endpoint can loop SSO. Add regressions for both repeated expiry and this cascade before the review fix.
- Final Release log review confirmed that the WebKit fallback's two `try? await callAsyncJavaScript` expressions select the synchronous callback overload with a nil callback. Their inferred return is `()?`, so casts to the portal action string and interaction Boolean always fail. Replace these two calls with explicit callback-to-continuation evaluation; preserve all URL/navigation/generation checks. This warning exists in the iOS Release build, not just the standalone macOS runner.
- Device-specific expired-session responses remain unavailable; synthetic RED/GREEN evidence establishes these code failure paths, not the school's exact session timeout.

Repair the existing recovery path rather than adding prewarming: a forced retry must obtain a new CAS service session and validate the requested subsystem; recognize only official login redirects as a recoverable read-auth failure. Never redirect a business POST to CAS or replay submissions, uploads or payments.

## Steps

- [x] Isolate from the existing campus branch and run baseline API/form checks.
- [x] Add failing tests for stale validation credentials, bounded retries, trusted read-login redirects, rejected foreign redirects and form metadata recovery.
- [x] Verify campus RED before product edits; retain logs outside the worktree.
- [x] Make force-renewal and read-redirect changes; preserve cancellation/account isolation and terminal failures.
- [x] Verify e-card model RED on macOS, then add bounded background read recovery and verify GREEN.
- [x] Verify GREEN and run all locally supported Foundation/JS suites.
- [x] Complete independent code review and macOS simulator build; report build and device acceptance separately.

## Review focus

- A valid CAS identity must match the App account before any resumed read.
- Failed/cancelled CAS must not publish stale credentials or continue sending business requests.
- Limit recovery to one attempt; never turn 403, arbitrary redirects or server errors into auth retry loops.
- Tests for form submissions and uploads must still prove single-attempt behavior.
- A real interactive CAS requirement must remain visible as an authentication failure, not an empty result.

## Verification record

- Local campus API RED: stale-validation recovery and both trusted-login redirect cases fail on the original implementation. Expanded checks also exercise bounded recovery, wrong-account validation and replacement during CAS. The final runner has 35 passing checks.
- Local form API RED: both metadata 401 and official-login 302 fail on the original implementation; final runner has 45 passing checks, including existing single-attempt submissions/uploads and reconciliation.
- Full local suite: 14 Swift runners / 329 checks, plus 14 JavaScript tests, all pass. WebKit and the payment model are validated separately on macOS.
- macOS RED at `2a167c9`: [40175035495](https://github.com/54zhien/ccsut/actions/runs/40175035495) compiles the model runner and fails the four missing recovery behaviors. Existing no-resend/payment and HTTP 500 behavior pass. This failed run is preserved.
- Intermediate application source `bdf1a9d8574c454461ce5c60ada360ea0de63b3f`: e-card model checks and the full workflow/simulator build pass in [40175196239](https://github.com/54zhien/ccsut/actions/runs/40175196239). This runner also compiles the production bridge, cookie stores and model rather than stubbing WebKit. This is not the final review-fixed candidate.
- Intermediate Release compilation/package [40175197384](https://github.com/54zhien/ccsut/actions/runs/40175197384) succeeds at the same source. IPA ZIP CRC, bundle `com.imzhien.ccsut`, display name `长工院`, iOS 26.0 floor and arm64 Mach-O verified. SHA-256 `a1efa769eb5d7394dbe8c8bbe60a8b562c4e500fc6ba77adc404fde9a357f5d4`. Preserve this provenance; final delivery must use the later review-fixed source.
- Review regression RED at `939fc8b`: [40175511322](https://github.com/54zhien/ccsut/actions/runs/40175511322) fails only the second-expiry check; the initial recovery, single-campus loop bound and no-resend checks pass. The review fix rearms after a complete successful read, with revision/generation/cancellation guards. Final tests cover both one- and multiple-campus success followed by a later expiry.
- Intermediate source `a476353`: native regression/simulator workflow [40175665692](https://github.com/54zhien/ccsut/actions/runs/40175665692) and Release [40175666553](https://github.com/54zhien/ccsut/actions/runs/40175666553) pass; package metadata/CRC verified, SHA-256 `9aae4e058bb3e5587bad0c4dc8fd349f690cf84091fe87bc6ad6c0cd6cd48deb`. The later JavaScript fallback repair supersedes this candidate.
- Initial fallback fixture attempt `3ce18dc`, [40176121308](https://github.com/54zhien/ccsut/actions/runs/40176121308), fails to compile because WebKit's Swift overlay is non-open and cannot be overridden. This is a fixture failure, not bug RED. Replace that fake with a real WebKit local-HTML fixture at `6ef0f55`; no school page request is sent.
- Real WebKit fallback RED at `6ef0f55`: [40176408644](https://github.com/54zhien/ccsut/actions/runs/40176408644) compiles, proves the local fixture's authentication origin and initial CAS click, then fails the interaction Boolean/one-time report and portal-action bookkeeping checks. The fix explicitly receives JavaScript callback results instead of discarding them as Void. No timing-only or compiler failure is counted as bug RED.
- Final application source `f22c8295146b00f016e8c6f58c1392f0abebfd83`: full native regression and simulator build [40176558520](https://github.com/54zhien/ccsut/actions/runs/40176558520) pass, including real WebKit local-HTML interaction/action results and repeated e-card expiry with one/multiple campuses. Release [40176559584](https://github.com/54zhien/ccsut/actions/runs/40176559584) passes; the previous ambiguous JavaScript-overload warnings are absent. No product code changes follow this verified source; this completion entry is documentation only.
- Final IPA metadata/ZIP CRC/arm64 validation passes; SHA-256 `6800d42b917d3b0e9c319853ac0c100b4ee699b178f943dfa7516ccfaacfdc53`. Earlier packages remain separate and are not the final delivery.
- Final independent review found no material product issue. Minor test-strength note: a duplicate portal didFinish could theoretically be suppressed while the first callback remains in flight; observed real-WebKit RED catches the original lost-result behavior. Existing revision/generation/navigation checks remain intact.
- Reviewable change: draft [PR #12](https://github.com/54zhien/ccsut/pull/12), based only on `codex/campus-optional-location`; neither it nor the existing campus PR is merged.
- No real payment, application, upload or authenticated student-data request was performed. The user's original idle-session response has not been captured; device idle/resume acceptance remains open. Do not infer a server timeout or guaranteed TGC renewal lifetime from these tests.
