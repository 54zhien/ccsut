# Scoped Liquid Glass controls and layout

## Scope and implementation

User requested only score/exam filter controls, campus add/form controls, the
mechanical recharge amount display and minimum, elective presentation/closure,
and detail navigation's tab-bar animation. The later refinement also requests
student-name display recovery and investigation of blank background previews.
API endpoints, HTTP requests, response decoders, authentication verification,
top material blur, timetable logic and submission/payment protocols are unchanged
by the refinement.

- Score/exam menus use SF `line.3.horizontal.decrease` and native circular
  interactive Liquid Glass on a48pt circle matching NagiBackButton, with neutral
  foreground/tint. Historical term selection is preserved.
- Campus plus circles use64pt interactive native glass tinted with the theme.
  Their measured
  rendered size and public container corner radius determine physical offsets.
  Form/confirmation closes use `.primary` and `.tint(nil)`. Submission capsules
  use measured height H and corner radius R, with physical inset R-H/2; only
  their label compression/width is constrained at large accessibility text.
- Meter retains native three-wheel interaction inside a recessed silver enclosure
  in light appearance and the existing dark enclosure in dark appearance. The
  local amount card uses44pt outer corners (24pt meter corner plus20pt inset).
  Minimum selection/confirmation is10 yuan; 400 and lower server
  limits remain. A server cap below10 disables recharge. No transaction is sent
  automatically or replayed; order reconciliation remains unchanged.
- Elective controls remain top-aligned through loading/closed/empty states.
  Only observed `-1 / 没有可选的教学班` is closure. All/available/free display
  `选课通道暂未开启`; independently loaded enrolled/history results remain visible.
  Per-batch closure aggregation preserves successful batches and prioritizes
  genuine failures. The later refinement uses restrained semantic backgrounds
  for search/filter/term controls rather than glass on every control. Empty-state
  intrinsic size and header height are measured to center status at the visible
  viewport midpoint, clamping below controls at large Dynamic Type. Campus record
  empty states and form terminal/error states are centered similarly.
- Actual system tab bar visibility remains under UIKit. Navigation coordination
  adds translation and fade, handles cancelled pops, and honors Reduce Motion. DEBUG sampling
  checks real public tab-bar presentation layers, not just terminal hittability.
- AGENTS.md records the user's future requirement to consult current Apple docs,
  use native Liquid Glass where applicable, honor explicit page exceptions and
  preserve unrequested UI.
- Optional student-name publication no longer requires the response to repeat an
  optional account field after independent identity verification. Explicit account
  mismatches and stale generations remain rejected; blank data and unavailable
  selection metadata retain an existing name. Request behavior is unchanged.

## Official references checked

- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/glassbuttonstyle
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/view/controlsize(_:)
- https://developer.apple.com/documentation/swiftui/edge/corner/style/concentric
- https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator
- https://developer.apple.com/documentation/uikit/uitabbarcontroller/settabbarhidden(_:animated:)
- https://developer.apple.com/documentation/quartzcore/calayer/presentation()
- https://developer.apple.com/documentation/swiftui/glass/tint(_:)
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/documentation/uikit/uiview/transform
- https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:)

## Preserved verification history

- Meter boundary RED then19 GREEN; model minimum RED3 sub-ten failures then
  existing API/model suites GREEN. Native scoped logic later passed as well.
- Elective closure RED2 then17 GREEN. Review expanded mixed-batch regressions:
  RED14/40 then40/40 GREEN. State31 and enrolled40 checks also passed locally.
- Whole-branch review found and resolved mixed-batch false closure and a failed
  nil-order receipt's minimum-value rebinding. Scoped re-review passed.
- `40270430536` at `3bd9791`:9 native UI checks passed and36 appearance captures.
  Manual image review found an accessibility-size CTA overflowing horizontally,
  despite the previous weak assertion passing; the image was preserved.
- `40271249134` at `0b0b7b2`:8/9 passed; new touch-bound assertion measured the
  native regular menu as42pt. Fixed using native large control size.
- `40272320541` at `d895fc8`: large-text CTA containment/symmetry, keyboard and
  departure checks passed. Leave bulk input yielded `reson` rather than `reason`;
  the failed recording was inspected. Product editor logic was not modified.
  Test now sends each literal prefix character once and requires exact AX
  acknowledgement before continuing, with no retries or correction. This is
  test-protocol stabilization, not evidence of a fast-input product repair.
- `40272717521` at `7b43089`: native >=44pt menu bounds and historical selection
  passed. Both earlier failures and their artifacts remain available.
- Source `6e2126f`: Release `40274748500` passed. Final nine-check native run
  `40274745342` includes actual intermediate tab movement+opacity assertions,
  input acknowledgement, interaction recording and13 selected appearance pages.
  Eight checks passed; actual motion check failed because the original detail
  sampler attached after most of the navigation had completed.
- `40277047934` at `040b0e9`: persistent root sampler observed482 valid frames,
  zero missing/detached frames, opacity0..1 but Yrange0. Motion check failed,
  terminal root restoration passed. This is why actual public UITabBar translation
  was added beside UIKit's visibility operation. Release40277051548 passed.
- Student-name extracted production methods: three RED assertions before the
  local publication correction, seven GREEN after it. No school requests used.
- Source734480f: native UI40281319923 passed11/12. Release40281320383
  passed; final IPA ZIP CRC, arm64 Mach-O, display name长工院, bundlecom.imzhien.ccsut
  and minimumiOS26.0 passed inspection. Size5,962,510bytes; SHA256
  `90539d290980df2bccf97aaef5f572dde407f7511011ca3e3921bb37c29344f8`.
  Exact48pt equality,64pt campus add bounds, centered empty-state geometry,
  form/keyboard/amount/search checks and background roundtrip passed. Actual tab
  push/cancelled-pop movement passed on all three academic pages (Yrange40–74pt,
  alpha0..1), but completed pop did not restore root tab hittability. This failed
  run is retained. Sourcec0ae485 now reuses the appearance captured while visible
  instead of capturing UIKit's hidden bar as the target. Focused nav run40283378973
  still failed completed-pop root hittability; strict push/cancel motion passed
  all three pages. Captured baseline alone is not a proven repair. Release40283379161 passed.
- Current c0ae485 IPA inspection: ZIP CRC, arm64, app name/bundle/minimumOS passed;
  5,962,641bytes, SHA256
  `df68ae3908acd3f639f93179ccf74c0cf59d2ee42f815f25494a9e95dd00783a`.
- Diagnostic-only source0996dab adds preview lifecycle/completion/geometry logs
  persisted outside the disappearing detail. Run40284819477 isolates the failed
  normal-return test without changing its assertions or production behavior. It
  failed at app.launch with a background-assertion timeout, before push/back ran;
  the diagnostic was dispatched separately as40286111557 on a fresh runner.
  That run reproduced the product failure: show entry reached root, completion
  had live self and matching transition ID, nativeHidden/isHidden were false,
  alpha1 and transform0, but actual center changed832.5 to749.5 and window top
  changed791 to708. The83pt error persisted after settling. All ancestors were
  visible with alpha1. Missing show, released owner and alpha baseline are ruled
  out for this case; the actual misplaced layout is established.
- Original c0ae raw console recovered from preserved xcresult using the installed
  Git libzstd confirms show entry and alpha1/transform0. The final AX bar frame
  was y708/h83 on an874pt screen, one full bar height above the expected bottom
  frame. Visible point remained(-1,-1). This supports a transform/native-layout
  ordering error, not a missing show call or hidden alpha baseline.
- Source08c6077 normalizes the transform before native visibility/layout calls,
  then stages custom presentation movement afterward. It also normalizes before
  terminal/cancelled native visibility. Strict two-test navigation run40286432215
  passed2/2 with zero failures; no test assertions or wait limits changed. All
  three academic pages recorded simultaneous down/fade and up/fade motion,
  Yrange83pt, alpha0..1, zero missing/detached samples. Completed academic and
  campus returns restored hittable tabs. Final/settled logs show center832.5,
  window top791, nativeHidden=false, isHidden=false, alpha1 and transform0.
  This directly resolves the recorded83pt displacement. Release40286496396 passed.
  IPA ZIP CRC, arm64 executable, app name/bundle and minimumiOS26 passed inspection;
  size5,963,257bytes, SHA256
  `822a3559a5945c8aaa6dfd723dc2a0acfd790a9e27c1cabecee9cf2e43163383`.
- Scoped refinement review of040b0e9..734480f found no concrete blocking issue;
  the narrow0996dab..08c6077 ordering review also found no blocking source issue.
  Runtime tab restoration is now established by the exact-source tests above.

## Scope decision and delivery state

The explicit requested changes were implemented without another approval gate;
no additional product scope was inferred. If a visual interpretation differs
from the user's intention, the remaining cost is a scoped UI adjustment after
device review. The task branch and worktree are retained; main was not merged.
Final production source is08c60775603a4e7c2dfc863301e7ed9d2d87b467. Subsequent
review-document commits do not change the app. The native package is unsigned;
physical-device installation/acceptance and actual-account name display remain
unverified. All earlier failed tests and the separate simulator launch failure
remain recorded above rather than being replaced by the passing result.

## Background display investigation

The native test used a real Home-indicator gesture and pause to capture the app
switcher, then activated the app again and checked the previously loaded content.
Timetable and score snapshots retained their visible data. The campus leave
reason became a gray privacy placeholder in the switcher and was restored on
return. That view already has SwiftUI privacySensitive; Apple's documented
privacy redaction and the captured before/switcher/after images explain this
specific result. No model or API change was made for it. Entire-page blanking was
not reproduced in these three synthetic cases; do not infer that every device
or live-account background symptom is explained by this observation.

Native screenshots reviewed confirm normal-size neutral close controls,
concentric add/submit placement, equal neutral filters, centered closed/campus
empty states, restrained elected-course controls and light silver/dark meter.
At maximum accessibility text, elective filters remain horizontally scrollable
and the empty message wraps without overlapping the controls. The repaired
form CTA is contained; pre-existing horizontal overflow in very large form date
controls remains outside the requested styling scope. Physical-device appearance,
animation feel and actual-account name display remain acceptance items.
