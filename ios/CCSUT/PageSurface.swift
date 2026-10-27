import SwiftUI
import UIKit
import Observation

/// Shared spacing and opaque content surfaces. Glass is reserved for controls.
enum AppLayout {
    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 28
    static let sectionSpacing: CGFloat = 28
}

struct AppSectionHeading: View {
    let title: String
    var detail: String? = nil

    init(_ title: String, detail: String? = nil) { self.title = title; self.detail = detail }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

struct AppServiceRow: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20).padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AppDetailHeading: View {
    let title: String
    let subtitle: String
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.title2).foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical).accessibilityHidden(true)
            }
            Text(title).font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PageLoadingState: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.regular).accessibilityHidden(true)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func appContentCard() -> some View {
        background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: AppLayout.cardRadius))
    }
}

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
            Image(systemName: symbol)
                .font(.system(size: symbolSize ?? 20, weight: .medium))
                .frame(width: 24, height: 24)
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

/// The timetable's page hierarchy: viewport -> reader -> vertical scroll view.
/// Keep refresh, scroll geometry and the scroll view in one stable owner; page
/// chrome and loading tasks belong outside this surface.
struct PageScrollSurface<Content: View>: View {
    var refresh: (@MainActor () async -> Void)? = nil
    var refreshHaptics = false
    var backgroundColor: Color = Color(.systemGroupedBackground)
    var onOffsetChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder var content: (CGSize, ScrollViewProxy) -> Content

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    content(viewport.size, proxy)
                        .background {
                            if let refresh {
                                NativePageRefreshAnchor(action: refresh, haptics: refreshHaptics)
                                .frame(width: 0, height: 0)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                        }
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollBounceBehavior(.always, axes: .vertical)
                #if DEBUG
                .modifier(PageRefreshDiagnostics())
                #endif
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
                } action: { _, value in
                    onOffsetChange(value)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .background(backgroundColor)
    }
}

extension View {
    /// Apply directly to the page's vertical ScrollView. SwiftUI owns the
    /// refresh lifecycle, including empty/loading content and return animation.
    func pageRefreshable(action: @escaping @MainActor () async -> Void) -> some View {
        modifier(PageRefreshable(action: action))
    }
}

private struct PageRefreshable: ViewModifier {
    let action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable {
                #if DEBUG
                await MainActor.run {
                    if RefreshFeedbackObservation.enabled { RefreshFeedbackObservation.shared.beginCallback() }
                }
                #endif
                await action()
                #if DEBUG
                let cancelled = Task.isCancelled
                await MainActor.run {
                    if RefreshFeedbackObservation.enabled { RefreshFeedbackObservation.shared.endCallback(cancelled: cancelled) }
                }
                #endif
            }
            #if DEBUG
            .modifier(PageRefreshDiagnostics())
            #endif
    }
}

#if DEBUG
private struct PageRefreshDiagnostics: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onDisappear {
                if RefreshFeedbackObservation.enabled && ProcessInfo.processInfo.arguments.contains("--preview-controlled-refresh") {
                    PreviewRefreshCompletionGate.shared.release()
                }
            }
            .background {
                if RefreshFeedbackObservation.enabled {
                    RefreshFeedbackNativeProbe().frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if RefreshFeedbackObservation.enabled {
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        let controlled = ProcessInfo.processInfo.arguments.contains("--preview-controlled-refresh")
                        Text(RefreshFeedbackObservation.shared.report)
                            .font(.system(size: controlled ? 9 : 1, design: .monospaced))
                            .foregroundStyle(controlled ? Color.primary : Color.clear)
                            .frame(width: controlled ? 280 : 1, height: controlled ? 180 : 1)
                            .background(controlled ? Color(.secondarySystemGroupedBackground) : Color.clear)
                            .padding(.bottom, controlled ? 130 : 0)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(RefreshFeedbackObservation.shared.report)
                            .accessibilityIdentifier("refresh-feedback-observation")
                            .allowsHitTesting(false)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if RefreshFeedbackObservation.enabled && ProcessInfo.processInfo.arguments.contains("--preview-controlled-refresh") {
                    Button("完成诊断刷新") { PreviewRefreshCompletionGate.shared.release() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("complete-controlled-refresh")
                        .padding(.trailing, 16).padding(.bottom, 90)
                }
            }
    }
}
#endif

/// Own the native control independently of SwiftUI's RefreshAction environment.
/// Installing it as a scroll-view subview preserves the system pull animation and
/// held inset when a pushed page updates its layout during an asynchronous read.
private struct NativePageRefreshAnchor: UIViewRepresentable {
    let action: @MainActor () async -> Void
    let haptics: Bool
    func makeCoordinator() -> Coordinator { Coordinator(action: action, haptics: haptics) }
    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.action = action
        context.coordinator.haptics = haptics
        view.connect()
    }
    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) { coordinator.detach() }

    @MainActor final class AnchorView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() { super.didMoveToWindow(); connect() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); connect() }
        override func layoutSubviews() { super.layoutSubviews(); connect() }
        func connect() {
            guard window != nil else { return }
            var parent = superview
            while let view = parent {
                if let scroll = view as? UIScrollView { coordinator?.attach(to: scroll); return }
                parent = view.superview
            }
        }
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () async -> Void
        var haptics: Bool
        private let control = UIRefreshControl()
        private weak var scroll: UIScrollView?
        private var task: Task<Void, Never>?
        private var revision: UInt64 = 0
        init(action: @escaping @MainActor () async -> Void, haptics: Bool) {
            self.action = action
            self.haptics = haptics
            super.init()
            control.addTarget(self, action: #selector(refresh), for: .valueChanged)
        }
        func attach(to scroll: UIScrollView) {
            guard self.scroll !== scroll else { return }
            detach()
            self.scroll = scroll
            scroll.alwaysBounceVertical = true
            scroll.addSubview(control)
        }
        @objc private func refresh() {
            guard task == nil else { return }
            if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            let expectedRevision = revision
            let action = action
            #if DEBUG
            if RefreshFeedbackObservation.enabled { RefreshFeedbackObservation.shared.beginCallback() }
            #endif
            task = Task { @MainActor [weak self] in
                await action()
                guard let self, revision == expectedRevision else { return }
                control.endRefreshing()
                task = nil
                #if DEBUG
                if RefreshFeedbackObservation.enabled { RefreshFeedbackObservation.shared.endCallback(cancelled: Task.isCancelled) }
                #endif
            }
        }
        func detach() {
            revision &+= 1
            task?.cancel()
            task = nil
            control.endRefreshing()
            control.removeFromSuperview()
            scroll = nil
        }
    }
}

#if DEBUG
/// Reference-only observations avoid publishing @State from the refresh callback.
/// The probe never installs/replaces a refresh control or changes any gesture delegate.
@MainActor private final class RefreshFeedbackObservation {
    static let shared = RefreshFeedbackObservation()
    static var enabled: Bool {
        InterfacePreview.enabled && (InterfacePreview.refreshObservation ||
            ProcessInfo.processInfo.arguments.contains("--preview-slow-refresh"))
    }
    private var entered = 0
    private var completed = 0
    private var cancelled = false
    private var activeSince: CFTimeInterval?
    private var refreshingSeen = false
    private var prematurelyStopped = false
    private var maximumPull: CGFloat = 0
    private var native = "native=unobserved"
    private var activeNative = "unobserved"

    func beginCallback() {
        entered += 1
        activeSince = CACurrentMediaTime()
        refreshingSeen = false
        prematurelyStopped = false
    }
    func endCallback(cancelled: Bool) {
        completed += 1
        self.cancelled = cancelled
        activeSince = nil
    }
    func observe(_ scroll: UIScrollView) {
        let control = scroll.refreshControl ?? scroll.subviews.compactMap { $0 as? UIRefreshControl }.first
        let pull = max(0, -(scroll.contentOffset.y + scroll.adjustedContentInset.top))
        maximumPull = max(maximumPull, pull)
        if let since = activeSince {
            if control?.isRefreshing == true { refreshingSeen = true }
            else if refreshingSeen && CACurrentMediaTime() - since > 0.1 { prematurelyStopped = true }
        }
        let frame = control.map { $0.convert($0.bounds, to: scroll.window) } ?? .zero
        let scrollFrame = scroll.convert(scroll.bounds, to: scroll.window)
        native = "control=\(control.map { NSStringFromClass(type(of: $0)) } ?? "nil"); refreshing=\(control?.isRefreshing ?? false); hidden=\(control?.isHidden ?? false); alpha=\(control?.alpha ?? 0); controlY=\(Int(frame.minY)); controlH=\(Int(frame.height)); maxPull=\(Int(maximumPull)); scrollY=\(Int(scrollFrame.minY)); offsetY=\(Int(scroll.contentOffset.y)); adjustedTop=\(Int(scroll.adjustedContentInset.top)); insetTop=\(Int(scroll.contentInset.top))"
        if activeSince != nil { activeNative = native }
    }
    var report: String {
        "entered=\(entered); completed=\(completed); cancelled=\(cancelled); active=\(activeSince != nil); refreshingSeen=\(refreshingSeen); prematurelyStopped=\(prematurelyStopped); \(native); activeNative=[\(activeNative)]"
    }
}

private struct RefreshFeedbackNativeProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {}
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.stop() }

    @MainActor final class ProbeView: UIView {
        private var timer: Timer?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            if window != nil {
                let timer = Timer(timeInterval: 0.025, target: self, selector: #selector(sample), userInfo: nil, repeats: true)
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        func stop() { timer?.invalidate(); timer = nil }
        @objc private func sample() {
            guard let window else { return }
            var candidates: [UIScrollView] = []
            func collect(_ view: UIView) {
                guard !view.isHidden, view.alpha > 0.01 else { return }
                if let scroll = view as? UIScrollView {
                    let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
                    if visible.width > window.bounds.width * 0.75, visible.height > window.bounds.height * 0.4 {
                        candidates.append(scroll)
                    }
                }
                for child in view.subviews { collect(child) }
            }
            collect(window)
            if let scroll = candidates.last { RefreshFeedbackObservation.shared.observe(scroll) }
        }
    }
}

/// Exposes fixture publication to UI tests without observing SwiftUI refresh-task cancellation.
struct PageRefreshPublicationDiagnostics: View {
    let count: Int

    var body: some View {
        Group {
            if InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-refresh") {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(count)")
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(count)")
                        .accessibilityIdentifier("academic-publication-count")
                    Text("implementation=preview.publish; publicationCount=\(count)")
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("implementation=preview.publish; publicationCount=\(count)")
                        .accessibilityIdentifier("page-refresh-diagnostic")
                }
                .frame(width: 1, height: 1, alignment: .topTrailing)
                .allowsHitTesting(false)
            }
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
        .accessibilityLabel("返回")
    }
}
