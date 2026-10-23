# Cancelled pop and academic home refinement

User feedback: score term strip corners are too pill-shaped; all academic
details' title/buttons drift relative to the page during a cancelled right-swipe;
academic home entries bounce unexpectedly when pulled, sit too near the header,
and leave too much unused lower space. Keep the icon and business logic unchanged.

- Use an 18pt continuous radius for the shared score/exam term surface, retaining
  equal widths and pinned Liquid Glass.
- Reproduce partial/cancelled native interactive pop before changing navigation.
  DEBUG CADisplayLink observes the title's presentation position relative to the
  child page. The test must sample actual interactive frames and require <2pt
  relative drift, then confirm cancellation leaves the detail interactive.
- Place a static inline title/back/refresh header in the child page, retaining
  native UINavigationController pop transitions through its public edge/content
  gesture recognizers. Scope gesture delegates to that child and restore original
  delegates/enabled state on disappearance. Root and child both hide the shared
  system bar, avoiding its independent content interpolation.
- Replace home's automatically inset grouped List with one ScrollView and three
  full-width cards. Top spacing24pt, gaps16pt, card heights128–156pt from viewport;
  optional upcoming exam follows the entries so arrival cannot move them. Disable
  bounce only when content fits. Test the no-reminder case and pull settlement.
- Keep the shared Nagi blur and root title motion. Validate cancelled and completed
  pop for all three pages, ordinary back taps, term pinning, all previous UI tests,
  dark/compact screenshots, native gesture recording and Release packaging.
- No merge; preserve baseline and failed-run provenance, review before delivery.

## Evidence and review

- User screenshots reproduced the relative header motion before the navigation
  change: after normalizing both images to 590px width, the white content edge
  moved 114px while the title glyphs moved 100px. The <=3px relative-motion check
  failed with 14px of drift. The supplied photos/grades remain outside Git.
- Baseline UI 39918127961 was cancelled during simulator/test initialization;
  UI 39919260705 timed out during the six-minute cold simulator boot. Neither is
  feature RED or passing acceptance. The latter retained its simulator state;
  the build passed but native tests never ran. Boot now has a ten-minute bound.
- Production change 8ab25edd5ede07596e27c0c53aee747ab3eb7ad8 passed Release
  build 39919627312 and regression 39919624952. The downloaded IPA passed ZIP
  integrity; bundle com.imzhien.ccsut retains primary icon AppIcon. SHA256:
  247f5e08aebb8be34b113b8e22b5524523d6645cfb600237a576b719531eed37.
- Independent read-only review found no confirmed delegate ownership/restoration
  defect, but requested coverage of the public content-pop recognizer and vertical
  scrolling. testAcademicDetailSupportsContentSwipeBack in cecd9b0 first scrolls
  to a floating term strip and then performs an interior right-swipe. The final
  no-reminder home render must also be checked for excess lower blank space.
- A scoped diff against ea2e7d5 confirmed no changes to the icon, API client,
  authentication store or data models.

## Additional requested scope

- Label the existing four paired-period rails with the supplied time ranges:
  1–2:8:20–10:00; 3–4:10:20–12:00; 5–6:14:00–15:40; 7–8:16:00–17:40.
  Put start/end times on two lines within the existing 44pt rail.
- Current week's chip reads “本周”; other chips retain their week numbers. Keep
  initial scroll-to-selection with center anchor, and do not add edge blank space
  (explicit user correction).
- Remove top-right refresh controls from timetable, all academic details and the
  web login sheet. Retain pull-to-refresh, including academic empty/loading/error
  scroll surfaces. Web login uses WKWebView's native UIRefreshControl, ends it on
  load completion/failure through KVO, and keeps the existing reload semantics.
  The inline captcha reload is not a top-bar control and remains available.
- UI 39919624951 and 39920380984 passed all ordinary navigation, edge/content pop,
  vertical scrolling, home pull settlement and previous checks. Both failed the
  DEBUG cancelled-pop sampler with zero observations; video shows a real partial
  pop and attached header. This is a failed instrumentation check, not passing
  acceptance. Replace child-controller transition lookup with a UIView/window
  sampler gated by the native gesture states, and navigate through the actual
  home entry before the cancellation test. Preserve both failed runs.
- Add real pull-refresh invocation checks for all three details with and without
  data, plus native geometry/text checks for week centering and the supplied times.

## Additional verification

- Pixel check of the native cancellation recording from UI 39919624951: at 590px
  normalized width, resting frame22 versus held frames24–27 gives content shift
  116px and title shift 116.5px, or 0.5px relative error throughout the hold. This
  independently verifies the score header motion despite the old probe failure.
- Independent review of cecd9b0..e9d08ee found no confirmed refresh, lifecycle,
  time-label or week-selection defects. WKWebView refresh was inspected in source;
  no live school login or new authenticated network operation was performed.
- Production e9d08eeb1afebda33bfdf490b41af664f778eef9 passed Release
  39923025817 and regression 39923023769. The IPA ZIP is intact; bundle and primary
  icon remain com.imzhien.ccsut / AppIcon. Downloaded IPA SHA256:
  c4eb6b17eb9237972997671b22170ede9a93c6572ceecc1e0ded7ee500bce979.
- UI 39923023789 passed ten of eleven tests, including the corrected process
  sampler on all three details and populated/empty pull refresh. It found a real
  initial week-centering failure: chip midpoint 217pt versus viewport 201pt.
  Keep this RED result. Configure native view-aligned settling with an explicit
  center anchor, and register the unpadded HStack as the target layout. Keep the
  existing 16pt edge inset; do not introduce added edge blank space.

- The successful native cancellation captures in e9d08ee report 96/88/80 process
  samples for score/exam/elective respectively, each with 0.000pt local drift.
  Pop completion/cancellation, back taps, vertical scrolling, six populated/empty
  refresh cases, home settlement and pinned term geometry all passed in that run.
- Inspected native e9d08ee screenshots: light/dark home including the no-reminder
  case, normal/floating score term strips, and regular/compact timetable top and
  bottom. All four supplied time ranges fit their original rail without clipping;
  smaller corners, no top refresh buttons, and the three-card home are visible.
- Center correction a610ece3f4ef4f2d3ea3f46bffb81e6c535f7635 passed Release
  39926497996 and regression 39926495719. Its IPA passed ZIP/bundle/icon checks;
  SHA256: fce873d8389dc838bafb9dd08f5c99da820ccf58ec0345031ac6ef172acda7a8.
- UI 39926495887 retained the same ten passing checks but the initial chip moved
  to58pt instead of201pt. The anchor-only candidate is rejected. Replace the
  week bar's legacy ScrollViewReader/onAppear command with a centered semantic
  scrollPosition binding initialized alongside the selected week before layout.
  Use prefixed String week identities, separate from timetable day/period Int
  identities, and move the existing16pt inset to native scroll content margins.
  Check initial center, selecting the next week, and returning to the current week.
- Publish interaction logs/screenshots as an early artifact before the slower
  compact-simulator render; this preserves immediate failure evidence without
  changing the full suite or its pass criteria. Both previous center failures are
  retained. The browser live-log fallback was unavailable locally; it made no
  repository or account changes.
