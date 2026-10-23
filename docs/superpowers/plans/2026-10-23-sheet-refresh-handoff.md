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

Build and delivery evidence will be recorded after the workflow completes.
