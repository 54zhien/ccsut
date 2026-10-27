# Campus authentication: live CAS-to-SPA redirect failure

## Supersedes the earlier unconfirmed hypotheses

The preceding package did not fix the reported re-login/cold-start symptom. Its cookie-rotation regression and browser navigation fixes covered real code defects, but neither established the user's native authentication failure. The earlier document's statement that the fragment hypothesis was unconfirmed is superseded by the live observations below.

The user completed a fresh school login in a dedicated temporary browser. No password, verification code, token, cookie value, ticket, account ID, or private response was written to the evidence files. Only authentication metadata and sanitized request stages were retained. Only authentication and read-only record queries were exercised.

## Proven failure mechanism

The production `CampusClient` was compiled into a Windows diagnostic executable. Its credential input was passed in memory from the dedicated browser; the isolated native credentials excluded ehall cookies to exercise native creation of a missing campus session using an existing valid CAS login. A separate control used the browser-established campus session.

Observed network chain with the pre-fix production source:

1. `validate_full`: HTTP 200 / errcode 2001, a new campus session cookie is staged.
2. Campus CAS entry: HTTP 302 to the official CAS login.
3. CAS with the existing TGC: HTTP 302 back to the campus proxy with a service ticket.
4. Proxy consumes the ticket and redirects through its clean entry URL.
5. Proxy redirects to the official leave or return-school SPA route with a fragment such as `#/leaveList`.
6. `CampusClient.trustedURL` rejects every non-nil fragment, throws authentication, and discards the still-unverified campus cookie transaction. The final identity validation and record query never run.

The browser permits the same SPA redirect and establishes the campus session, so returning to the native page can then succeed. Re-login removes the campus session; server expiry likewise requires renewal through the same fragment-bearing chain. This explains the repeated symptom without attributing it to UI changes.

## Minimal correction

Keep the existing host, scheme, user-info and port validation. Remove the client-only fragment when constructing the HTTP URL; retain encoded path/query bytes, including a literal encoded `%23` inside a query value. The normalizer does not permit a new host or an unsafe authority. The page fragment is not part of an HTTP request.

## Validation and limits

- The new live-shaped fixture fails on all three record kinds before the change. Three fragment-normalization cases also fail. After the fix, the targeted CampusAPI suite has 89 PASS / 0 FAIL.
- The pre-fix production executable fails at the fragment redirect for leave, departure and return records using the real school service. The fixed production executable successfully completes all three record queries with an isolated missing-campus-session snapshot; no manual browser repair is performed between each old/new comparison.
- The actual `StoredCookie` production codec was extracted unchanged and exercised as an in-memory encode/decode round trip. Restored credentials successfully renew and read leave/return records. The departure restored run hit Windows URLSession transport errors at the initial validation step (NSURLError -1002, then -1); those failure logs are preserved and are not reported as authentication failures or a fully passed cold-start run. An earlier non-restored departure query succeeds after the fragment fix.
- An initial diagnostic mistakenly used agent-browser's current-origin cookie getter and omitted the separate auth-domain cookies. That incomplete-input probe is invalid evidence for missing CAS credentials. It was corrected by reading the complete dedicated browser context in memory before conducting the valid comparisons above.
- Real record contents remain private; only sanitized chain logs exist in ignored local `dist/campus-auth-source/`. No full test suite or real school mutation ran. Actual iPhone installation and a waited physical cold start remain separate acceptance items.

Release compile/package run 40205635484 passed at `84ea0df89193e4fbf3c9c677a20bb51fc8f36fbb`. Artifact 12603802463 contains the verified unsigned IPA (5,820,127 bytes), SHA-256 `09275a8ec8843cbf5c413d53fc5fb42ad2c4cd42ae57bd2186fbfa13fa1fdd23`. ZIP CRC, arm64 Mach-O, display name 长工院, bundle ID `com.imzhien.ccsut` and minimum iOS 26.0 checks passed. The temporary dedicated browser was closed after the authorized read-only comparisons. Physical iPhone re-login and a waited cold start remain device acceptance items.
