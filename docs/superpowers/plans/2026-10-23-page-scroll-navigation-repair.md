# Page scrolling, first-load layout and academic navigation repair

Goal: make the whole timetable page scroll and refresh as a single surface, fix narrow first-load content, apply device-aware corners, and unify academic page chrome and layout.

User scope includes score/exam/elective layout improvements. Preserve session, API, enrollment confirmations, filtering, and data semantics.

Investigation: the timetable has an internal vertical ScrollView while semester/weekdays are fixed outside it. Header animation observes that internal scroll. A loading-only VStack inside NagiPageChrome's GeometryReader has no full-width constraint. Academic destinations toggle from a hidden custom root navigation bar to visible system navigation bars with conditional toolbar labels.

- [ ] Reproduce with native UI tests: cold-load width, semester/day movement, pull refresh, repeated academic push/pop. Keep the baseline failures and screenshots.
- [ ] Replace the inner vertical timetable scroller with one outer page scroller; derive finite grid dimensions from the outer viewport. Bind refresh and header offset to that outer scroller only. Remove internal trailing 88pt space.
- [ ] Expand the shared chrome content to fill its proposal in every loading/error/empty/content state. Use a stable custom back and refresh control on academic destinations with the same masked blur. Keep an explicit in-page elective search field.
- [ ] Format raw school terms for display; use device corner geometry for the timetable, and remove fixed medium-sheet radius overrides.
- [ ] Improve the academic content hierarchy and spacing: score summary plus two-line semester headers, exam overview plus readable date/location, elective search/filter/summary plus non-overlapping status/credits.
- [ ] Run native interaction checks and existing regressions, inspect cold/loaded/dark/compact/destination/sheet screenshots, build Release, and independently review.

No merge or publication is part of this change. Simulator acceptance does not replace physical-device acceptance.
