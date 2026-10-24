# Native ecard SSO implementation plan

> Execute inline after the existing f7c8e30 CI failure is diagnosed and repaired. User approved this approach and requested a packaged IPA.

**Goal:** Reuse the existing verified CAS session for native electricity-payment authentication, with official WebView interaction as fallback.

**Architecture:** A Foundation-only native SSO client follows only observed official routes, manually handles redirects/cookies, exchanges an in-memory transit ticket, validates the returned account and JWT, and returns a memory-only payment token. The payment model and background prefetch prefer this path. A failed native attempt can hand the existing session to the official WebView; genuine account mismatch/cancellation cannot be treated as a retryable login. Keep native business requests authoritative instead of overwriting their cookies with a stale WebKit snapshot.

**Constraints:** No personal capture fixtures, ticket values, session values, or raw query URLs in repository/output. Tests use synthetic values. Only authentication and read-only queries may be exercised against the school. No payment, application, upload, or other business submission. No promise of indefinite server-side session lifetime. Preserve UI and all unrelated worktrees.

## Tasks

- [x] Diagnose CI 40102806088 with explicit WebKit preconditions and deterministic Foundation regressions; commit the scoped fix and confirm a fresh exact-head macOS CI without erasing the failed run. `6f0187e` normalized cookie identity; run 40104789995 then proved the non-HttpOnly replacement fixture failed before restoration. `ad7d103` preserves HttpOnly in that fixture; exact-head run 40104980301 passed.
- [ ] Verify the observed native handshake in an isolated in-memory cookie jar. Discover configuration rather than copy personal/device/session state. Record only sanitized stage outcomes.
- [x] Add EcardSSOClient and synthetic transport tests for successful fresh/restored sessions, per-hop cookies/rotation, GET/POST restrictions, hostile redirect/nested URL/header injection, identity/expiry, timeout, cancellation and logout. All 31 standalone synthetic checks passed on Windows. Cookie changes remain staged until final identity/expiry validation succeeds; normalized identities support rotation and deletion.
- [x] Integrate native-first login/prewarm and WebView fallback, including native cookie authority and generation guards. Register sources/tests in Xcode and CI. Bridge tests cover native success, interactive fallback, wrong-account errors and JWTs, untrusted redirects, cancellation, cache invalidation and account switches. Independent final source review found no remaining confirmed blocker. Full WebKit execution remains a macOS CI gate.
- [ ] Review, run targeted regressions and exact-head macOS validation, then build Release unsigned IPA from the same commit, download and inspect packaging, and deliver it. Distinguish device acceptance from build/test evidence.

## Review focus

One-time tickets must not be replayed blindly; authentication headers must stay on their intended host; native cookie rotation must not be overwritten by WebKit; malformed/offline failures must not be reported as a proven expired TGC; logout and account changes must reject late tokens/cookies.

## Live verification boundary

The available reference TGC reached the interactive CAS login page. Fresh browser authentication could not be retained by the available browser connection; no live native SSO success has been established. The captures verify ticket/form equality and gateway response schemas, but do not contain request Authorization headers. The native client therefore does not invent a portal OAuth client secret; its token Authorization is optional and unset in production. Real authenticated interoperability, including any required portal client authentication, remains to be verified. Official WebView fallback remains available for protocol or deployment differences.
