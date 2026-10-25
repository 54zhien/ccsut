# Page scrolling, first-load layout and academic navigation repair

Goal: make the whole timetable page scroll and refresh as a single surface, fix narrow first-load content, apply device-aware corners, and unify academic page chrome and layout.

User scope includes score/exam/elective layout improvements. Preserve session, API, enrollment confirmations, filtering, and data semantics.

Investigation: the timetable has an internal vertical ScrollView while semester/weekdays are fixed outside it. Header animation observes that internal scroll. A loading-only VStack inside NagiPageChrome's GeometryReader has no full-width constraint. Academic destinations toggle from a hidden custom root navigation bar to visible system navigation bars with conditional toolbar labels.

- [x] Reproduce with native UI tests: cold-load width, semester/day movement, pull refresh, repeated academic push/pop. Keep the baseline failures and screenshots.
- [x] Replace the inner vertical timetable scroller with one outer page scroller; derive finite grid dimensions from the outer viewport. Bind refresh and header offset to that outer scroller only. Remove internal trailing 88pt space.
- [x] Expand the shared chrome content to fill its proposal in every loading/error/empty/content state. Use a stable custom back and refresh control on academic destinations with the same masked blur. Keep an explicit in-page elective search field.
- [x] Format raw school terms for display; use device corner geometry for the timetable, and remove fixed medium-sheet radius overrides.
- [x] Improve the academic content hierarchy and spacing: score summary plus two-line semester headers, exam overview plus readable date/location, elective search/filter/summary plus non-overlapping status/credits.
- [x] Run native interaction checks and existing regressions, inspect cold/loaded/dark/compact/destination/sheet screenshots, build Release, and independently review.

No merge or publication is part of this change. Simulator acceptance does not replace physical-device acceptance.


Validation (production code 8fade8101fa09ddbad9d1dbc96238b1aa8ecd64c):
- 39905056100: preserved RED baseline. Cold surface measured80.67pt vs402pt page; navigation/refresh failed. The initial weekday locator was ambiguous and was corrected by identity/firstMatch rather than weakening movement assertions.
- 39906231057 /39906232377: compile found a get-only refresh environment write; removed the unnecessary child overrides, with refresh directly on the sole vertical scroller.
- 39906365469: navigation, actual whole-page movement, exactly-once refresh, and device-radius tests passed. Cold screenshot was full width; its old AX role query no longer matched the scroll container, corrected to query intended identities across roles while retaining the95-percent-width threshold.
- 39907171723: all50 existing regressions passed.
- 39907171679: all5 native UI tests, simulator render and screenshot export passed. Inspected full-width loading, actual gesture screenshots, all academic destinations, dark/compact and medium sheets.
- 39907172436: Release IPA built; downloaded archive integrity checked.
- Independent review found one remaining raw elective empty-term caption, fixed in8fade81; follow-up review found no blockers. No API/session/login production edits. No merge or physical-device acceptance.
