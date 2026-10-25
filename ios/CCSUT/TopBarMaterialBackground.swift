import SwiftUI
import UIKit

enum TopBarBlur {
    /// The native safeAreaBar / soft scroll-edge implementation remains intact.
    /// No preference screen or change to page interaction is needed to revert.
    #if CCSUT_LEGACY_TOP_BLUR
    static let usesLegacy = true
    #else
    static let usesLegacy = ProcessInfo.processInfo.arguments.contains("--legacy-top-blur")
    #endif
}

struct TopBarMaterialBackground: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    var additionalLength: CGFloat = 32
    var topHold: Double = 0.35
    var horizontalInset: CGFloat = 0

    func makeUIView(context: Context) -> TopBarMaterialHost {
        let view = TopBarMaterialHost()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: TopBarMaterialHost, context: Context) {
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        view.configure(style: colorScheme == .dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight,
                       additionalLength: additionalLength,
                       topHold: topHold, horizontalInset: horizontalInset)
    }
}

/// The representable keeps precisely the bar's proposed size. Only its effect
/// subview extends beyond those bounds, so the page's safe-area reservation and
/// every control's frame stay unchanged.
final class TopBarMaterialHost: UIView {
    private let blur = TopBarMaterialView()
    private var additionalLength: CGFloat = 32
    private var horizontalInset: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = false
        addSubview(blur)
    }

    required init?(coder: NSCoder) { nil }

    func configure(style: UIBlurEffect.Style, additionalLength: CGFloat,
                   topHold: Double, horizontalInset: CGFloat) {
        self.additionalLength = max(additionalLength, 0)
        self.horizontalInset = max(horizontalInset, 0)
        blur.configure(style: style, topHold: topHold)
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A bar inside the safe area has zero local top inset. Use its own
        // window, never a global screen/key-window lookup, to cover the status
        // area without extending above the window during rotation/transitions.
        let topCoverage: CGFloat
        if let window {
            topCoverage = max(0, min(convert(bounds, to: window).minY, window.safeAreaInsets.top))
        } else {
            topCoverage = safeAreaInsets.top
        }
        let inset = min(horizontalInset, bounds.width / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blur.frame = CGRect(x: inset, y: -topCoverage,
                            width: max(bounds.width - inset * 2, 0),
                            height: bounds.height + topCoverage + additionalLength)
        blur.layoutIfNeeded()
        CATransaction.commit()
    }
}

/// A single system material with an opacity mask. Keep alpha at 1; fade the
/// mask instead of compositing a partially transparent visual-effect view.
final class TopBarMaterialView: UIVisualEffectView {
    private let gradientMask = TopBarGradientMask()
    private var currentStyle: UIBlurEffect.Style = .systemUltraThinMaterial
    private var profile = TopBarFadeProfile()
    private var maskNeedsUpdate = true
    private var maskBounds: CGRect = .null

    init() {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func configure(style: UIBlurEffect.Style, topHold: Double) {
        if currentStyle != style {
            currentStyle = style
            effect = UIBlurEffect(style: style)
            maskNeedsUpdate = true
        }
        let updated = TopBarFadeProfile(holdFraction: topHold)
        if profile.holdFraction != updated.holdFraction {
            profile = updated
            maskNeedsUpdate = true
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty, maskNeedsUpdate || maskBounds != bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientMask.frame = bounds
        let gradient = gradientMask.layer as! CAGradientLayer
        // Include the hold boundary explicitly; sample only the fading segment.
        let positions = [0.0] + (0...32).map {
            profile.holdFraction + (1 - profile.holdFraction) * Double($0) / 32
        }
        gradient.colors = positions.map {
            UIColor.black.withAlphaComponent(CGFloat(profile.opacity(at: $0))).cgColor
        }
        gradient.locations = positions.map { NSNumber(value: $0) }
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // UIKit copies an effect view's UIView mask internally. Reassign after
        // geometry/profile changes so those copies receive the new dimensions.
        mask = gradientMask
        maskBounds = bounds
        maskNeedsUpdate = false
        CATransaction.commit()
    }
}

private final class TopBarGradientMask: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
}
