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
- [x] Add and run a native edge-swipe reproduction against the current app.
- [x] Restore native detail navigation in NagiPageChrome / child views; update
  button navigation coverage and add fixed-title/term-strip scroll checks.
- [x] Add shared pinned capsule surface in PageSurface, use in ScoreView and
  ExamView; change ScheduleView panel radius and AcademicView section caption.
- [x] Run regression checks, native UI interactions, screenshot review, and
  Release packaging on exact code SHA. Preserve any failed run evidence.
- [x] Independent code review, draft PR update; no merge.

Business data loading, session state, calculation and enrollment are out of scope.

Evidence and review:
- Baseline `6d331ae`, UI run `39910092474`: the new edge-swipe test failed at
  the root-account return assertion after a real left-edge drag. The existing
  five UI tests passed (six executed, one failure). Artifacts retained.
- First implementation `ff243ea`: 50 regression checks, Release build and all
  seven UI tests passed (`39911136918`). This proves RED-to-GREEN for edge swipe,
  with additional centered-title and equal-width/pinned-strip coverage.
- Independent review requested explicit window anchoring for the blur backdrop,
  since content-local safe-area insets can be zero below a native bar. Commit
  `9bd18f6` uses the greater of global top position and safe-area inset. The
  edge-swipe test also requires a hittable account button and no detail bar.
- Screenshot review of the initial pinned-state captures showed sharp scrolling
  rows behind the native title despite the glass term strip being correct.
  Commit `7688c73` composites the shared gradient as an overlay above scroll
  content, retaining the explicit window anchoring from `9bd18f6`.
- Final exact-code verification: `7688c73` UI `39912167113` passed all seven
  native tests (zero failures); regression `39912167136` and Release
  `39912168624` passed. Final pinned screenshots confirm the gradient covers
  scrolling rows behind the centered title, with equal-width glass capsules.
  Academic-home caption removal, normal-state capsules, 28pt timetable panel
  and dark elective navigation were visually inspected.
- IPA downloaded to the matching external delivery folder; ZIP integrity passed,
  bundle identifier `com.imzhien.ccsut`. No merge or physical-device acceptance.
