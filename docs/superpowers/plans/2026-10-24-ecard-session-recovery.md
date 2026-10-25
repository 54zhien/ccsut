# Ecard session recovery implementation plan

**Goal:** Restore the verified native session into an ephemeral WebView reliably after cold launch and before payment SSO.

**Architecture:** Keep Keychain as the durable credential source and retain the non-persistent WebStore. A Foundation-only cookie synchronizer retries once and verifies its writes. Bootstrap replaces restored credentials; payment startup fills missing cookies without rolling back newer WebKit credentials. Cancellation and account generation changes stop both paths.

**Constraints:** Local uncommitted changes only. Preserve existing work. No real school submissions, payments, credential logging, or capture fixtures. A session cookie without an expiry remains eligible for restoration. Timeout messages contain fixed stage labels only.

**Review focus:** Partial or silently failed cookie writes; logout during suspension; newer WebKit cookies; session cookies without expiry; timeout URLs containing tokens.

## Steps

- [x] Add regression coverage: restored session cookies, one-shot write/read failure, silently dropped writes, permanent failure, account switch, preservation of newer WebKit credentials, safe stage classification.
- [x] Reproduce failures before changing the runtime integration.
- [x] Implement shared restoration and wire it into bootstrap/refresh and token fetching. Preserve native login if WebKit restoration fails, with a retryable error.
- [x] Preserve successfully warmed WebKit cookie rotations in Keychain; classify SSO timeouts without storing URLs.
- [x] Register the source in Xcode and CI; add native Session integration regressions. Run local Foundation/JS checks and syntax parsing. Report macOS/WebKit checks separately if unavailable locally.

User delegated the repair approach; no further design approval is needed. This plan is executed inline in the existing isolated worktree. Commits/pushes are excluded to preserve the prior local-only constraint.

## Validation record

- RED: executed the original production injection method with an in-memory cookie store adapter; a single write timeout silently abandoned restoration.
- GREEN: the current production injection and WebStore restoration functions, with the same adapter, recover a transient write failure and expose a permanent failure through `lastError` (2 checks).
- Review found overlapping background prefetch/native refresh could roll credentials back. Bootstrap now refreshes before prefetch; native refresh holds a preparation suspension gate and drains the previous task before CAS/injection. It releases the gate and restarts best-effort prefetch only for the same still-active account. Extracted production task-method adapters verify cancel-and-join (RED then GREEN), replacement-prefetch blocking and restart (2 checks); removing the gate in an adapter reproduced the regression. These adapters remain under the ignored evidence directory and perform no navigation.
- Foundation restoration/stage runner: 18 checks passed under Swift 6 on Windows.
- Existing login/privacy/CAS JavaScript tests: 14 passed. Academic reliability runner: 35 passed, including the prior uncommitted grade fixes.
- Xcode project plist lint, diff whitespace check, and modified Swift syntax parsing passed. EcardAPI typechecking with a Windows FoundationNetworking import adapter also passed.
- Added real WKWebsiteDataStore cold-bootstrap/session-cookie/rotation tests to the macOS Session runner; not executed locally. Full iOS/macOS compilation, exact-revision CI, IPA packaging, and physical cold-start SSO remain pending. No school credentials, live requests, submissions, uploads, or payments were used for verification.
