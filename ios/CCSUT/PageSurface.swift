import SwiftUI
import UIKit
import Observation

enum AppMessages {
    static let loadFailure = "加载失败，请重试"

    static func readable(_ message: String) -> String {
        message.range(of: "[A-Za-z]", options: .regularExpression) == nil ? message : loadFailure
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
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
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

/// Keep the active native pinned header glass, then hand off at close range.
/// Keep per-frame geometry outside observation so scrolling does not redraw the list.
@MainActor @Observable
final class AcademicTermHeaderTracker {
    private(set) var floatingTerms: Set<String> = []
    @ObservationIgnored private var frames: [String: CGRect] = [:]

    func setFrame(_ frame: CGRect, for term: String) {
        frames[term] = frame
        updateFloatingTerms()
    }

    func remove(_ term: String) {
        frames.removeValue(forKey: term)
        updateFloatingTerms()
    }

    private func updateFloatingTerms() {
        let ordered = frames.sorted {
            $0.value.minY == $1.value.minY ? $0.key > $1.key : $0.value.minY < $1.value.minY
        }
        var next: Set<String> = []
        // Pinned headers can report their scrolled layout frame. Do not reject
        // the active header because maxY is above zero or use that bottom as
        // the on-screen pin position. Match the original scroll coordinate.
        if let index = ordered.lastIndex(where: { $0.value.minY <= 0.5 }) {
            let active = ordered[index]
            next.insert(active.key)
            let successor = index + 1
            if ordered.indices.contains(successor),
               ordered[successor].value.minY <= active.value.height + 2 {
                next.insert(ordered[successor].key)
            }
        }
        if next != floatingTerms { floatingTerms = next }
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("term-header-\(term)")
            .accessibilityValue(isFloating ? "floating" : "inline")
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("academic-scroll")) } action: {
                tracker.setFrame($0, for: term)
            }
            .onDisappear { tracker.remove(term) }
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
