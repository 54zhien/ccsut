# Nagi page chrome implementation plan

Goal: reuse the requested Nagi header, masked material and scroll title animation in the existing CCSUT UI preview.

Source: local Nagi 9f5cd1a6b2cfa638044a90b5713ad682c8f4b9dc, LibraryView.swift (header/visibility) and SearchView.swift (masked material).

Scope: top-level timetable and academic pages. Retain all API/session behavior, timetable layout and secondary navigation. Direct source adaptation is appropriate because both applications already target native SwiftUI/iOS 26; introducing a package would couple CCSUT to the entire reader application.

- [x] Inspect the requested source, including animation thresholds, reduced motion and blur mask.
- [x] Adapt the shared header into NagiPageChrome.swift and register it with Xcode.
- [x] Bind real vertical scroll geometry independently on each page; preserve secondary native navigation.
- [x] Record native simulator header hide/reveal and inspect screenshots, including dark and compact.
- [x] Build Release, run existing regressions and review the final diff before updating draft PR #2.

Acceptance: 38pt scaled title, 48pt circular controls, 8pt hide/0.5pt reveal hysteresis, 0.25s easeInOut, delayed 8pt button blur, no blur animation with Reduce Motion. Status-bar-to-header gradient follows the source's systemMaterial and 0.42 alpha stop. Header footprint stays stable as in Nagi.

Validation: implementation d499952 and preview-scroll correction 7e26509. Latest regression 39899665012, Release 39899665963, simulator screenshots/video 39899665136 all successful. Inspected static light/dark/compact/account and native video frames showing button blur, hidden title, and restored title. First video at 39899076839 did not exercise scrolling because its bottom anchor was already visible; retained provenance and corrected preview anchor to top. Independent review found no blockers. No physical-device acceptance or merge.
