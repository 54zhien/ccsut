# PII containment and Cookie deletion scope

Base: `36dc5d85c3a373119da170f9d400d8ef605c9b14` (`codex/payment-recovery`).
Scope: prevent local distribution/diagnostic files from being committed; repair
SSO Cookie deletion identity. No UI, payment-model, release-version, write-script,
or unrelated feature changes. Keep the pull request unmerged.

## Failure and correction

The credential boundary previously supplied a flattened Cookie header. Domain and
Path were lost, so an expired staged Cookie suppressed all persistent Cookies
with the same name. The boundary now supplies scoped Cookie objects while
checking the account generation under the CookieJar lock. SSO overlays pending
changes by `(name, normalized domain, path)` before selecting request values.
Existing successful-authentication commit, cancellation, redirect validation and
same-name specificity policy remain in place.

Regression coverage includes narrower/broader Path deletion, parent/host Domain
deletion, unrelated Path, same-identity deletion, rotation, failed authentication,
account changes and cancellation. Native adapter tests also cover scope metadata,
expired/unrelated credentials, path boundaries, Secure and stale generations.
Cookie identity follows RFC 6265 sections 4.1.2 and 5.3:
https://www.rfc-editor.org/rfc/rfc6265.html#section-5.3

The root `dist/` directory is ignored in full. Its tracked installation document
is removed from the index, preserving the local file. Regression tests check both
the real index (including future forced adds) and ordinary `git add` behavior in
an isolated synthetic repository. CI triggers include `.gitignore` and `dist/**`.
These guards prevent this known output-directory exposure route; they are not a
general PII scanner or proof that every repository file is free of personal data.

## Verification evidence

- Existing SSO baseline: 33 passing assertions locally.
- New tests before fix: four Cookie behavior failures and two privacy guard
  failures, with the same failures reproduced on macOS.
- Preserved RED commit: `3fc4984633dc5824f0f19ca28c29b735c81b5b36`.
- Preserved RED CI: https://github.com/54zhien/ccsut/actions/runs/40165973269
- Local fixed result: 43 SSO assertions and 16 JavaScript tests passed.
- Exact final source SHA, full native suite and simulator build results belong in
  the PR description/checks after execution. No real school login/payment is run.

## Public history remains an open exposure

On 2026-10-25, the repository was public. Two historical installation-document
versions containing a student-number value still returned HTTP 200 anonymously.
Current source at the base did not contain that historical numeric identifier in
the tracked text files scanned. No personal values are copied into this document,
test fixtures, CI logs or the PR.

Removing the current file, ignoring `dist/`, and opening an unmerged PR do not
remove old commits, tags, PR refs, external caches or downloaded copies. A separate
repository-level action is required before declaring historical exposure closed.
Changing visibility affects public repository/release access; history rewriting
changes commit identities and requires coordination across existing branches,
tags, open PRs and worktrees. Neither action is performed implicitly by this fix.
GitHub Support may also be needed for cached views and PR references after a
history cleanup. Retest anonymous historical access before closing the incident.
