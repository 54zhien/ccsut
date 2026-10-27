# Review repairs

Base: `d61e04c`, following the user's approval to repair the review findings.

- [ ] Campus: retain unresolved submission ownership across presentations, paginate reconciliation, honor refresh after pagination. Use synthetic failing regressions before fixes.
- [ ] Authentication: reconcile WebKit deletions, surface failed credential persistence, restrict academic redirects, remove unused diagnostics.
- [ ] Payment and exams: enforce the existing room guard; centralize school-date formatting and test foreign timezones.
- [ ] Historical tools: scope cookies, require explicit write opt-in, remove unsafe certificate overrides. Keep these tools out of production iOS.
- [ ] Update the review with dispositions, run offline suites and native CI, and review the integrated changes. Preserve the accepted UI; do not merge or publish a release without a new request.

License selection remains a maintainer decision. Avoid broad file splitting while fixing state ownership; extract only helpers needed by these repairs.
