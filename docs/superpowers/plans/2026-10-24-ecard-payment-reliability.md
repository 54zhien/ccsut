# Ecard payment reliability implementation plan

Goal: finish the reviewed payment and login fixes on top of DeepSeek commit 84dc2a5, without making real payments or changing the UI.

Scope: EcardAPI.swift, EcardTokenBridge.swift, their regression runners, and CI compilation dependencies. The existing SessionStore.logout cache-clear call stays in place.

1. Add offline regression tests before implementation. Keep HTTP requests behind URLProtocol and WebKit loading behind an injected WKWebView subclass. Record baseline failures, including the existing session CI failure (40002143680).
2. Bind navigation callbacks to the WKNavigation returned by each load; capture request/account identifiers before asynchronous JavaScript evaluation. Ignore old navigation results, stop loading on request termination, and invalidate in-flight credentials when logout clears the cache. Validate HTTPS, exact charge-app path boundary, account, and expiry consistently.
3. Preserve payment order identity on ambiguous post-submission failures (including malformed responses and cancellation), query status where possible, and return pending rather than encouraging another payment. Keep explicit business rejection as an error. Select only complete, password-free balance channels; preserve the literal null context value and encode strings using JSONEncoder.
4. Run RED then GREEN on the real API and bridge logic locally with test WebKit doubles on Windows. Compile/run the same bridge tests with a real WKWebView subclass on macOS CI. Restore session regression compilation, and build the iOS application on the exact final commit.
5. Review the full diff, preserve failed-run provenance, commit on codex/ecard-payment-reliability, and deliver a reviewable branch/PR targeting feat/ecard-payment. Do not merge.

Review focus: late navigation errors, JavaScript completion after a replacement request or logout, expired/wrong-account credentials, payment acknowledgement lost after debit, explicit rejection, and all HTTP traffic remaining mocked.

Progress: baseline Node login tests pass (6/6). Existing upstream CI failure is a missing EcardTokenBridge compilation dependency, not a test assertion failure.

RED: the offline runner on 84dc2a5 compiled and reported 10 assertion failures: malformed/cancelled payment acknowledgement, empty channel ID, invalid JSON control characters, stale navigation error, stale JavaScript result, logout cache resurrection, and three untrusted storage origins/paths. Timeout/HTTP pending handling and literal null preservation already passed upstream.

GREEN locally: the production API and bridge logic pass those regressions with the Windows WebKit boundary double; the existing six login-script tests pass. Native macOS and iOS validation is tracked separately in CI. The test constructor accepts a WKWebView dependency so the same tests can intercept native WebKit loads without contacting the school.

Review follow-up: a JSON 502 response was incorrectly classified as a business rejection; its new regression failed before moving HTTP validation ahead of business decoding. Native run 40049294189 passed API and most bridge assertions, then hit a CoreFoundation SIGTRAP. The native test double was fabricating WKNavigation handles; it now obtains real handles from a separate WebView loading an empty local HTML document. The production WebView remains fully offline in these tests. Earlier failing runs are retained (including 40049113252's additional-test compiler error and 40049134724's native crash).

Native validation: commit 112c6f4 passed all three jobs in run 40049465795: 21 ecard assertions on native WebKit, the session suite and six login-script tests, and a complete unsigned iOS build. Final review then found a narrower logout scheduling race after continuation resumption but before fetchToken returns. A deterministic new assertion failed on 112c6f4; fetchToken now fences that resumed result with a local cache revision and task cancellation check. Unmapped navigations remain eligible for the active request because login form submissions and SSO transitions create new native navigation handles; already-owned retired handles and asynchronous completions keep their original ownership.
