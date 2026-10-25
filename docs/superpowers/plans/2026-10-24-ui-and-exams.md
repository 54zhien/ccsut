# Academic UI refinement and exam recovery

> **For agentic workers:** Use superpowers:executing-plans or superpowers:subagent-driven-development. Track completed checks below.

**Goal:** Implement the user's approved five UI refinements, increase the score semester strip radius, and repair exam loading without changing the established glass, navigation, or transition effects.

**Architecture:** Keep existing SwiftUI surfaces and atomic academic snapshots. Share a lightweight semester jump control between scores and exams. Diagnose the exam term discovery boundary separately from the data fetch; preserve authentication, account generation, and all-or-nothing publication.

**Tech Stack:** SwiftUI / Foundation, iOS 26, Swift regression runners, macOS GitHub Actions.

**Spec:** User approval on 2026-10-24 of the preceding UI recommendations: timetable readability; elective disabled reasons and empty results; score detail disclosure; score/exam semester navigation; useful academic home summaries. Extra requests: more rounded score semester background and fix exam loading failure.

## Global Constraints

- Reuse the existing academic-reliability worktree; preserve unrelated original checkout changes.
- Keep existing glass/navigation/week animations and pinned semester headers at standard text sizes; accessibility text sizes use flowing headers to preserve content access.
- No real enrollment, drop, or SMS requests in validation.
- Do not represent static fixtures or compilation as real-device/server acceptance.
- Keep complete snapshots, safe account generations, and mutation gates.

## Review Focus

- Term markup absent or different: discover supported terms from evidence, never silently fabricate a complete empty result.
- One exam term fails: keep the prior complete snapshot and show useful failure context.
- Account changes while requests run: discard previous-account results.
- Large text and long course titles: preserve access to grades, period labels, and actions.
- Disabled elective action or empty search: expose the reason and an actionable reset.

### Task 1: Score details and semester controls

Files: ScoreView.swift, PageSurface.swift; UI fixture tests as appropriate.
- [x] Replace crowded inline breakdown with accessible tap-to-expand detail, with grade point labels.
- [x] Add reusable AcademicTermJumpMenu(terms: [String], onSelect: (String) -> Void) for ScrollViewReader anchors.
- [x] Add score semester quick jump and increase semester strip corner radius to 26 points, preserving pinned transitions.
- [x] Verify actual macOS build and rendered screenshots / interaction tests.

### Task 2: Elective feedback

Files: ElectiveView.swift, CourseDetailSheet.swift; related policy tests only if behavior changes.
- [x] Display existing safe action block reason on course cards/details and accessibility hints.
- [x] Show an empty-filter/search message and reset action without weakening eligibility or action gates.
- [x] Verify disabled reasons, reset, and existing regression suite.

### Task 3: Exam recovery

Files: AcademicCalendar.swift, AcademicAPI.swift, ExamView.swift, AcademicReliabilityTests.swift, SessionRegressionTests.swift as needed.
- [x] Inspect actual contracts/probes and isolate the new failure dependency.
- [x] Capture a failing regression for the demonstrated unsupported response/term shape before production changes.
- [x] Fix discovery/load with strict validated terms, safe account handling, complete snapshots, and useful stage-specific failure feedback.
- [x] Add quick semester jump using the shared control.
- [x] Run Foundation regression suite and exact-commit macOS compilation; report remaining live-server uncertainty explicitly.

### Task 4: Readability and home summaries

Files: ScheduleView.swift, AcademicView.swift and existing shared presentation/model helpers if required.
- [x] Scale period/time/day labels and improve auxiliary contrast while preserving grid geometry and animation.
- [x] Add truthful available summary data to existing home cards; avoid repeated requests and invented zero counts.
- [x] Verify large text layouts and existing fixture navigation.

### Task 5: Integration

- [x] Review shared changes for layout, privacy, cancellation, and account lifecycle regressions.
- [x] Run Swift/Node runners and macOS build/UI validation at the final application/test commits.
- [x] Record exact commit, successful/failed run provenance, and physical-device acceptance still required.

## Evidence checkpoint

- Code commit: `2cc216e75b45bb7c9c044041fac3c5e7b9340c28`.
- Root cause: the original official `kslist` HAR response uses five `onclick="loadKspc('term');"` controls, and no `option` or `changeXn` controls. The prior parser rejected this real page before any exam-list query.
- Local RED: the sanitized captured controls produced one failed academic regression on the previous parser. GREEN after adding validated mobile control parsing: 26/26 academic assertions.
- macOS regression run `39995033219`: 166 Swift PASS assertions, 6 Node tests, zero failures; Debug simulator build succeeded. The HTTP-boundary integration test uses the actual API, term parser, and complete snapshot loader for one discovery plus five semester reads.
- Release run `39995275101`: succeeded; downloaded IPA ZIP verified, app executable present, bundle `com.imzhien.ccsut`, iOS 26 minimum, unsigned. SHA256 `d1c6ddf6331dfda46c7e0df140d38aa5b63ab99bd198215ec4ed36231dcfd546`.
- UI run `39995043330`: week positioning test passed (one test, zero failures); exported initial/returned/scrolled screenshots. Actual timetable pixels inspected for period/time labels and preserved card/week styling. The interaction suite finished with 10/14 passing. Failures were cancelled-pop sampling, academic pull-to-refresh, timetable pull-to-refresh, and score disclosure lookup. Preserve this failed run. Actual AX evidence confirmed the outer score row identifier replaced the disclosure identifier; actual recordings confirmed pull movement without a refresh spinner. XXXL screenshots also exposed grade wrapping and oversized sticky headers. Follow-up fixes and observational refresh/transition probes are under validation; no passing claim is made for them yet.
- No live enrollment/drop/SMS occurred. No new real-server session was used; the exam regression is reproduced from the user's previously captured official response. Physical-device exam loading and visual acceptance remain to be checked with the new IPA.
- Read-only requests retain pre-existing outer generation checks: stale results cannot publish. Passing the captured generation through every read API is a separate hardening opportunity; mutation transport remains generation-bound.

## Follow-up validation

- `2e8a506` failed compilation in runs `39998436853` and `39998438610`: diagnostic-only geometry formatting used unavailable C names. Fixed with ordinary Swift geometry descriptions in `886049d`; both failed runs retained.
- `886049d` session run `39998662066` passed all regressions and the simulator Debug build.
- UI run `39998663699`: week positioning 1/1 passed; interaction suite 12/14 passed. Score disclosure/home summary, large text course-action reachability, semester jumps, disabled elective feedback, and all navigation tests passed. Cancelled-pop probes recorded actual in-flight samples for scores, exams, and electives.
- Remaining two RED tests demonstrate the same refresh failure. The runtime probe found the correct `SwiftUI.HostingScrollView`, but `refreshControlMatches=false` before and after each pull. Content offset reached -311 points on scores and -292.7 on timetable, with zero refresh events. SwiftUI removed the manually installed refresh control after attachment. The repair removes the manual UIKit injection and attaches native SwiftUI refreshable to all five actual page scroll views, retaining always-bounce and await-completion behavior. The red tests are preserved without weakening assertions; final CI is pending.

- Screenshot review of `886049d`: XXXL summary values 3.90/10.5 and expanded scores are intact, and disclosure can be reached and operated. Final coverage also exercises large-text semester menus and captures the ordinary exam date rail after a historical-term jump.

## Native refresh and final visual follow-up

- Production checkpoint `7cb52b0`: regression/build run `40002395547` passed 166 Swift assertions and 6 Node tests; release run `40002404063` produced a verified unsigned IPA, SHA256 `88c8037b6478c3bc1ed103e541a2a035953ea0fbf3a2cfc7ffd7eebda075e005`.
- UI run `40002398342`: week positioning passed, 12/14 interaction tests passed. Native timetable refresh now fires exactly once. Large-text semester jumps and exam day rail passed and were rendered. Preserve the failed run: academic refresh and search-reset assertions still failed.
- The academic refresh gesture began inside the new semester Menu: point (321.6,305.9) overlaps AX menu bounds x297...366/y283...327. A follow-up moved the gesture to the noninteractive body at x=0.2, retaining its vertical distance, duration and exactly-once assertion. Run `40006075428` still failed the score refresh check, so menu overlap does not explain the remaining failure.
- Additional pixel review found the XXXL exam row time split as 14:2 / 0 beside a truncated location. Accessibility-size rows now stack time and location, keeping time on one line; standard-size rows are unchanged. The focused follow-up includes the existing full large-text scenario to inspect this actual rendering.
- CI now supports a focused refresh/search/large-text pass for these remaining concerns, with the original full-suite evidence retained. Final focused validation is pending.

- Search reset recording from `40002398342` confirms the action clears the query, restores count 3 and renders course cards. The synchronous assertion ran during the 0.18-second transition while the old empty-state AX node remained. The corrected test waits up to 3 seconds for its disappearance and then requires the course to exist; no production search logic was changed.

## Latest checkpoint

- Code `549c0fed8431276dbd7769affcbb9d88879f7e41`: regression/build run `40006074514` passed 166 Swift assertions, 6 Node tests, and the Debug simulator build. Release run `40006080460` succeeded; verified unsigned IPA SHA256 `d96b750f166a4d23949c2dea62147f94c1229ae43c51b204ad7accd993049d40`.
- Focused UI run `40006075428`: timetable refresh, elective reset/disabled reason, and large-text navigation/layout passed. Rendered exam time `14:20` and location `9号栋9-112` are readable after the historical-term jump. Score refresh remains RED; the after-completion counter is insufficient to distinguish no callback from cancellation. Next diagnosis records native scroll/control state and callback entry/completion/cancellation without changing production behavior.

- Diagnostic code `a6c390e`: regression/build run `40007940809` passed. UI run `40007942198` retained all six failing academic refresh assertions. Every page/empty-state combination had a native `SwiftUI.UIKitRefreshControl`, one recognized pan, 182–224 points of pull, and one callback entry. The outer callback task was cancelled, so the old post-cancellation counter remained zero; this is not evidence that the independent `PageLoadGate` fetch failed. The timetable's synchronous fixture had one noncancelled completion. Follow-up validation observes successful snapshot publication inside the gated load itself, waits for initial publication before dragging, and requires exactly one additional publication plus the expected displayed content. Production cancellation and account-generation guards remain intact.

- Final application source `6926342c63f7677fb3d8e3363981a9c605ee6dd5`: regression/build `40011066924` passed 166 Swift assertions and 6 Node tests; release `40011074860` succeeded. Verified unsigned IPA SHA256 `97785fd6238304871a72d6c461cd0d9cd52413c31e3acd51a7a788a9e4b58890`. Large runtime instrumentation and all callback-state mutations were removed; snapshot-publication instrumentation is DEBUG-only.
- UI `40011069453` retained a test-selector failure: actual AX snapshots show `academic-publication-count` as an `Other` node, with labels 1 before and 2 after score refresh; the test wrongly queried `StaticText`. Elective reset, large text, and timetable refresh passed. The follow-up changes only the selector to a type-independent exact identifier match; its required publication counts and content assertions are unchanged. Application sources and the existing IPA remain identical.
- UI `40012330316` on selector fix `e4bd41f` did not exercise academic refresh: the first three tests failed in `app.launch()` with `Timed out while acquiring background assertion`; no publication diagnostic was emitted. The fourth timetable refresh test passed. This launch-stage infrastructure failure is retained, and a fresh runner is requested at the same commit to obtain the missing six-scenario evidence; no application or test assertion is changed for the retry.

## Final validation and delivery

- Final application source: `6926342c63f7677fb3d8e3363981a9c605ee6dd5`. Final UI test source: `e4bd41f4cd4fb9911f6d311270a7841a41692e31`. The application and Xcode project have no changes between these commits; the latter changes the accessibility selector and this evidence record only.
- Regression/build runs `40011066924` and `40012328876` succeeded: 166 Swift PASS assertions, 6 Node tests, and the Debug simulator build.
- Same-source UI retry `40014163351` succeeded: 4 focused tests, zero failures. Scores, exams, and electives each published exactly once after refresh in both populated and empty states (initial count 1, refreshed count 2), with expected content/empty-state assertions. Elective search reset and disabled feedback, large-text controls, and whole-page timetable refresh also passed.
- Independently inspected final screenshots: the standard score semester strip has matching 26-point rounded corners, and the accessibility-size historical exam row displays `14:20` and the complete room `9号栋9-112`. Existing navigation/week coverage is recorded in the earlier full-suite runs above; the final run is the four-test focused suite, not a new full-suite run.
- Release run `40011074860` succeeded. Delivered `dist/ui-exam-6926342/CCSUT-unsigned.ipa`; ZIP integrity and app executable verified. SHA256 `97785fd6238304871a72d6c461cd0d9cd52413c31e3acd51a7a788a9e4b58890`, 4,703,316 bytes, bundle `com.imzhien.ccsut`, version 0.1.0/build 1, minimum iOS 26.0. The package is unsigned and requires the user's existing signing/install process.
- Implementation and CI verification are complete. Live school-server exam loading and physical-device visual acceptance remain for the user to test; no new authenticated school session or enrollment/drop/SMS action was used during this work.
