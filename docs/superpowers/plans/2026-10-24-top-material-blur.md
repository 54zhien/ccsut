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
- [ ] Add behavior tests for plateau/progress/endpoints before implementation.
- [ ] Implement TopBarFadeProfile in ios/CCSUT/TopBarBlurProfile.swift; test locally with the Swift runner, and test actual UnitCurve opacity on macOS.
- [ ] Add ios/CCSUT/TopBarMaterialBackground.swift with a layout-aware effect subclass and UIView/CAGradientLayer mask; register both sources in the Xcode project.
- [ ] Integrate only in NagiTopBar; preserve its original chain in the legacy branch.
- [ ] Compare new/fallback visible control and content frames in the existing native UI suite; capture both modes.
- [ ] Run local regressions and native CI from the exact implementation commit, inspect screenshots, and report evidence limits.

## Execution decisions
- Use the attached isolated worktree from ui/navigation-timetable; do not modify unrelated untracked files in the original checkout.
- Defaults (32pt extension, 35% hold, ultra-thin system material) are implementation choices open to device visual tuning.
