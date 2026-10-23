# Official-material and login recovery repairs

Scope follows device feedback on e27412f. No app tests, per the user's standing
instruction; compile/package and artifact inspection only. Do not merge main.

## Findings and bounded fixes

- Semester glass regression: the previous tracker mixed global viewport/insets
  and removed headers once their layout frame passed the pin edge. A pinned
  LazyVStack header can retain its natural layout geometry. Restore the working
  named scroll coordinate and keep the active header glass irrespective of its
  scrolled layout bottom. Apply a small 2pt handoff allowance to the successor.
- Restore the original five-color course palette from6d6a7a5. The school-blue
  accent remains for controls and navigation, independently of course colors.
- Sheets already have the system material. Remove custom full-sheet glass and
  clear presentation overrides. Use native glass button styles for close/logout,
  preserving medium detents and centered profile content.
- Native scroll-edge effects respond to registered bar contents. Their region
  can change as the custom header fades. Keep a system bar material persistently
  mounted outside that animation and use one shared64pt top-bar wrapper for both
  root pages and academic details. This is a source-level causal hypothesis;
  device verification remains outstanding without UI testing.
- Academic content cards get26pt corners, overview/filter panels28pt; semester
  strips retain their previously requested18pt corners.
- Login content fills at least the available safe-area viewport and centers as a
  group; smaller/keyboard-constrained layouts can scroll. Use a1pt separator with
  equal20pt insets; both sides of the OTP row use20pt, including the send label.
- Shared web-login sheet currently only reparents the existing web view, even
  after a failed initial navigation. reload() also lacks a fallback when no page
  committed. Reset navigation errors, restart the CAS request when recovery is
  needed, and cancel/invalidate native SMS timing when entering manual web login.
  Keep one WKWebView/cookie store and existing CAS adoption. Native NavigationStack
  toolbars supply close/reload and bottom-right Safari controls; no custom glass
  sheet background and no heading.
- Anonymous read-only HTTP observation: CAS entry returned200 in3.49s; the TLS
  service endpoint closed its connection after14.31s from this computer. This
  does not prove the user's device network or authenticated redirect behavior.

## Apple references checked

- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/material
- https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)
- https://developer.apple.com/documentation/swiftui/glassbuttonstyle
- https://developer.apple.com/documentation/webkit/wkwebview/reload()

Apple specifies that system sheets adopt the material, standard toolbar/button
styles provide controls, and full-height sheets become more opaque to focus the
task. Do not force a second glass layer to make a large sheet more transparent.

## Delivery

- [ ] Source changes and diff review.
- [ ] Release compilation/package; no application tests.
- [ ] Downloaded IPA integrity, metadata and hash inspection.
