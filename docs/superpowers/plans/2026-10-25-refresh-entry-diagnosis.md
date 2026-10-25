# Refresh entry diagnosis

## Latest scope and evidence (supersedes earlier hypotheses)

The user clarified that the defect is the missing pull/spinner/retained loading area compared with the timetable. Whether data updates is currently unknown and is not the acceptance criterion. They explicitly requested direct synchronization with the timetable instead of more build-number questions.

- Controlled completion replaced the earlier two-second sampling. Screenshots are captured before a test-only completion button releases a continuation; the read cannot have finished before that screenshot.
- Run 40178129369 reproduced the contrast in one simulator: timetable has a visible native spinner and held refresh area; scores have already returned to rest while still awaiting completion. The score chrome-outside-reader case failed to launch and is not a valid negative comparison.
- Controlled omission of pop support, top scroll edge, or attachment outside chrome did not restore the score feedback (40177523210). A custom pop gesture has not been established as the cause.
- Primitive ScrollView, wrapped ScrollView and List screenshots in 40177592621 all show native refresh feedback. The wrapper's publication assertion failed separately; it is not evidence that its visual feedback was absent.
- The iPhone Duo runtime in 40177680576 shows a visible score spinner/held gap. It is a different device/runtime from the user's phone and does not constitute device acceptance.
- The independently owned native subview reference in 40178591876 passed its completion check; its raw native ScrollView reference failed. Preserve this mixed result rather than calling the run green.
- Baseline held-position assertion: 40179739102 at cef415b. Timetable-hierarchy score candidate: 40179838441 at 60ad49e. All-page synchronization candidate: 40180032458 at 6f49e18. These runs were pending when this entry was written.

Implementation scope is in `2026-10-25-refresh-animation-sync.md`. Existing load gates, API methods, authentication and writes remain unchanged. Synchronizing source structure is still a candidate until rendered held-gap checks pass.

## Device report and scope

- User reports iPhone 15 Pro Max on iOS 27.2, with the renamed 长工院 package.
- Scores scroll normally. At the top, pulling from the middle of a score card still shows no refresh indicator.
- Timetable refresh works. This does not establish that the score network callback was never invoked.
- Source under investigation: `codex/campus-optional-location` at `0ba689544a1bd0a3edb0f2ae80e2cd70008c6c22`.
- The first navigation comparison changes tests/workflow only; its application source is identical to that base. A later, separately flagged DEBUG-only probe observes slow-load refresh feedback. Release refresh behavior is unchanged.

## Verified source and historical evidence

- All supported native page refreshes use the SwiftUI `pageRefreshable` wrapper. The campus home is a static navigation page with no refresh attachment.
- Timetable, scores and exams all use the same `PageLoadGate`. Joining an initial network request is not evidence that the refresh gesture failed.
- Campus records independently drop concurrent read calls through their loading guards. That defect cannot explain a score page with no visible refresh control.
- The final historical UI validation used application source `6926342` and test source `e4bd41f`, already using SwiftUI `.refreshable`. Run `40014163351` succeeded; its API status was rechecked during this investigation.
- The historical test waits for initial snapshot publication before pulling, uses short fixture lists, and starts directly in the academic tab. It does not cover the normal timetable-first route or the user's iOS 27.2 device.
- Earlier diagnostics recorded refresh callback entry followed by cancellation on academic pages, while the gated fetch could continue. Publication counts alone do not prove that the spinner remained visible throughout loading.
- Source comparison from `6926342` to `0ba6895` shows no change to the score refresh attachment, `PageSurface`, `AcademicNavigation`, or `NagiPageChrome`. MainTabs gained the campus tab; scores gained grade-summary corrections.

## Current hypotheses

1. Refresh installation or lifecycle depends on entering through TabView and pushing a page after timetable was mounted.
2. Real list length/content changes the behavior missed by short fixtures.
3. Runtime behavior differs on the reported iOS 27.2 system.
4. The refresh action starts but its indicator collapses before the asynchronous work finishes.

The custom pop recognizers remain a hypothesis, not a proven cause: their begin delegate rejects vertical pans. No pop, chrome, scroll container, or payment behavior is changed speculatively.

## Controlled simulator check

Diagnostic commit: `ff736bef50b429bb7187cc6e26be3fa1e1aeb8ea`.

- UI run `40172419480` selects the existing six short/empty academic cases and timetable control, plus two long-list cases and three timetable-first navigation cases.
- The new route is timetable -> academic tab -> real scores/exams/electives navigation link. It waits for the initial snapshot, pulls once from the middle of the body, and requires exactly one additional publication plus retained content.
- Before/after screenshots and the normal interaction video are retained by the workflow.
- Automatic source-regression run: `40172412576`.
- Run `40172419480` succeeded: six tests, zero failures. All eleven academic scenarios published one additional snapshot; the timetable control also passed. Actual environment: iPhone 17 Pro / iOS 26.4.1, Xcode 26.6 with iOS 26.5 SDK. Source regressions `40172412576` also succeeded.
- The interaction recording contains body movement and snapshot publication, but sampled score frames do not show a clear spinner. The 250 ms fixture is too short to establish sustained feedback. Do not equate the publication assertions with a passed spinner-lifetime check.

## Reported-system comparison

- GitHub supplies a separate `xcode-27` runner, with Xcode 27.2 available. Its iOS 27.2 simulator runtime can be downloaded using the documented Xcode platform command.
- Run `40172871198` failed before building/testing: the downloaded runtime identifier had a device suffix; the initially assumed generic identifier was invalid.
- Run `40173190787` failed before building/testing: after discovering the actual identifier, CoreSimulator returned `Incompatible device` for iPhone 15 Pro Max. These environment failures remain preserved and are not application regressions.
- Commit `3d5efd7` selects a compatible device from runtime/device metadata and logs when it differs from the reported physical model. Run `40173450343` used iPhone Duo / iOS 27.2: direct short/empty and long academic refreshes and the timetable passed. Three timetable-first cases failed at the `app.tabBars.buttons["教务"]` lookup, before entering the target page. Those selector/layout failures are not evidence that academic refreshing failed.
- The 27.2 comparison also uses a newer compiler/SDK. Even a pass cannot rule out behavior specific to the shipped older-SDK binary on the physical device.

## Slow-load native feedback observation

- Commit `b7098e6` adds a two-second score fixture activated only by `--preview-slow-refresh`, a read-only native control probe, and one focused UI test.
- The probe records callback entry/completion/cancellation, observed `UIRefreshControl.isRefreshing`, pull distance and control frame/visibility properties. It does not assign a refresh control or modify gesture delegates.
- Observations are stored in a plain reference object; the refresh callback does not publish SwiftUI `@State`. A separate accessibility-only timeline exposes them to the UI test.
- Run `40173747618` passed on iPhone 17 Pro / iOS 26.4.1. After release, callback counts were entered=1/completed=0, the native control reported refreshing=true/hidden=false, and the refreshed snapshot later published once. No premature native-state stop was observed. The screenshot still showed no spinner.
- Run `40174123248` obtained a generic iOS 27.2 runtime and successfully used iPhone 15 Pro Max, matching the user's reported model and OS version. It passed the same slow-load state/publication checks; its after-release screenshot also showed no visible spinner. The control class was `SwiftUI.PlatformRefreshControlProxy`, versus `SwiftUI.UIKitRefreshControl` in the 26.x observation. A proxy frame must not be treated as the actual indicator glyph's screen frame.
- Both observations ended with callback cancelled=true, but the native refreshing state persisted through the load and data publication completed. Cancellation alone is not evidence that the read or native state ended early; it does not prove visible feedback/held spacing either.

## Top-bar-only omission

- Commit `be34b21`, run `40174718567`: two state/publication tests passed, with and without the top bar. Both after-release screenshots still lacked a spinner.
- Therefore top-bar-only occlusion is not established and removing the top bar is not a repair. The earlier control-frame overlap was a hypothesis, not a root-cause conclusion.
- No accepted header styling, gesture behavior or Release refresh implementation is changed by this DEBUG-only experiment.

## Remaining single-factor comparisons

- Commit `437d10c`, run `40175427310`: four state/publication tests passed for the baseline, omitted pop-support controller, hidden top scroll-edge effect, or refresh attached outside the detail chrome. Sampled after-release images all lacked a spinner. Native active records showed contentOffset.y=-126, adjustedContentInset.top=126 and contentInset.top=0.
- These are single-factor experiments; none demonstrates a repair. In particular, successful publication/native-state assertions do not prove that feedback is visible.

## State/task ownership comparison and measurement correction

- Commit `0c22f0d`, run `40175854223`: the baseline and omitted-isLoading-publication cases passed state/publication assertions. The inline-load experiment failed: the refresh callback completed cancelled=true without a second publication. Bypassing the unstructured load gate therefore loses the fetch under callback cancellation; removing that protection is not a repair.
- The two-second fixture permits screenshot/AX timing ambiguity. Do not label an image as definitively mid-refresh solely because a nearby accessibility read reports active=true; these reads and screenshots are not one atomic sample. Earlier visual-absence statements need this qualification.
- Commit `c69e5dd` replaces timing assumptions with a controlled second score read. A DEBUG-only continuation cannot complete until the UI test taps `完成诊断刷新` after its screenshot. The initial read still completes normally. The test requires the initial publication count to remain 1 before the screenshot, then releases the continuation and requires count 2.
- The screenshot uses `XCUIScreen.main.screenshot()` and includes a visible DEBUG-only native observation panel, making active/completed state visible in the captured frame itself.
- Run `40176551951` is pending for the baseline, no loading-state publication, and inline-load variants. Preserve all previous runs; do not reclassify their publication checks as visual acceptance.

## Next decision

- If a new case fails, inspect that first failure and compare it with the unchanged control cases before changing application code.
- If all cases pass, record that the device symptom remains unreproduced. Obtain runtime/control/callback observations on the affected environment rather than replacing the existing refresh implementation without evidence.
