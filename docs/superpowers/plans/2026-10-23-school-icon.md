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

Files: `design/icon-source/` retains the unchanged user SVG and Nagi JSON;
`tools/build_app_icon.py` derives the five SVG layers and parameter package;
`ios/CCSUT/AppIcon.icon` is the primary icon resource in Xcode. Remove the old
flat graduation-cap app icon set to avoid retaining the old artwork.

Validate generation/geometry locally, compile the actual .icon on macOS, inspect
compiled light/dark/mono appearances and render outputs, build the Release IPA.
Do not change Swift pages, business logic or merge the draft PR. Native icon
rendering and physical-device acceptance remain separate evidence.
