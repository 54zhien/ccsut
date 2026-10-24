#if canImport(SwiftUI)
import SwiftUI
#endif

/// Normalizes the fade after an opaque plateau. This controls mask opacity,
/// not the system material's blur radius.
struct TopBarFadeProfile {
    let holdFraction: Double

    init(holdFraction: Double = 0.35) {
        self.holdFraction = holdFraction.isFinite ? min(max(holdFraction, 0), 0.999999) : 0.35
    }

    func fadeProgress(at position: Double) -> Double {
        min(max((position - holdFraction) / (1 - holdFraction), 0), 1)
    }

    #if canImport(SwiftUI)
    func opacity(at position: Double) -> Double {
        1 - UnitCurve.easeIn.value(at: fadeProgress(at: position))
    }
    #endif
}
