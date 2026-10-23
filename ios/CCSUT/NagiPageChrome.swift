// Adapted from Nagi 9f5cd1a: LibraryView page header and SearchView masked material.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum NagiPageHeaderMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 8
    static let controlSize: CGFloat = 48
    static let controlIconSize: CGFloat = 20
    static let hideThreshold: CGFloat = 8
    static let revealTolerance: CGFloat = 0.5
    static let transitionDuration: Double = 0.25
    static let buttonBlurRadius: CGFloat = 8

    static var contentHeight: CGFloat {
        controlSize + verticalPadding * 2
    }
}

/// 页面级大标题，保持标题和右侧操作控件的视觉与动效一致。
struct NagiPageHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleFontSize: CGFloat = 38

    let title: String
    let transitionProgress: CGFloat
    let isHeaderHidden: Bool
    let actionIcon: String?
    let actionAccessibilityLabel: String?
    let action: (() -> Void)?
    let secondaryAction: AnyView?
    let leadingAction: AnyView?

    init(
        title: String,
        transitionProgress: CGFloat = 0,
        isHeaderHidden: Bool = false,
        actionIcon: String? = nil,
        actionAccessibilityLabel: String? = nil,
        action: (() -> Void)? = nil,
        secondaryAction: AnyView? = nil,
        leadingAction: AnyView? = nil
    ) {
        self.title = title
        self.transitionProgress = transitionProgress
        self.isHeaderHidden = isHeaderHidden
        self.actionIcon = actionIcon
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.action = action
        self.secondaryAction = secondaryAction
        self.leadingAction = leadingAction
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let leadingAction { leadingAction }
            Text(title)
                .font(.system(size: titleFontSize, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(minHeight: NagiPageHeaderMetrics.controlSize, alignment: .leading)
                .opacity(titleOpacity)
                .accessibilityHidden(isHeaderHidden)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            if secondaryAction != nil || (action != nil && actionIcon != nil) {
                HStack(spacing: 8) {
                    if let secondaryAction {
                        secondaryAction
                            .blur(radius: buttonBlurRadius)
                            .opacity(buttonOpacity)
                            .allowsHitTesting(!isHeaderHidden)
                            .accessibilityHidden(isHeaderHidden)
                    }

                    if let action, let actionIcon {
                        Button(action: action) {
                            Image(systemName: actionIcon)
                                .font(.system(size: NagiPageHeaderMetrics.controlIconSize, weight: .medium))
                                .frame(
                                    width: NagiPageHeaderMetrics.controlSize,
                                    height: NagiPageHeaderMetrics.controlSize
                                )
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .blur(radius: buttonBlurRadius)
                        .opacity(buttonOpacity)
                        .allowsHitTesting(!isHeaderHidden)
                        .accessibilityHidden(isHeaderHidden)
                        .accessibilityLabel(actionAccessibilityLabel ?? actionIcon)
                    }
                }
            }
        }
        .padding(.horizontal, NagiPageHeaderMetrics.horizontalPadding)
        .padding(.vertical, NagiPageHeaderMetrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var normalizedProgress: CGFloat {
        min(max(transitionProgress, 0), 1)
    }

    private var titleOpacity: Double {
        Double(1 - normalizedProgress)
    }

    private var buttonTransitionProgress: CGFloat {
        min(max((normalizedProgress - 0.5) * 2, 0), 1)
    }

    private var buttonBlurRadius: CGFloat {
        guard !reduceMotion else { return 0 }
        return buttonTransitionProgress * NagiPageHeaderMetrics.buttonBlurRadius
    }

    private var buttonOpacity: Double {
        Double(1 - buttonTransitionProgress)
    }
}

private struct NagiHeaderGaussianBlur: UIViewRepresentable {
    let statusBarFraction: CGFloat

    func makeUIView(context: Context) -> NagiGradientMaskedBlurView {
        NagiGradientMaskedBlurView()
    }

    func updateUIView(_ uiView: NagiGradientMaskedBlurView, context: Context) {
        uiView.statusBarFraction = statusBarFraction
    }
}

private final class NagiGradientMaskedBlurView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let gradientMask = CAGradientLayer()

    var statusBarFraction: CGFloat = 0.35 {
        didSet {
            updateGradient()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(blurView)
        blurView.layer.mask = gradientMask
        updateGradient()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        gradientMask.frame = blurView.bounds
    }

    private func updateGradient() {
        let statusEnd = min(max(statusBarFraction, 0), 0.72)
        gradientMask.colors = [
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor.black.withAlphaComponent(0.42).cgColor,
            UIColor.clear.cgColor
        ]
        gradientMask.locations = [
            0,
            NSNumber(value: Double(statusEnd)),
            NSNumber(value: Double(statusEnd + (1 - statusEnd) * 0.58)),
            1
        ]
        gradientMask.startPoint = CGPoint(x: 0.5, y: 0)
        gradientMask.endPoint = CGPoint(x: 0.5, y: 1)
    }
}


private struct NagiPageChrome<Actions: View>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHeaderHidden = false
    @State private var transitionProgress: CGFloat = 0
    let title: String
    let scrollOffset: CGFloat
    let showsBackButton: Bool
    @ViewBuilder let actions: () -> Actions

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .toolbar(.hidden, for: .navigationBar)
                .scrollEdgeEffectHidden(true, for: .top)
                .safeAreaInset(edge: .top, spacing: 0) {
                    let height = geometry.safeAreaInsets.top + NagiPageHeaderMetrics.contentHeight + 12
                    NagiPageHeader(
                        title: title,
                        transitionProgress: transitionProgress,
                        isHeaderHidden: isHeaderHidden,
                        secondaryAction: AnyView(actions()),
                        leadingAction: showsBackButton ? AnyView(NagiBackButton()) : nil
                    )
                    .background(alignment: .top) {
                        NagiHeaderGaussianBlur(statusBarFraction: height > 0 ? geometry.safeAreaInsets.top / height : 0)
                            .frame(height: height)
                            .offset(y: -geometry.safeAreaInsets.top)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .onChange(of: scrollOffset) { _, offset in
            updateVisibility(offset)
        }
        .onAppear { updateVisibility(scrollOffset) }
    }

    private func updateVisibility(_ offset: CGFloat) {
        let shouldHide = max(offset, 0) > (isHeaderHidden ? NagiPageHeaderMetrics.revealTolerance : NagiPageHeaderMetrics.hideThreshold)
        guard shouldHide != isHeaderHidden else { return }
        isHeaderHidden = shouldHide
        if reduceMotion {
            transitionProgress = shouldHide ? 1 : 0
        } else {
            withAnimation(.easeInOut(duration: NagiPageHeaderMetrics.transitionDuration)) {
                transitionProgress = shouldHide ? 1 : 0
            }
        }
    }
}

extension View {
    func nagiPageChrome<Actions: View>(title: String, scrollOffset: CGFloat, showsBackButton: Bool = false, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(NagiPageChrome(title: title, scrollOffset: scrollOffset, showsBackButton: showsBackButton, actions: actions))
    }
}
