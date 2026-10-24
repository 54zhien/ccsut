# School seal Icon Composer package

Use the user's transparent outlined school seal as the artwork. Copy Nagi's
Icon Composer package structure first, then adapt only CCSUT's copy. The user
explicitly specified the default white background, default black dark background,
and default shadow. Therefore use `system-light` / `system-dark` fills and leave
shadow unset so the system supplies its preset. No SVG shadow or baked background.

Keep the complete school seal and original path geometry. Normalize the canvas
to 1024 and center it; separate the outer text/seal, rings, central mark, orange
accents and facets. Retain Nagi's glass layer setup while disabling translucency
to keep the thin outlined lettering legible. Use brighter blues in dark mode.
All five layers share the same canvas and transform to preserve alignment.
The outer stroked circle is outlined as an equivalent filled annulus because
Icon Composer layer fills otherwise turn that circle into a solid disk. The
13 supplied outline paths remain unchanged, alongside the two original dots.

Files: `design/icon-source/` retains the unchanged user SVG and Nagi JSON;
`tools/build_app_icon.py` derives the five SVG layers and parameter package;
`ios/CCSUT/AppIcon.icon` is the primary icon resource in Xcode. Remove the old
flat graduation-cap app icon set to avoid retaining the old artwork.

Validate generation/geometry locally, compile the actual .icon on macOS, inspect
compiled light/dark/mono appearances and render outputs, build the Release IPA.
Do not change Swift pages, business logic or merge the draft PR. Native icon
rendering and physical-device acceptance remain separate evidence.

Validation record:
- User SVG is an exact byte-for-byte copy; Nagi source package was not changed.
  Deterministic generation preserves all 13 original path strings. Outer-border
  annulus uses the source center and inner/outer stroke radii.
- Initial native compilation succeeded but the appearance verifier incorrectly
  counted all appearance references in one stack (`39914068439`). The verifier
  now resolves the matching standalone group and correct appearance reference;
  the original failed run is retained.
- Native small PNG inspection exposed the filled outer-circle issue, fixed by
  outlining the circle. Superseded UI previews `39914068408` and `39914424247`
  were cancelled to free macOS runners; these are not acceptance results.
- Final production-resource SHA `d1b0287`: regression `39914599804` and Release
  IPA `39914600983` passed. IPA ZIP integrity and `CFBundleIconName=AppIcon`
  verified after download. Subsequent changes only affect verification tooling.
- Native compiler/appearance inspection and Icon Composer exports passed at
  `3ee4760`, run `39914946258`, using identical production resources. Default
  and dark renders were inspected, along with the exported tinted rendition.
  Compiled system backgrounds are default white/black gradients; leaving shadow
  unset resolves to neutral style 3, opacity 0.5. All five vector layers have
  lighting effects. The renderer is located independently when the selected
  Xcode does not bundle the Icon Composer app (`39914599779` records this failure).
- Independent review's important appearance-query finding is fixed. No Swift
  page or business-code edits. Native UI run `39914599825` passed all seven
  interaction tests with zero failures. Draft PR remains unmerged; real-device
  icon appearance is still for the user to confirm.
