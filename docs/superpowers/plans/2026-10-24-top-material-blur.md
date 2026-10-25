# Top Material Blur Implementation Plan

> Execute inline using superpowers:executing-plans; scope and implementation direction are supplied by the user.

**Goal:** Replace only CCSUT's shared top-bar background with masked system material, retaining the old background as a selectable fallback.
**Architecture:** A tested fade profile feeds a UIKit effect-view subclass; a background-only host handles geometry. NagiTopBar selects custom or unchanged legacy chrome.
**Tech Stack:** SwiftUI, UIKit, Core Animation, iOS 26.
**Spec:** ../specs/2026-10-24-top-material-blur-design.md

## Global Constraints
- Preserve all page layout, interactions, header metrics and animations.
- No private APIs, new dependencies or settings controls.
- Keep legacy native safeAreaBar path and existing .soft modifiers available.

## Review Focus
- Safe-area changes and rotation must resize both effect and mask.
- Top hold must be a real plateau; bottom alpha must equal zero.
- The effect must neither intercept touches nor enter the accessibility tree.
- New and fallback modes must have equal header/content frames.
- Do not combine the custom effect with the native top scroll-edge effect.

## Task 1: Shared masked material background
- [x] Add behavior tests for plateau/progress/endpoints before implementation.
- [x] Implement TopBarFadeProfile in ios/CCSUT/TopBarBlurProfile.swift; test locally with the Swift runner, and test actual UnitCurve opacity on macOS.
- [x] Add ios/CCSUT/TopBarMaterialBackground.swift with a layout-aware effect subclass and UIView/CAGradientLayer mask; register both sources in the Xcode project.
- [x] Integrate only in NagiTopBar; preserve its original chain in the legacy branch.
- [x] Compare new/fallback visible control and content frames in the existing native UI suite; capture both modes.
- [x] Run local regressions and native CI from the exact implementation commit, inspect screenshots, and report evidence limits.

## Execution decisions
- Use the attached isolated worktree from ui/navigation-timetable; do not modify unrelated untracked files in the original checkout.
- Defaults (32pt extension, 35% hold, ultra-thin system material) are implementation choices open to device visual tuning.

## Validation record
- Product-source commit: dbae00e750aa88973789937ae1f74c31442cf65e. Subsequent 2cb30a8 and b674d52 change only test/export infrastructure.
- Local: 8 normalization checks, 8 timetable checks, 1 release-preview guard and 6 login-script tests passed. macOS additionally passed actual UnitCurve opacity plateau, zero endpoint and monotonicity checks.
- Native session regressions: 40058429771 passed. Release build/package: 40058441332 passed; IPA ZIP, Mach-O executable and bundle/iOS metadata verified.
- IPA SHA-256: 1f3744d2246b662930f8bd60c2cbe00f2581b015172610426ef462801c129080.
- Native UI run 40058438323: week-positioning passed (1/1); interaction suite 8/11 passed, including five-page legacy/material layout parity and actual top-control taps. Screenshot body pixel difference below y=550px is zero for all five parity pages (1206x2622 screenshots).
- Retain original UI failures: testAcademicHomeWithoutReminderHasStableSpacedEntries (128pt expectation vs unchanged 96pt layout), testAcademicPagesPullToRefreshIncludingEmptyStates, testPullingTimetableRefreshesWholePageOnce (refresh counters stay zero).
- Screenshot export failed because Bash 3.2 treats an empty array expansion as unbound with nounset. Replaced that expansion with explicit mode branches in 2cb30a8. Run 40059993959 successfully rendered light/dark, hidden-header and compact-phone previews; inspected them visually. Hidden-header screenshot body pixels below y=550 are identical in both light and dark new/legacy pairs.
- The attempted legacy test control in 40059993959 was invalid: its trace reported material mode because scheme environment expansion did not reach the test runner. Preserve it as an invalid experiment, not evidence of baseline reproduction. b674d52 removes the scheme override and forces only the test launcher with CCSUT_TEST_LEGACY_TOP_BLUR.
- Verified legacy control 40061476948 at b674d52152fe9e85cb09f8b24a7def4e4ed20d1f: each launch explicitly logged TOP_BLUR_TEST_MODE legacy. All three same assertions failed again (96pt versus 128pt; scores refresh counter; timetable refresh counter), 3/3 failures. These failures also occur with the unchanged native chrome, so this change does not establish a green full UI gate. Do not modify those layouts/interactions or weaken their assertions as part of this blur task. The root cause of the refresh failures remains outside this scope.
- Independent reviewer found no actionable implementation defects. Physical-device appearance, rotation, largest Dynamic Type and reduced-transparency behavior remain unaccepted.
