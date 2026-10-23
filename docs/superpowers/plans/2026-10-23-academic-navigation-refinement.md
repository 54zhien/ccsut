# Academic navigation and term strip refinement

User scope: reduce only the timetable panel corners; restore academic detail
titles to the centered navigation position without fading; restore edge-swipe
back; remove the academic service section caption; give score/exam term headers
equal-width capsule backgrounds that become Liquid Glass when pinned.

Implementation choices: retain the existing SwiftUI NavigationStack and native
navigation bar for child pages rather than installing a gesture recognizer
delegate. Keep the existing Nagi gradient blur as the bar backdrop. Retain the
root pages' accepted Nagi title motion. Use a 28pt continuous timetable panel
radius; keep sheet radii unchanged. Use 16pt horizontal margins for both term
strips, with a normal grouped surface and floating Liquid Glass.

Steps:
- [ ] Add and run a native edge-swipe reproduction against the current app.
- [ ] Restore native detail navigation in NagiPageChrome / child views; update
  button navigation coverage and add fixed-title/term-strip scroll checks.
- [ ] Add shared pinned capsule surface in PageSurface, use in ScoreView and
  ExamView; change ScheduleView panel radius and AcademicView section caption.
- [ ] Run regression checks, native UI interactions, screenshot review, and
  Release packaging on exact code SHA. Preserve any failed run evidence.
- [ ] Independent code review, draft PR update; no merge.

Business data loading, session state, calculation and enrollment are out of scope.
