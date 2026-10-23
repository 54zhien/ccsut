# Academic UI refinement and exam recovery

> **For agentic workers:** Use superpowers:executing-plans or superpowers:subagent-driven-development. Track completed checks below.

**Goal:** Implement the user's approved five UI refinements, increase the score semester strip radius, and repair exam loading without changing the established glass, navigation, or transition effects.

**Architecture:** Keep existing SwiftUI surfaces and atomic academic snapshots. Share a lightweight semester jump control between scores and exams. Diagnose the exam term discovery boundary separately from the data fetch; preserve authentication, account generation, and all-or-nothing publication.

**Tech Stack:** SwiftUI / Foundation, iOS 26, Swift regression runners, macOS GitHub Actions.

**Spec:** User approval on 2026-10-24 of the preceding UI recommendations: timetable readability; elective disabled reasons and empty results; score detail disclosure; score/exam semester navigation; useful academic home summaries. Extra requests: more rounded score semester background and fix exam loading failure.

## Global Constraints

- Reuse the existing academic-reliability worktree; preserve unrelated original checkout changes.
- Keep existing glass/navigation/week animations and pinned semester headers.
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
- [ ] Verify actual macOS build and rendered screenshots / interaction tests.

### Task 2: Elective feedback

Files: ElectiveView.swift, CourseDetailSheet.swift; related policy tests only if behavior changes.
- [x] Display existing safe action block reason on course cards/details and accessibility hints.
- [x] Show an empty-filter/search message and reset action without weakening eligibility or action gates.
- [ ] Verify disabled reasons, reset, and existing regression suite.

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
- [ ] Verify large text layouts and existing fixture navigation.

### Task 5: Integration

- [x] Review shared changes for layout, privacy, cancellation, and account lifecycle regressions.
- [ ] Run Swift/Node runners and macOS build/UI validation at the final commit.
- [ ] Record exact commit, successful/failed run provenance, and physical-device acceptance still required.

## Evidence checkpoint

- Code commit: `2cc216e75b45bb7c9c044041fac3c5e7b9340c28`.
- Root cause: the original official `kslist` HAR response uses five `onclick="loadKspc('term');"` controls, and no `option` or `changeXn` controls. The prior parser rejected this real page before any exam-list query.
- Local RED: the sanitized captured controls produced one failed academic regression on the previous parser. GREEN after adding validated mobile control parsing: 26/26 academic assertions.
- macOS regression run `39995033219`: 166 Swift PASS assertions, 6 Node tests, zero failures; Debug simulator build succeeded. The HTTP-boundary integration test uses the actual API, term parser, and complete snapshot loader for one discovery plus five semester reads.
- Release run `39995275101`: succeeded; downloaded IPA ZIP verified, app executable present, bundle `com.imzhien.ccsut`, iOS 26 minimum, unsigned. SHA256 `d1c6ddf6331dfda46c7e0df140d38aa5b63ab99bd198215ec4ed36231dcfd546`.
- UI run `39995043330`: week positioning test passed (one test, zero failures); exported initial/returned/scrolled screenshots. Actual timetable pixels inspected for period/time labels and preserved card/week styling. The interaction suite finished with 10/14 passing. Failures were cancelled-pop sampling, academic pull-to-refresh, timetable pull-to-refresh, and score disclosure lookup. Preserve this failed run. Actual AX evidence confirmed the outer score row identifier replaced the disclosure identifier; actual recordings confirmed pull movement without a refresh spinner. XXXL screenshots also exposed grade wrapping and oversized sticky headers. Follow-up fixes and observational refresh/transition probes are under validation; no passing claim is made for them yet.
- No live enrollment/drop/SMS occurred. No new real-server session was used; the exam regression is reproduced from the user's previously captured official response. Physical-device exam loading and visual acceptance remain to be checked with the new IPA.
- Read-only requests retain pre-existing outer generation checks: stale results cannot publish. Passing the captured generation through every read API is a separate hardening opportunity; mutation transport remains generation-bound.
