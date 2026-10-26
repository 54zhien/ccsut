# Scoped Liquid Glass controls and page refinement

User requirements are the authority. Only the named surfaces change; the existing
login fix, top blur, timetable, branding, authentication and transaction safety
remain outside this change. New applicable controls use current Apple public
Liquid Glass APIs, semantic SF Symbols and accessible native interaction.

- Score/exam filters: native glass Menu, SF `line.3.horizontal.decrease`, preserving
  the existing term selection and right-hand location.
- Campus records: native circular glass plus with its center concentric to the
  actual container's bottom-right corner, using public container curvature.
  Leave/departure form close controls use neutral primary styling. Primary form
  submission capsules share the physical bottom corner centers, including the
  review/confirmation step. No form logic or real submission changes.
- Electricity: refine the existing black three-drum meter with a restrained
  enamel bezel, a single coherent reading window and stronger digit hierarchy.
  Native wheel pickers and Dynamic Type remain. Minimum payable amount is 10
  whole yuan; current 400/server limits remain. Limits below 10 disable payment;
  no payment, order reconciliation or automatic retry behavior changes.
- Electives: keep search/filter controls anchored at the top in loading, closed,
  populated and empty states. Precisely classify the known closed-channel
  response, show `选课通道暂未开启` for all/available/free, and retain independently
  fetched enrolled/history results without displaying that closure as an error.
  Refine native filter/term controls and course-card hierarchy only on this page.
- Detail navigation: the actual system tab bar sinks and fades during push,
  reverses during pop, and follows interactive cancellation. Respect Reduce
  Motion. Keep the existing system tab items, navigation and back gesture.

Chosen approach: public native glass controls and UIKit transition coordination
inside existing SwiftUI pages. A replacement custom tab bar or broad global
restyle would exceed the user's explicit scope. The existing isolated worktree
is reused. User's detailed action request authorizes these reversible changes;
routine aesthetic details above are implementation choices.

Apple references checked 2026-10-26:
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/glassbuttonstyle
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/edge/corner/style/concentric
- https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator
- https://developer.apple.com/documentation/uikit/uitabbarcontroller/settabbarhidden(_:animated:)

Verification: targeted logic regressions, native simulator interaction/screenshots
in light/dark and accessibility text, Release build and IPA inspection. Preserve
failed-run evidence and report device acceptance separately.
