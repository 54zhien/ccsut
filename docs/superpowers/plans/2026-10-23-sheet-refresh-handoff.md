# Sheet controls, refresh lifetime and header handoff

## Requested behavior

- Increase the account-entry avatar without filling the glass button.
- Keep profile identity centered; restore a wide logout button at the bottom.
- Use SF Symbols for sheet controls, with circular control centers concentric with the sheet corners.
- Open web login at the screenshot's large height. Web content fills the sheet; close, reload and Safari float over it. No pull-to-refresh in the web view.
- Hold the native page refresh area until the asynchronous load finishes, then let it settle.
- Keep the header blur mounted independently of fading title/actions.
- Reduce the gap between colliding pinned semester headers while retaining floating glass.

## Investigation and implementation

- The screenshot confirms the label-only `Button(role: .close)` rendered “Close” instead of a symbol. Shared sheet controls now use explicit SF Symbols (`xmark`, `arrow.clockwise`, `safari`), a 44-point circular glass surface and primary adaptive foreground.
- Sheet corner radius and the circular control inset share one metric: inset = radius - 22. The profile identity is centered in the sheet's full container, with the long logout button independently anchored at the bottom. The account-entry avatar changes from 28 to 34 points inside the existing 48-point control.
- The previous web sheet placed top/bottom bars in its layout and derived a detent from WKWebView content size plus those bars. This produced visible white bands and viewport/content-height feedback. The new single large detent matches the requested opening height; overlay controls take no space away from the web viewport. Automatic web content insets and pull refresh are disabled in the sheet; the same live WKWebView/session is retained.
- Academic pages used separate scroll views for placeholder and loaded content. They now keep one scroll view and one refresh attachment throughout loading, empty, error and data states. A native UIRefreshControl is attached to the nearest ancestor scroll view from the vertical content. Its target awaits the load before endRefreshing. A shared load gate joins an existing initial request instead of returning immediately from a concurrent pull. The academic landing page also refreshes its optional exam reminder.
- The previous header relied on the system's element-sensitive scroll-edge effect while its elements faded. That is a plausible explanation for the reported flash, not a reproduced device diagnosis. Nagi SearchView's public UIKit masked systemMaterial implementation is now continuously mounted under both root and academic detail headers. The automatic top edge effect is disabled to avoid a second material changing during the fade. No opaque color layer is added.
- Semester sections use zero stack spacing for native pinning, with card spacing inside the section. Each strip has one point above/below, leaving a two-point visual seam at collision. The successor gets glass when its measured top reaches the pinned header's height; native section headers still perform the push-off.

## Sources

- Nagi local source: `Nagi/Views/Search/SearchView.swift`, GradientMaskedBlurView.
- Apple UIRefreshControl: https://developer.apple.com/documentation/uikit/uirefreshcontrol
- Apple scroll-edge element containers: https://developer.apple.com/documentation/uikit/uiscrolledgeelementcontainerinteraction
- Apple Liquid Glass guidance: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

## Verification boundary

The user's no-tests/package-only instruction remains in force. Static source review and whitespace checks precede Release compilation and IPA integrity inspection. No app tests, UI tests, simulator interactions or physical-device acceptance are claimed. Refresh hold behavior, pinned-header collision, corner alignment and blur appearance still require device observation.

## Build and delivery

- Production commit: `d01545b2cb97be3d0ce2fc664b11a705c8330b7b`.
- Manual Release workflow: https://github.com/54zhien/ccsut/actions/runs/39962135365 — success; compile, package and artifact upload completed. No test step ran.
- Downloaded artifact: `D:/Codex/CCSUT-deliveries/d01545b/CCSUT-d01545b-unsigned.ipa`.
- Size: 4,557,415 bytes.
- SHA256: `812f7c3f7bb77bca6addd5c2d1c6461a2a85ef8f83b87ae5b29ba59a3db1f2a2`.
- ZIP integrity passed; executable present; bundle `com.imzhien.ccsut`; minimum iOS 26.0; primary `AppIcon`; actual Boolean `CADisableMinimumFrameDurationOnPhone = true`.
- The previous delivered `6437f5c` and its device feedback remain documented in `2026-10-23-web-fit-week-recovery.md`; it is not presented as device-approved.

## Follow-up: gradient coverage after d01545b

The user reported that the blur now looked like only a system layer. Current-source inspection confirms `NagiPersistentHeaderBlur` is still mounted, includes a gradient mask, and explicitly disables the system's automatic top scroll edge. It does not prove that the gradient is correctly visible on the device.

Comparison with the verified local Nagi checkout `9f5cd1a` identifies a porting difference: Nagi Search explicitly gives the blur a height of safe-area top + header + 12-point tail and offsets it by the negative top inset. d01545b instead used an inferred SwiftUI background size, negative bottom padding and ignoresSafeArea, while deriving the mask fraction from the window's safe area. Those two geometry sources are not guaranteed to describe the same container.

The follow-up restores Nagi's explicit frame and upward offset, using the local container's safe area and the measured header height for both coverage and mask stops. The blur remains mounted outside label/control opacity. The material itself remains the same adaptive UIKit systemMaterial used by Nagi; this is a gradient alpha mask over that material, not a separately implemented variable-radius Gaussian filter.

This is a correction of the identified source-level layout deviation. Whether it explains the entire reported device appearance remains unverified. No application tests are authorized for this follow-up.

### Additional steering: native button size and permanent mask

The user reported the 44-point sheet circles were too small and explicitly requested the gradient mask remain present. Apple describes 44 points as a minimum hit region, not a prescribed rendered button diameter (https://developer.apple.com/design/human-interface-guidelines/buttons). Shared sheet controls now use native `Button` with an icon-only SF Symbol label, `.buttonStyle(.glass)`, `.buttonBorderShape(.circle)` and `.controlSize(.large)`. The manually assigned frame and symbol font are removed. Header/web inset calculations use the measured native control diameter. Account and timetable course headers share this component; web close, reload and Safari use it as well.

The blur view and gradient mask are unconditionally mounted. Only the title and action content receive the visibility animation. Mask stops depend on container geometry, never scroll offset or header visibility.

Intermediate blur-only commit `cc9975b04bc56e411e15a0358488937e53801d85` compiled and packaged successfully in https://github.com/54zhien/ccsut/actions/runs/39964534410. It was not delivered because the additional button-size request arrived before delivery. The final artifact must include both changes.

### Follow-up delivery evidence

- Final production commit: `f0412c844384f03574aad759adae8e9480e8974a`.
- Release compile/package success: https://github.com/54zhien/ccsut/actions/runs/39965258839.
- Download: `D:/Codex/CCSUT-deliveries/f0412c8/CCSUT-f0412c8-unsigned.ipa`.
- Size: 4,564,725 bytes; SHA256: `9f71690e587c98d2a816da82c134229d1d68feda8857f805beb336ea45adfee5`.
- ZIP integrity, executable, bundle `com.imzhien.ccsut`, minimum iOS 26.0, AppIcon and actual high-refresh Boolean verified.
- No app/UI/performance tests run; no claim of rendered blur or native button-size acceptance on the physical device.
