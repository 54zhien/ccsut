# Timetable refresh animation synchronization

User direction: synchronize other refreshable pages with the timetable's native pull, retained loading region, and dismissal. Keep existing loading actions and page content.

Implementation plan (inline execution):
- [x] Add a rendered-position assertion: while a manually held refresh is pending, the score summary remains at least 40 points below its resting position. Preserve the earlier screenshots showing the baseline failure.
- [ ] Extract the timetable's viewport -> scroll reader -> vertical scroll hierarchy, native refresh attachment and scroll geometry observation into `PageScrollSurface`.
- [ ] Verify the score page against the held-region assertion and screenshot before adopting the same surface on the remaining refreshable pages.
- [ ] Keep load gates, authentication, elective writes and payment behavior unchanged. Check normal/empty content, repeated refresh, navigation and return to resting position.
- [ ] Remove diagnostic variants from the deliverable; retain experiment commits and CI results on the diagnosis branch. Report simulator verification separately from device acceptance.

Evidence:
- Baseline visual reproduction: run 40178129369 shows the timetable holding its spinner/refresh gap while scores have already returned to rest, with both completions explicitly held.
- Baseline assertion run: 40179739102, commit cef415b.

The user explicitly requested direct synchronization instead of further environment questions. No build-number answer is needed to proceed.
