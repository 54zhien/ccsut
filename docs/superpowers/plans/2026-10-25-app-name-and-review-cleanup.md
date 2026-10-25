# Review cleanup and official App display name

User approved fixing the confirmed review findings and naming the App 长工院. Execute inline in the existing campus worktree, with a separate managed worktree for public branch redaction. Preserve bundle identifier, Keychain keys, all unrelated changes and existing CI failure provenance.

1. Add regressions for whitespace in elective capacity; normalize both numeric components. Keep pending/invalid values conservative and preserve unspaced inputs.
2. Share a period caption between course detail and the course chooser. A single period displays 第 X 节; merged periods retain 第 X–Y 节. Preserve page layout.
3. Retain the last native SSO failure in memory as fixed stage/error enums. Never retain raw URLs, tickets, headers, account numbers or arbitrary error text. Successful native authentication and logout clear stale diagnostics; failed background prewarming preserves the diagnosis. Cancellation or account changes cannot publish a stale diagnosis. Add synthetic protocol and bridge regression coverage.
4. Ignore only local native preview/regression download directories. Change Debug and Release CFBundleDisplayName to 长工院, keeping com.imzhien.ccsut and the existing build target/product names so updates preserve app data. Check the generated bundle if packaged.
5. In a separate checkout, replace the known personal identifiers in the CAS probe and installation instructions at affected public branch tips using ordinary descendant commits. Read/replace sensitive strings only in memory; never print their diffs or put real identifiers in fixtures. Do not rewrite history, change visibility, merge feature branches into main, or touch another worktree's files.
6. Review the complete diff, run targeted tests, then exact-head macOS regressions and iOS build. Commit/push the campus branch within existing session authorization; keep PR #7 targeting the approved payment baseline. Branch-tip redaction must be checked after pushing. Historical exposure remains a separate decision.

Excluded findings: current validated timetable loading already rejects week 99 and weekday 0; authentication timeout in the token-acquisition path is not evidence that a cached business token must be cleared. Do not invent TGC lifetime guarantees or perform real payments, applications or uploads.

## Evidence so far

- The user reports the previous `f0ae76f` IPA passed native SSO and cover-install testing on their device. This is device feedback for that flow/account, not proof of future TGC renewal behavior.
- Capacity regressions failed in three whitespace cases before the fix, then all 39 academic checks passed. Native failure diagnostics failed both new stage assertions before recording was implemented, then all 33 protocol checks passed. Existing 8 schedule checks also passed.
- The 10 affected public branch tips received ordinary descendant commits touching only `_cas3.mjs` and the installation guide. A post-push scan found no known identifiers in either file on any remote branch tip. The temporary managed checkout is no longer needed and was submitted for archival. Existing worktrees and branch histories were preserved. Historical commits and old tags are outside this cleanup.
- Diagnostic storage contains only fixed enums, survives WebView fallback, and clears after native recovery or session invalidation. Bridge tests additionally cover classified terminal identity mismatch and stale/cancelled result suppression. Exact-head macOS execution is required before completion.
