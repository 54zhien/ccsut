# Brand, login and week motion refinement

**Goal:** Apply the user's supplied artwork and native login reference; refine
week following motion, dark appearance, course sheet and academic entries.

**Architecture:** Keep existing CAS/session and school data flows. Separate
animated seal ring from static core. Isolate week animation from timetable layout.

**Constraints:** User explicitly requests no tests for this package. Run only
source/asset review and the Release build needed to produce an IPA. Preserve
draft PR2 and existing failed/cancelled evidence. Do not change app icon assets.

- [x] WeekSelector: independent non-interactive glass chips, selected-week anchor,
  right drag trails only left-hand chips with increasing delay; mirror on left
  drag. Bound displacement, no fusion, preserve default center/no added margins.
  Remove per-frame invalidation of the whole schedule and honor reduced motion.
- [x] Pass SwiftUI color scheme to native masked header blur; use explicit light
  and dark material only on scheme changes. Lighten dark empty timetable cells.
- [x] Course details: fixed medium detent, compact header/close and consolidated
  teacher/location/time/weeks layout with semantic colors and internal scrolling.
- [x] Academic home: shorter entries and always-available vertical bounce, while
  keeping the existing top spacing and optional exam reminder below entries.
- [x] Login: adaptive white/black background; seal above supplied signature;
  two-row grouped account/code input and prominent login button. Sending code
  retains keyboard. Existing native-backed CAS/WebKit/timeout flow stays intact.
- [x] Web login: large-only sheet; no top title; top-left close, top-right reload,
  bottom-right Safari. Safely transfer the same WKWebView between native cover
  and sheet, preserving cookies and avoiding simultaneous ownership.
- [x] Startup: adaptive plain background, centered seal plus loading label;
  rotate only border/name ring, static core. Reduced motion stays static.
- [x] Review DeepSeek exam branch's semester grouping changes and merge into the
  current packaging branch if sound. No main/PR2 merge is implied.
- [x] Compile Release, verify IPA ZIP/bundle/icon and deliver, without test runs.

Design direction: retain native system typography/controls and school artwork,
with plain semantic backgrounds and a grouped input surface matching the user's
reference. Generic AI palette/style recommendations did not match the reference
and were discarded; SwiftUI focus guidance is relevant. The signature PNG stays
unaltered; native clipping removes the duplicate seal beside the wordmark.

DeepSeek review: origin/fix/exam-term-grouping at cdf752f changes only ExamView
and ExamItem. API already requests each semester explicitly; tagging each result
with that request's term gives a suitable grouping key independent of the server
context field. Optional term preserves decoding/memberwise initialization fallback.
No transport, sorting, login or unrelated business changes were present. Merged
into ui/navigation-timetable as c4af4c2; main and draft PR2 were not merged.

Source review corrected login cleanup when a successful web login removes the
root login page while its browser sheet is visible. Temporary sheet coverage
preserves operations; session-driven root removal cancels outstanding timers.
Existing CAS JS is unchanged. Native keyboard, sheet handoff and new motion
have not been executed or accepted on-device, per the user's no-test request.

Release preflight39944481253 at be96eaa compiled the brand/login/detail UI and
merged exam model successfully, without running tests. This is an intermediate
build, not the final package with the revised week selector.

Enable the generated CADisableMinimumFrameDurationOnPhone boolean for Debug and
Release so the week display link may request the device's supported refresh rate.
Apple's ProMotion guidance requires this opt-in for preferredFrameRateRange hints:
https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
This config does not prove measured frame rate; no performance run is claimed.

Week refinement source review: WeekSelector owns the observable display-link
state, so the schedule no longer reads a changing per-frame time. Immutable
Sendable frame snapshots remain the only visualEffect input. For rightward drag
(decreasing native offset), only weeks before selectedWeek receive displacement;
leftward drag mirrors this. Delay starts at70ms and adds45ms per following week,
up to300ms, with40pt displacement cap. Native scroll continues on the other side
without extra motion. Keep500ms history and stop the clock400ms after idle.
Shared GlassEffectContainer and interactive glass are removed from week chips.
The native reader/16pt margins and reduced-motion/reset paths remain in place.

Final-source4513c7481c10747f4ac03d422138fcf1dc6abef4 passed Release39945348726.
Downloaded IPA ZIP, bundle and primary icon were intact, but inspecting the final
Info.plist found CADisableMinimumFrameDurationOnPhone absent. The generated
INFOPLIST_KEY build setting was not emitted. Preserve that incomplete-config
artifact as provenance; add an explicit minimal Info.plist merged with generated
bundle metadata for both configurations, then rebuild the changed configuration.
No tests were run; this was final artifact metadata inspection.

Final production f459c4ebe66e7826162ad7b5326de7690fc4b6c3 passed Release
39945640388. The downloaded IPA is4533258bytes; ZIP integrity, bundle
com.imzhien.ccsut, primary iconAppIcon and the actual Boolean ProMotion opt-in
all pass final artifact inspection. SHA256:
3b4daacb6d218c9a3089b12b909a1c9de27f9fd91d34754bd455617a2e6554c9.
No app tests or performance measurements were executed. Changes to session/API
and AppIcon remain absent; the explicitly reviewed exam model change is included.
Further commits only record this evidence; production sources stay identical.
