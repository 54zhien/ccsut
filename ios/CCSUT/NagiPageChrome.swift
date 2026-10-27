// Ported from Nagi 9f5cd1a: LibraryView native safeAreaBar and page header.
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

private struct NagiPageChrome<Actions: View>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHeaderHidden = false
    @State private var transitionProgress: CGFloat = 0
    let title: String
    let scrollOffset: CGFloat
    let showsBackButton: Bool
    let actions: () -> Actions

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .nagiTopBar {
                NagiPageHeader(
                    title: title,
                    transitionProgress: transitionProgress,
                    isHeaderHidden: isHeaderHidden,
                    secondaryAction: AnyView(actions()),
                    leadingAction: showsBackButton ? AnyView(NagiBackButton()) : nil
                )
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

/// Inline chrome belongs to the child, so a cancelled pop cannot interpolate its
/// title/buttons independently of the moving page. UIKit still owns the gesture.
private struct AcademicDetailChrome<Actions: View>: ViewModifier {
    let title: String
    @ViewBuilder let actions: () -> Actions
    var backgroundColor: Color = Color(.systemGroupedBackground)
    #if DEBUG
    @State private var transitionDrift: CGFloat = 0
    @State private var transitionSamples = 0
    @State private var transitionDiagnostics = "waiting"
    #endif

    func body(content: Content) -> some View {
        content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scrollBounceBehavior(.always, axes: .vertical)
                .nagiTopBar {
                    HStack {
                        NagiBackButton()
                        Spacer(minLength: 12)
                        actions()
                    }
                    .overlay {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                            .accessibilityIdentifier("academic-detail-title")
                            .allowsHitTesting(false)
                            .background {
                                #if DEBUG
                                if InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-transition") {
                                    AcademicTitleMarker()
                                }
                                #endif
                            }
                    }
                    .frame(height: 48)
                    .padding(.horizontal, 16)
                    .padding(.vertical, NagiPageHeaderMetrics.verticalPadding)
                }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle(title)
            .background { AcademicPopSupport() }
            .background {
                #if DEBUG
                if InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-transition") {
                    AcademicTransitionProbe() { drift, samples, diagnostics in
                        transitionDrift = drift
                        transitionSamples = samples
                        transitionDiagnostics = diagnostics
                    }
                }
                #endif
            }
            .overlay(alignment: .bottomTrailing) {
                #if DEBUG
                if InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-transition") {
                    VStack {
                        Text(String(format: "%.3f", transitionDrift)).accessibilityIdentifier("transition-drift")
                        Text("\(transitionSamples)").accessibilityIdentifier("transition-samples")
                        Text(transitionDiagnostics).accessibilityIdentifier("transition-diagnostics")
                    }
                    .font(.caption2).allowsHitTesting(false)
                }
                #endif
            }
    }
}

extension View {
    /// Keep the native bar mounted; only its background implementation changes.
    /// The header's labels, controls and their animations remain independent.
    fileprivate func nagiTopBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        modifier(NagiTopBar(bar: content()))
    }

    func academicDetailChrome(title: String, backgroundColor: Color = Color(.systemGroupedBackground)) -> some View {
        modifier(AcademicDetailChrome(title: title, actions: { EmptyView() }, backgroundColor: backgroundColor))
    }

    func academicDetailChrome<Actions: View>(title: String, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(AcademicDetailChrome(title: title, actions: actions))
    }

    func nagiPageChrome<Actions: View>(title: String, scrollOffset: CGFloat, showsBackButton: Bool = false, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(NagiPageChrome(title: title, scrollOffset: scrollOffset, showsBackButton: showsBackButton, actions: actions))
    }
}

private struct NagiTopBar<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        if TopBarBlur.usesLegacy {
            // Original implementation: retain this chain verbatim for rollback.
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaBar(edge: .top, spacing: 0) {
                    bar
                }
        } else {
            content
                .toolbar(.hidden, for: .navigationBar)
                .scrollEdgeEffectHidden(true, for: .top)
                .safeAreaBar(edge: .top, spacing: 0) {
                    bar.background {
                        TopBarMaterialBackground()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
    }
}
