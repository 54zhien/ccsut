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
- [ ] Replace crowded inline breakdown with accessible tap-to-expand detail, with grade point labels.
- [ ] Add reusable AcademicTermJumpMenu(terms: [String], onSelect: (String) -> Void) for ScrollViewReader anchors.
- [ ] Add score semester quick jump and increase semester strip corner radius to harmonize with the 26/28-point cards, preserving pinned transitions.
- [ ] Verify actual macOS build and rendered screenshots / interaction tests.

### Task 2: Elective feedback

Files: ElectiveView.swift, CourseDetailSheet.swift; related policy tests only if behavior changes.
- [ ] Display existing safe action block reason on course cards/details and accessibility hints.
- [ ] Show an empty-filter/search message and reset action without weakening eligibility or action gates.
- [ ] Verify disabled reasons, reset, and existing regression suite.

### Task 3: Exam recovery

Files: AcademicCalendar.swift, AcademicAPI.swift, ExamView.swift, AcademicReliabilityTests.swift, SessionRegressionTests.swift as needed.
- [ ] Inspect actual contracts/probes and isolate the new failure dependency.
- [ ] Capture a failing regression for the demonstrated unsupported response/term shape before production changes.
- [ ] Fix discovery/load with strict validated terms, safe account handling, complete snapshots, and useful stage-specific failure feedback.
- [ ] Add quick semester jump using the shared control.
- [ ] Run Foundation regression suite and exact-commit macOS compilation; report remaining live-server uncertainty explicitly.

### Task 4: Readability and home summaries

Files: ScheduleView.swift, AcademicView.swift and existing shared presentation/model helpers if required.
- [ ] Scale period/time/day labels and improve auxiliary contrast while preserving grid geometry and animation.
- [ ] Add truthful available summary data to existing home cards; avoid repeated requests and invented zero counts.
- [ ] Verify large text layouts and existing fixture navigation.

### Task 5: Integration

- [ ] Review shared changes for layout, privacy, cancellation, and account lifecycle regressions.
- [ ] Run Swift/Node runners and macOS build/UI validation at the final commit.
- [ ] Record exact commit, successful/failed run provenance, and physical-device acceptance still required.
