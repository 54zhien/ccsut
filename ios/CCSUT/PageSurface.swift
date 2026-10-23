import SwiftUI
import UIKit
import Observation

enum AppMessages {
    static let loadFailure = "加载失败，请重试"

    static func readable(_ message: String) -> String {
        message.range(of: "[A-Za-z]", options: .regularExpression) == nil ? message : loadFailure
    }
}

struct GlassSheetSurface: ViewModifier {
    @Environment(\.deviceCornerRadius) private var cornerRadius

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: max(cornerRadius, 28)))
            }
            .presentationBackground(.clear)
    }
}

struct SheetHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭\(title)")
        }
        .overlay {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 52)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

private struct DeviceCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var deviceCornerRadius: CGFloat {
        get { self[DeviceCornerRadiusKey.self] }
        set { self[DeviceCornerRadiusKey.self] = newValue }
    }
}

extension View {
    func trackVerticalPageOffset(_ offset: Binding<CGFloat>) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
        } action: { _, value in offset.wrappedValue = value }
    }
}

/// Resolve the device/container curvature using public iOS 26 geometry.
/// This view fills the window, so inset cards and sheets can share its radius.
struct ScreenCornerReader: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> CornerView { CornerView(onChange: onChange) }
    func updateUIView(_ view: CornerView, context: Context) { view.onChange = onChange }

    final class CornerView: UIView {
        var onChange: (CGFloat) -> Void
        private var lastRadius: CGFloat?

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            cornerConfiguration = .corners(radius: .containerConcentric())
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard window != nil, bounds.width > 0 else { return }
            let radius = max(effectiveRadius(corner: .topLeft), effectiveRadius(corner: .bottomLeft),
                             effectiveRadius(corner: .topRight), effectiveRadius(corner: .bottomRight))
            guard lastRadius != radius else { return }
            lastRadius = radius
            DispatchQueue.main.async { [weak self] in self?.onChange(radius) }
        }
    }
}

/// Empty/loading/error states must still have a scroll surface to pull down.
/// Loaded pages already own their ScrollView and keep it without nesting.
struct RefreshablePlaceholder: ViewModifier {
    let needed: Bool

    func body(content: Content) -> some View {
        if needed {
            GeometryReader { viewport in
                ScrollView {
                    content.frame(maxWidth: .infinity, minHeight: viewport.size.height)
                }
                .scrollBounceBehavior(.always, axes: .vertical)
            }
        } else {
            content
        }
    }
}

/// Only publish a change when a header pins or its successor is within 8 points.
/// Keep per-frame geometry outside observation so scrolling does not redraw the list.
@MainActor @Observable
final class AcademicTermHeaderTracker {
    private(set) var floatingTerms: Set<String> = []
    @ObservationIgnored private var frames: [String: CGRect] = [:]
    @ObservationIgnored private var viewport: CGRect = .zero
    @ObservationIgnored private var topInset: CGFloat = 0

    func setViewport(_ frame: CGRect) {
        viewport = frame
        updateFloatingTerms()
    }

    func setTopInset(_ inset: CGFloat) {
        topInset = inset
        updateFloatingTerms()
    }

    func setFrame(_ frame: CGRect, for term: String) {
        frames[term] = frame
        updateFloatingTerms()
    }

    func remove(_ term: String) {
        frames.removeValue(forKey: term)
        updateFloatingTerms()
    }

    private func updateFloatingTerms() {
        guard viewport.height > 0 else { return }
        // The visible surface is inset 6 points inside each pinned header.
        let pinY = viewport.minY + topInset + 6
        let visible = frames.filter { $0.value.maxY > pinY && $0.value.minY < viewport.maxY }
            .sorted { $0.value.minY < $1.value.minY }
        var next: Set<String> = []
        for (index, header) in visible.enumerated() {
            if header.value.minY <= pinY + 1 {
                next.insert(header.key)
            } else if index > 0 {
                let previous = visible[index - 1].value
                let gap = header.value.minY - previous.maxY
                if previous.minY <= pinY + 1, gap >= -1, gap <= 8 {
                    next.insert(header.key)
                }
            }
        }
        if next != floatingTerms { floatingTerms = next }
    }
}

extension View {
    func trackAcademicTermHeaders(_ tracker: AcademicTermHeaderTracker) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            tracker.setViewport($0)
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, inset in
            tracker.setTopInset(inset)
        }
    }
}

/// Both academic lists share the same inset and surface when a section pins.
struct AcademicTermStrip<Content: View>: View {
    let term: String
    let tracker: AcademicTermHeaderTracker
    @ViewBuilder var content: () -> Content

    private var isFloating: Bool { tracker.floatingTerms.contains(term) }

    var body: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isFloating {
                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 18))
                        .transition(.opacity)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isFloating)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                tracker.setFrame($0, for: term)
            }
            .onDisappear { tracker.remove(term) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("term-header-\(term)")
            .accessibilityValue(isFloating ? "floating" : "inline")
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }
}

struct NagiBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("返回教务")
    }
}
