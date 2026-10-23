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
    @State private var callbackEntryCount = 0
    @State private var lastCallbackCancelled = false
    @State private var scrollDiagnostic = "scrollProbe=waiting"

    private var refreshDiagnostic: String {
        "implementation=SwiftUI.refreshable; callbackEntered=\(callbackEntryCount); callbackCompleted=\(refreshCount); callbackCancelled=\(lastCallbackCancelled); callbackCount=\(refreshCount); \(scrollDiagnostic)"
    }

    private var diagnosticsEnabled: Bool {
        InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-refresh")
    }
#endif

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable {
#if DEBUG
                callbackEntryCount += 1
                lastCallbackCancelled = Task.isCancelled
#endif
                await action()
#if DEBUG
                if Task.isCancelled {
                    lastCallbackCancelled = true
                    return
                }
                refreshCount += 1
#endif
            }
#if DEBUG
            .background {
                if diagnosticsEnabled {
                    PageRefreshRuntimeProbe { scrollDiagnostic = $0 }
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
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

#if DEBUG
/// Read-only preview instrumentation for the native refresh failure. It records
/// visible scroll-view pan geometry/control state without changing either.
@MainActor
private struct PageRefreshRuntimeProbe: UIViewRepresentable {
    let onDiagnostic: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDiagnostic: onDiagnostic) }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.onDiagnostic = onDiagnostic
        view.coordinator = context.coordinator
        context.coordinator.refreshTargets(from: view)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
        view.coordinator = nil
    }

    @MainActor
    final class AnchorView: UIView {
        weak var coordinator: Coordinator?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); coordinator?.refreshTargets(from: self) }
        override func didMoveToSuperview() { super.didMoveToSuperview(); coordinator?.refreshTargets(from: self) }
        override func layoutSubviews() { super.layoutSubviews(); coordinator?.refreshTargets(from: self) }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onDiagnostic: @MainActor (String) -> Void
        private weak var anchor: AnchorView?
        private var observed: [ObjectIdentifier: ObservedScrollView] = [:]
        private var orderedScrollViewIDs: [ObjectIdentifier] = []
        private var minimumOffsetY: [ObjectIdentifier: CGFloat] = [:]
        private var minimumAdjustedY: [ObjectIdentifier: CGFloat] = [:]
        private var minimumPullDepth: [ObjectIdentifier: CGFloat] = [:]
        private var panEventCount = 0
        private var lastPublishedDiagnostic: String?
        private var pendingDiagnostic: String?
        private var publishScheduled = false

        init(onDiagnostic: @escaping @MainActor (String) -> Void) {
            self.onDiagnostic = onDiagnostic
        }

        func refreshTargets(from anchor: AnchorView) {
            self.anchor = anchor
            guard let window = anchor.window else {
                publish("event=attach; window=missing; panEvents=\(panEventCount)")
                return
            }

            var scrollViews: [UIScrollView] = []
            collectScrollViews(in: window, into: &scrollViews)
            let visible = scrollViews.filter { scrollView in
                let frame = scrollView.convert(scrollView.bounds, to: window)
                return !scrollView.isHidden && scrollView.alpha > 0.01
                    && frame.width >= window.bounds.width * 0.75
                    && frame.height >= window.bounds.height * 0.4
            }
            orderedScrollViewIDs = visible.map { ObjectIdentifier($0) }
            let identities = Set(orderedScrollViewIDs)
            for identity in Array(observed.keys) where !identities.contains(identity) || observed[identity]?.scrollView == nil {
                if let item = observed.removeValue(forKey: identity) {
                    item.pan?.removeTarget(self, action: #selector(trackPan(_:)))
                }
                minimumOffsetY.removeValue(forKey: identity)
                minimumAdjustedY.removeValue(forKey: identity)
                minimumPullDepth.removeValue(forKey: identity)
            }
            for scrollView in visible {
                let identity = ObjectIdentifier(scrollView)
                if observed[identity]?.pan !== scrollView.panGestureRecognizer {
                    observed[identity]?.pan?.removeTarget(self, action: #selector(trackPan(_:)))
                    scrollView.panGestureRecognizer.addTarget(self, action: #selector(trackPan(_:)))
                    observed[identity] = ObservedScrollView(scrollView, pan: scrollView.panGestureRecognizer)
                }
            }

            let frames = visible.enumerated().map { index, scrollView in
                describe(scrollView, index: index, in: window)
            }
            publish("event=attach; window=\(Int(window.bounds.width))x\(Int(window.bounds.height)); panEvents=\(panEventCount); scrolls=[\(frames.joined(separator: " | "))]")
        }

        @objc private func trackPan(_ recognizer: UIPanGestureRecognizer) {
            guard let item = observed.values.first(where: { $0.pan === recognizer }),
                  let scrollView = item.scrollView else { return }
            let identity = ObjectIdentifier(scrollView)
            sampleMinimum(for: scrollView, identity: identity)
            switch recognizer.state {
            case .began:
                panEventCount += 1
                publishSnapshot(event: "pan-began", source: scrollView)
            case .ended, .cancelled, .failed:
                publishSnapshot(event: "pan-\(String(describing: recognizer.state))", source: scrollView)
            default:
                break
            }
        }

        private func sampleMinimum(for scrollView: UIScrollView, identity: ObjectIdentifier) {
            let offsetY = scrollView.contentOffset.y
            let adjustedY = offsetY + scrollView.adjustedContentInset.top
            minimumOffsetY[identity] = min(minimumOffsetY[identity] ?? offsetY, offsetY)
            minimumAdjustedY[identity] = min(minimumAdjustedY[identity] ?? adjustedY, adjustedY)
            minimumPullDepth[identity] = max(minimumPullDepth[identity] ?? 0, -adjustedY)
        }

        private func publishSnapshot(event: String, source: UIScrollView) {
            guard let window = anchor?.window else { return }
            let sourceID = ObjectIdentifier(source)
            let sourceIndex = orderedScrollViewIDs.firstIndex(of: sourceID) ?? -1
            var targets = orderedScrollViewIDs.compactMap { observed[$0]?.scrollView }
            if !targets.contains(where: { $0 === source }) { targets.append(source) }
            let details = targets.enumerated().map { index, scrollView in
                describe(scrollView, index: index, in: window)
            }
            publish("event=\(event); source=\(sourceIndex); panEvents=\(panEventCount); scrolls=[\(details.joined(separator: " | "))]")
        }

        private func describe(_ scrollView: UIScrollView, index: Int, in window: UIWindow) -> String {
            let identity = ObjectIdentifier(scrollView)
            let frame = scrollView.convert(scrollView.bounds, to: window)
            let control = scrollView.refreshControl
            let minOffset = minimumOffsetY[identity].map { String(format: "%.0f", Double($0)) } ?? "—"
            let minAdjusted = minimumAdjustedY[identity].map { String(format: "%.0f", Double($0)) } ?? "—"
            let minPull = minimumPullDepth[identity].map { String(format: "%.0f", Double($0)) } ?? "—"
            return "#\(index):\(NSStringFromClass(type(of: scrollView))) frame=\(Int(frame.width))x\(Int(frame.height))@\(Int(frame.minX)),\(Int(frame.minY)) contentH=\(Int(scrollView.contentSize.height)) offsetY=\(Int(scrollView.contentOffset.y)) adjustedTop=\(Int(scrollView.adjustedContentInset.top)) minOffsetY=\(minOffset) minAdjustedY=\(minAdjusted) minPull=\(minPull) alwaysBounce=\(scrollView.alwaysBounceVertical) refreshControl=\(control.map { NSStringFromClass(type(of: $0)) } ?? "nil") refreshing=\(control?.isRefreshing ?? false) pan=\(String(describing: scrollView.panGestureRecognizer.state))"
        }

        private func collectScrollViews(in view: UIView, into result: inout [UIScrollView]) {
            if let scrollView = view as? UIScrollView { result.append(scrollView) }
            for child in view.subviews { collectScrollViews(in: child, into: &result) }
        }

        private func publish(_ message: String) {
            guard message != pendingDiagnostic, message != lastPublishedDiagnostic else { return }
            pendingDiagnostic = message
            guard !publishScheduled else { return }
            publishScheduled = true

            // UIViewRepresentable lifecycle/layout callbacks can run during a
            // SwiftUI update. Publish the observed state on the next main-actor
            // turn so updating the diagnostic @State cannot mutate the view
            // hierarchy synchronously from that update.
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                self.publishScheduled = false
                guard let diagnostic = self.pendingDiagnostic else { return }
                self.pendingDiagnostic = nil
                guard diagnostic != self.lastPublishedDiagnostic else { return }
                self.lastPublishedDiagnostic = diagnostic
                self.onDiagnostic(diagnostic)
            }
        }

        func detach() {
            for item in observed.values { item.pan?.removeTarget(self, action: #selector(trackPan(_:))) }
            observed.removeAll()
            orderedScrollViewIDs.removeAll()
            minimumOffsetY.removeAll()
            minimumAdjustedY.removeAll()
            minimumPullDepth.removeAll()
            anchor = nil
        }
    }

    @MainActor
    private final class ObservedScrollView {
        weak var scrollView: UIScrollView?
        weak var pan: UIPanGestureRecognizer?

        init(_ scrollView: UIScrollView, pan: UIPanGestureRecognizer) {
            self.scrollView = scrollView
            self.pan = pan
        }
    }
}
#endif

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
