# Session recovery implementation plan

**Goal:** Fix Cookie ownership, CAS renewal, failed login feedback, and cold-start completion.
**Scope:** User request dated 2026-10-23. Preserve all business views, layouts, animations, and selection behavior.
**Architecture:** Keep the existing WebView login and URLSession business requests. Use CookieJar as the single native Cookie source, with Keychain persistence and explicit redirect handling. Report login errors through the existing hint.
**Execution:** Implement inline in the clean checkout on `fix/session-cookie-recovery`; no new worktree is necessary. User has already authorized these fixes.

## Tasks
- [x] Add behavioral regression tests against the existing Swift session and embedded login script; record failures before implementation.
- [x] Unify Cookie reads/writes, expiry filtering, response rotation persistence, and logout cleanup; preserve HTTPOnly on restore.
- [x] Use the nonredirecting transport, validate authentication and HTTP responses, bound redirect time, and terminate startup after failures. Prevent in-flight work from restoring a logged-out session.
- [x] Observe SMS/login failure and timeout, release busy state, and avoid duplicate Cookie adoption. Keep the login layout intact.
- [x] Run regression tests on macOS, compile the complete iOS app, review the scoped diff, and report runtime acceptance limits.

## Review focus
- CAS returns its login page with HTTP 200; this is not authentication success.
- HTTP 503/timeouts during bootstrap must not leave `.checking` or `.refreshing`.
- A rotated Cookie must survive restart; a response arriving after logout must not resurrect it.
- Redirects must send each host only its own unexpired Cookies and honor Cookie paths.
- SMS rejection, invalid codes, and no response must all allow a retry.

## Evidence
Baseline: `a8981475ee842b4168fe224694bcbf67e2a4e6d7`; clean checkout; no pre-existing test target. Windows has Swift but no Apple SDK, so compile/run the actual Apple session sources in macOS CI. Run the actual embedded JavaScript locally with controlled DOM responses.

Regression evidence: c1ff066 failed on the original session defects; 2baf565 failed on unverified Cookie persistence; 7bfa495 passed all 30 Swift checks and 6 embedded-script tests and compiled/packaged the complete iOS app. Subsequent review guards add coverage for successful adoption and post-logout profile/Store isolation. Final commit CI is linked from the pull request. No physical-device acceptance is claimed.
