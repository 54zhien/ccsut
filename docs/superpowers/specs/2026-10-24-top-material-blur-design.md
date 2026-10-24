# Top material blur

Implement the user's selected system-material + vertical easeIn mask approach. Only the shared top-bar background changes; keep safeAreaBar, all header metrics, scroll offsets, title/button animations, navigation, refresh and business code intact.

Use one UIVisualEffectView subclass with a UIView mask backed by CAGradientLayer. Evaluate UnitCurve.easeIn directly, hold the first 35% opaque and reach zero at the bottom. Size the background from the actual bar bounds plus the top safe area and a 32pt extension. Insets, style and mask updates must take effect after layout changes. This is fading system material, not a claim of per-pixel variable-radius blur.

Approaches: the existing system scroll-edge effect remains the fallback; the user chose a custom masked material rather than continuing to tune that effect. Avoid stacking the two effects. Keep the original modifier chain verbatim in the fallback branch. Select it with --legacy-top-blur or CCSUT_LEGACY_TOP_BLUR, without adding product UI.

Validate mask normalization/endpoints, native compilation, existing interaction regressions and new/fallback layout parity. Inspect actual light/dark screenshots. Simulator evidence does not establish physical-device appearance or equivalence to the analyzed application.
