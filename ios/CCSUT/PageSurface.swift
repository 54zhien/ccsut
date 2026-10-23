import SwiftUI
import UIKit
import Observation

enum AppMessages {
    static let loadFailure = "加载失败，请重试"

    static func readable(_ message: String) -> String {
        message.range(of: "[A-Za-z]", options: .regularExpression) == nil ? message : loadFailure
    }
}

/// Appears only when existing content could not be refreshed.
struct PageStatusNotice: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let retry { Button("重试", action: retry).buttonStyle(.plain).foregroundStyle(.tint) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

enum SheetLayout {
    static func cornerRadius(_ deviceRadius: CGFloat) -> CGFloat {
        deviceRadius > 0 ? deviceRadius : 32
    }

    // The circle and the sheet corner share a center: inset + diameter / 2 = radius.
    static func controlInset(_ deviceRadius: CGFloat, diameter: CGFloat) -> CGFloat {
        guard diameter > 0 else { return 20 }
        return max(0, cornerRadius(deviceRadius) - diameter / 2)
    }
}

struct SheetSymbolButton: View {
    let symbol: String
    let label: String
    var symbolSize: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let symbolSize {
                // Image bounds, rather than a text baseline, define the center.
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: symbolSize, height: symbolSize, alignment: .center)
            } else {
                Label(label, systemImage: symbol)
            }
        }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .fixedSize()
            .foregroundStyle(.primary)
            .tint(nil)
            .accessibilityLabel(label)
    }
}

struct SheetHeader: View {
    @Environment(\.deviceCornerRadius) private var deviceCornerRadius
    @State private var controlDiameter: CGFloat = 0
    let title: String
    let close: () -> Void

    var body: some View {
        HStack {
            Spacer()
            SheetSymbolButton(symbol: "xmark", label: "关闭\(title)", action: close)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlDiameter = $0 }
        .overlay {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, controlDiameter + 8)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, SheetLayout.controlInset(deviceCornerRadius, diameter: controlDiameter))
        .padding(.top, SheetLayout.controlInset(deviceCornerRadius, diameter: controlDiameter))
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

/// Join an in-flight initial load instead of ending a pull refresh immediately.
@MainActor
final class PageLoadGate {
    private var pending: Task<Void, Never>?

    func run(_ action: @escaping @MainActor () async -> Void) async {
        if let pending { await pending.value; return }
        let task = Task { @MainActor in await action() }
        pending = task
        await task.value
        pending = nil
    }
}

extension View {
    /// Apply directly to the page's vertical ScrollView. SwiftUI owns the
    /// refresh lifecycle, including empty/loading content and return animation.
    func pageRefreshable(showsRefreshCount: Bool = false, action: @escaping @MainActor () async -> Void) -> some View {
        modifier(PageRefreshable(showsRefreshCount: showsRefreshCount, action: action))
    }
}

private struct PageRefreshable: ViewModifier {
    let showsRefreshCount: Bool
    let action: @MainActor () async -> Void
#if DEBUG
    @State private var refreshCount = 0
    @State private var refreshDiagnostic = "implementation=SwiftUI.refreshable; callbackCount=0"

    private var diagnosticsEnabled: Bool {
        InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-refresh")
    }
#endif

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable {
                await action()
#if DEBUG
                guard !Task.isCancelled else { return }
                refreshCount += 1
                refreshDiagnostic = "implementation=SwiftUI.refreshable; callbackCount=\(refreshCount)"
#endif
            }
#if DEBUG
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 0) {
                    if showsRefreshCount && InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-refresh") {
                        Text("\(refreshCount)").font(.caption2)
                            .accessibilityIdentifier("academic-refresh-count")
                    }
                    if diagnosticsEnabled {
                        Text(refreshDiagnostic)
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .frame(width: 1, height: 1)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(refreshDiagnostic)
                            .accessibilityIdentifier("page-refresh-diagnostic")
                    }
                }
                .allowsHitTesting(false)
            }
#endif
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
               ordered[successor].value.minY <= active.value.height {
                next.insert(ordered[successor].key)
            }
        }
        if next != floatingTerms { floatingTerms = next }
    }
}

/// A compact semester menu; each page owns its ScrollViewReader and scrolling.
struct AcademicTermJumpMenu: View {
    let terms: [String]
    let onSelect: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Menu {
            ForEach(terms, id: \.self) { term in
                Button(SchedulePresentation.termTitle(term)) { onSelect(term) }
                    .accessibilityIdentifier("academic-term-jump-\(term)")
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                } else {
                    Label("学期", systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                }
            }
            .background(Color(.tertiarySystemGroupedBackground), in: .capsule)
            .contentShape(.capsule)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("跳转学期")
        .accessibilityHint("选择学期后滚动到对应内容")
        .accessibilityIdentifier("academic-term-jump-menu")
        .disabled(terms.count < 2)
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
                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 26))
                        .transition(.opacity)
                } else {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isFloating)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("term-header-\(term)")
            .accessibilityValue(isFloating ? "floating" : "inline")
            .padding(.horizontal, 16)
            // Two visual points between adjacent pinned surfaces at the handoff.
            .padding(.vertical, 1)
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
