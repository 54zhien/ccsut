import Foundation

@main
struct TopBarBlurTests {
    static func main() {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        let profile = TopBarFadeProfile(holdFraction: 0.35)
        check(profile.fadeProgress(at: 0) == 0, "top remains fully held")
        check(profile.fadeProgress(at: 0.2) == 0, "hold covers an actual interval")
        check(profile.fadeProgress(at: 0.35) == 0, "hold ends without a discontinuity")
        check(abs(profile.fadeProgress(at: 0.675) - 0.5) < 0.000001,
              "fade spans the entire remaining height")
        check(profile.fadeProgress(at: 1) == 1, "bottom reaches the end of the curve")
        check(profile.fadeProgress(at: -1) == 0 && profile.fadeProgress(at: 2) == 1,
              "positions outside the band clamp to endpoints")
        let noHold = TopBarFadeProfile(holdFraction: 0)
        check(noHold.fadeProgress(at: 0.5) == 0.5, "zero hold starts fading at the top")
        let fullHold = TopBarFadeProfile(holdFraction: 1)
        check(fullHold.fadeProgress(at: 0.5) == 0 && fullHold.fadeProgress(at: 1) == 1,
              "full hold still allows a transparent bottom")
        #if canImport(SwiftUI)
        check(profile.opacity(at: 0.2) == 1, "actual easeIn mask preserves the opaque plateau")
        check(profile.opacity(at: 1) == 0, "actual easeIn mask has no bottom residue")
        let samples = (0...128).map { profile.opacity(at: Double($0) / 128) }
        check(zip(samples, samples.dropFirst()).allSatisfy { $0 >= $1 },
              "actual easeIn opacity decreases monotonically")
        #else
        print("NOTE UnitCurve opacity checks require SwiftUI on macOS/iOS")
        #endif
        exit(failures == 0 ? 0 : 1)
    }
}
