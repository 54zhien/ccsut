import SwiftUI
import UIKit

/// Keep UIKit's interactive pop with a page-owned header. Scope the delegate
/// override to the visible child and restore UIKit's delegates when it leaves.
struct AcademicPopSupport: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PopController { PopController() }
    func updateUIViewController(_ controller: PopController, context: Context) {}
    static func dismantleUIViewController(_ controller: PopController, coordinator: ()) {
        controller.restore()
    }

    final class PopController: UIViewController, UIGestureRecognizerDelegate {
        private struct SavedGesture {
            let recognizer: UIGestureRecognizer
            let delegate: (any UIGestureRecognizerDelegate)?
            let wasEnabled: Bool
        }
        private var saved: [SavedGesture] = []
        private var tabTransitionID = UUID()
        private var tabTransitionCoordinator: (any UIViewControllerTransitionCoordinator)?
        private var visibleTabAppearance: (transform: CGAffineTransform, alpha: CGFloat)?

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let nav = navigationController, nav.viewControllers.count > 1 else { return }
            transitionTabBar(hidden: true, animated: animated, navigation: nav)
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            #if DEBUG
            AcademicTabTransitionDiagnostics.trace("willDisappear nav=\(navigationController != nil) coordinator=\(navigationController?.transitionCoordinator != nil) toRoot=\(navigationController?.transitionCoordinator?.viewController(forKey: .to) === navigationController?.viewControllers.first)")
            #endif
            guard let nav = navigationController,
                  let coordinator = nav.transitionCoordinator,
                  coordinator.viewController(forKey: .to) === nav.viewControllers.first else { return }
            transitionTabBar(hidden: false, animated: animated, navigation: nav)
        }

        /// UIKit owns tab-bar visibility and the safe-area transition; the actual
        /// bar's translation and opacity follow the navigation coordinator. Never
        /// replace the system tab bar or reach into its private subviews.
        /// Apple references checked 2026-10-26:
        /// https://developer.apple.com/documentation/uikit/uitabbarcontroller/settabbarhidden(_:animated:)
        /// https://developer.apple.com/documentation/uikit/uiviewcontroller/transitioncoordinator
        /// https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinatorcontext/isanimated
        /// https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator/animatealongsidetransition(in:animation:completion:)
        /// https://developer.apple.com/documentation/uikit/uiview/transform
        /// https://developer.apple.com/documentation/corefoundation/cgaffinetransform/translatedby(x:y:)
        /// https://developer.apple.com/documentation/uikit/uiview/performwithoutanimation(_:)
        private func transitionTabBar(hidden: Bool, animated: Bool, navigation: UINavigationController) {
            let coordinator = navigation.transitionCoordinator
            #if DEBUG
            AcademicTabTransitionDiagnostics.trace("request hidden=\(hidden) nativeHidden=\(navigation.tabBarController?.isTabBarHidden.description ?? "nil") sameCoordinator=\(tabTransitionCoordinator != nil && tabTransitionCoordinator === coordinator)")
            #endif
            // Cancelling an interactive pop calls viewWillAppear again on the
            // detail. Let the original coordinator restore its captured state.
            if let active = tabTransitionCoordinator, let coordinator,
               active === coordinator { return }
            guard let tabs = navigation.tabBarController, tabs.isTabBarHidden != hidden else { return }
            let id = UUID()
            tabTransitionID = id
            let bar = tabs.tabBar
            // Hidden UIKit bars can have a zero alpha or a translated transform.
            // Reverse toward the appearance captured while the bar was visible,
            // rather than treating that hidden presentation as the visible target.
            if hidden { visibleTabAppearance = (bar.transform, bar.alpha) }
            let originalTransform = visibleTabAppearance?.transform ?? .identity
            let originalAlpha = visibleTabAppearance?.alpha ?? 1
            let loweredTransform = originalTransform.translatedBy(x: 0, y: max(bar.bounds.height, 1))
            let shouldAnimate = (coordinator?.isAnimated ?? animated) && !UIAccessibility.isReduceMotionEnabled
            let previousHidden = tabs.isTabBarHidden
            #if DEBUG
            if InterfacePreview.enabled {
                AcademicTabTransitionDiagnostics.trace("appearance hidden=\(hidden) currentAlpha=\(bar.alpha) visibleAlpha=\(originalAlpha) currentY=\(bar.transform.ty) visibleY=\(originalTransform.ty)")
            }
            AcademicTabTransitionDiagnostics.record(childAnimated: animated,
                                                    coordinatorAnimated: coordinator?.isAnimated, queued: nil)
            #endif
            guard shouldAnimate else {
                tabs.setTabBarHidden(hidden, animated: false)
                bar.transform = originalTransform
                bar.alpha = originalAlpha
                return
            }
            // Establish the real bar's start state before native visibility/layout changes.
            let prepare = {
                bar.transform = hidden ? originalTransform : loweredTransform
                bar.alpha = hidden ? originalAlpha : 0
            }
            UIView.performWithoutAnimation(prepare)
            tabs.setTabBarHidden(hidden, animated: true)
            // Native visibility must not overwrite the staged starting transform.
            UIView.performWithoutAnimation(prepare)
            let finish: (Bool) -> Void = { [weak self, weak tabs] cancelled in
                #if DEBUG
                AcademicTabTransitionDiagnostics.trace("finish hidden=\(hidden) cancelled=\(cancelled) selfAlive=\(self != nil) idMatch=\(self?.tabTransitionID == id) tabsAlive=\(tabs != nil)")
                #endif
                guard let self, self.tabTransitionID == id, let tabs else { return }
                self.tabTransitionCoordinator = nil
                tabs.setTabBarHidden(cancelled ? previousHidden : hidden, animated: false)
                UIView.performWithoutAnimation {
                    tabs.tabBar.transform = originalTransform
                    tabs.tabBar.alpha = originalAlpha
                }
                #if DEBUG
                AcademicTabTransitionDiagnostics.traceBar(tabs, event: "restored")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak tabs] in
                    if let tabs { AcademicTabTransitionDiagnostics.traceBar(tabs, event: "settled") }
                }
                #endif
            }
            if let coordinator {
                tabTransitionCoordinator = coordinator
                let queued = coordinator.animateAlongsideTransition(in: bar, animation: { _ in
                    bar.transform = hidden ? loweredTransform : originalTransform
                    bar.alpha = hidden ? 0 : originalAlpha
                }, completion: { context in finish(context.isCancelled) })
                #if DEBUG
                AcademicTabTransitionDiagnostics.record(childAnimated: animated,
                                                        coordinatorAnimated: coordinator.isAnimated, queued: queued)
                #endif
                if !queued {
                    bar.transform = hidden ? loweredTransform : originalTransform
                    bar.alpha = hidden ? 0 : originalAlpha
                }
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                    bar.transform = hidden ? loweredTransform : originalTransform
                    bar.alpha = hidden ? 0 : originalAlpha
                } completion: { _ in finish(false) }
            }
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let nav = navigationController, nav.viewControllers.count > 1 else { return }
            for gesture in [nav.interactivePopGestureRecognizer, nav.interactiveContentPopGestureRecognizer].compactMap({ $0 }) {
                guard gesture.delegate !== self else { continue }
                saved.append(SavedGesture(recognizer: gesture, delegate: gesture.delegate, wasEnabled: gesture.isEnabled))
                gesture.delegate = self
                gesture.isEnabled = true
            }
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restore()
        }
        func restore() {
            for item in saved where item.recognizer.delegate === self {
                item.recognizer.delegate = item.delegate
                item.recognizer.isEnabled = item.wasEnabled
            }
            saved.removeAll()
        }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let nav = navigationController, nav.viewControllers.count > 1,
                  nav.transitionCoordinator == nil else { return false }
            if let pan = gesture as? UIPanGestureRecognizer {
                let velocity = pan.velocity(in: nav.view)
                let direction: CGFloat = nav.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
                guard velocity.x * direction > abs(velocity.y) else { return false }
            }
            return true
        }
        private func original(for gesture: UIGestureRecognizer) -> (any UIGestureRecognizerDelegate)? {
            saved.first { $0.recognizer === gesture }?.delegate
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            original(for: gesture)?.gestureRecognizer?(gesture, shouldReceive: touch) ?? true
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            original(for: gesture)?.gestureRecognizer?(gesture, shouldRecognizeSimultaneouslyWith: other) ?? false
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            original(for: gesture)?.gestureRecognizer?(gesture, shouldRequireFailureOf: other) ?? false
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            original(for: gesture)?.gestureRecognizer?(gesture, shouldBeRequiredToFailBy: other) ?? false
        }
    }
}

#if DEBUG
@MainActor private enum AcademicTabTransitionDiagnostics {
    static func traceBar(_ tabs: UITabBarController, event: String) {
        let bar = tabs.tabBar
        let rect = bar.convert(bar.bounds, to: bar.window)
        var ancestors: [String] = []
        var parent = bar.superview
        while let view = parent {
            ancestors.append("\(type(of: view)):hidden=\(view.isHidden),alpha=\(view.alpha)")
            parent = view.superview
        }
        trace("\(event) nativeHidden=\(tabs.isTabBarHidden) hidden=\(bar.isHidden) alpha=\(bar.alpha) ty=\(bar.transform.ty) center=\(bar.center) bounds=\(bar.bounds) windowRect=\(rect) ancestors=\(ancestors)")
    }
    static func trace(_ message: String) {
        guard InterfacePreview.enabled else { return }
        let line = "TAB_TRANSITION \(message)\n"
        print(line, terminator: "")
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let data = line.data(using: .utf8) else { return }
        let file = directory.appendingPathComponent("tab-transition.log")
        if !FileManager.default.fileExists(atPath: file.path) {
            try? data.write(to: file)
        } else if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
    static var entry = "entry childAnimated=unset coordinatorAnimated=unset queued=unset"
    private static var entryID = 0
    private static var previousTabSample: (frame: CGRect, opacity: Float)?
    private static var tabDownSamples = 0
    private static var tabUpSamples = 0
    private static var validSamples = 0
    private static var missingSamples = 0
    private static var detachedCount = 0
    private static var minimumY: CGFloat?
    private static var maximumY: CGFloat?
    private static var minimumOpacity: Float?
    private static var maximumOpacity: Float?

    private static var motionReport: String {
        let range = String(format: "%.3f", Double((maximumY ?? 0) - (minimumY ?? 0)))
        let lowOpacity = minimumOpacity.map { String(format: "%.3f", Double($0)) } ?? "nil"
        let highOpacity = maximumOpacity.map { String(format: "%.3f", Double($0)) } ?? "nil"
        return "tabDown=\(tabDownSamples) tabUp=\(tabUpSamples) tabDetached=\(detachedCount) tabYRange=\(range) "
            + "tabOpacityMin=\(lowOpacity) tabOpacityMax=\(highOpacity)"
    }

    static var publicationKey: String {
        "\(motionReport) tabPresent=\(previousTabSample != nil) \(entry)"
    }

    static var tabReport: String {
        "\(motionReport) tabSamples=\(validSamples) tabMissing=\(missingSamples)"
    }

    static func record(childAnimated: Bool, coordinatorAnimated: Bool?, queued: Bool?) {
        guard InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-transition") else { return }
        if queued == nil {
            entryID += 1
            previousTabSample = nil
            tabDownSamples = 0
            tabUpSamples = 0
            minimumY = nil
            maximumY = nil
            minimumOpacity = nil
            maximumOpacity = nil
        }
        let coordinatorValue = coordinatorAnimated.map { String($0) } ?? "nil"
        let queuedValue = queued.map { String($0) } ?? "nil"
        entry = "entry childAnimated=\(childAnimated) coordinatorAnimated=\(coordinatorValue) queued=\(queuedValue) entryID=\(entryID)"
    }

    static func detached() {
        detachedCount += 1
        previousTabSample = nil
    }

    /// Public controller containment and presentation-layer geometry only.
    /// Apple references checked 2026-10-26:
    /// https://developer.apple.com/documentation/uikit/uiviewcontroller/children
    /// https://developer.apple.com/documentation/quartzcore/calayer/presentation()
    /// https://developer.apple.com/documentation/quartzcore/calayer/convert(_:to:)-tly5
    private static func findTabController(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        if let presented = controller.presentedViewController,
           let tabs = findTabController(in: presented) { return tabs }
        for child in controller.children {
            if let tabs = findTabController(in: child) { return tabs }
        }
        return nil
    }

    static func sampleTabBar(in window: UIWindow?) {
        guard let window, let root = window.rootViewController,
              let tabs = findTabController(in: root), tabs.tabBar.window === window,
              let layer = tabs.tabBar.layer.presentation(),
              let windowLayer = window.layer.presentation() else {
            missingSamples += 1
            previousTabSample = nil
            return
        }
        let renderedFrame = layer.convert(layer.bounds, to: windowLayer)
        let opacity = layer.opacity
        validSamples += 1
        minimumY = min(minimumY ?? renderedFrame.minY, renderedFrame.minY)
        maximumY = max(maximumY ?? renderedFrame.minY, renderedFrame.minY)
        minimumOpacity = min(minimumOpacity ?? opacity, opacity)
        maximumOpacity = max(maximumOpacity ?? opacity, opacity)
        if let previous = previousTabSample {
            let deltaY = renderedFrame.minY - previous.frame.minY
            let deltaOpacity = opacity - previous.opacity
            // Each count requires both changes within the same adjacent rendered samples.
            if deltaY > 0.1 && deltaOpacity < -0.001 { tabDownSamples += 1 }
            if deltaY < -0.1 && deltaOpacity > 0.001 { tabUpSamples += 1 }
        }
        previousTabSample = (renderedFrame, opacity)
    }
}

/// Persist at the TabView root so sampling starts before a detail push.
/// Cleanup references checked 2026-10-26:
/// https://developer.apple.com/documentation/quartzcore/cadisplaylink/invalidate()
/// https://developer.apple.com/documentation/swiftui/uiviewrepresentable/dismantleuiview(_:coordinator:)
struct AcademicTabTransitionRootProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> SamplerView { SamplerView(frame: .zero) }
    func updateUIView(_ view: SamplerView, context: Context) {}
    static func dismantleUIView(_ view: SamplerView, coordinator: ()) { view.stopSampling() }

    final class SamplerView: UIView {
        private var displayLink: CADisplayLink?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            stopSampling()
            guard window != nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(sample))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        func stopSampling() {
            if displayLink != nil { AcademicTabTransitionDiagnostics.detached() }
            displayLink?.invalidate()
            displayLink = nil
        }
        deinit { displayLink?.invalidate() }
        @objc private func sample() { AcademicTabTransitionDiagnostics.sampleTabBar(in: window) }
    }
}

struct AcademicTitleMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = "academic-title-anchor"
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

/// Sample the page's presentation layer while it translates, including the held
/// portion of a cancelled native pop. Do not depend on SwiftUI child-controller
/// forwarding of UINavigationController.transitionCoordinator.
struct AcademicTransitionProbe: UIViewRepresentable {
    let report: (CGFloat, Int, String) -> Void

    func makeUIView(context: Context) -> ProbeView { ProbeView(report: report) }
    func updateUIView(_ view: ProbeView, context: Context) { view.report = report }

    final class ProbeView: UIView {
        var report: (CGFloat, Int, String) -> Void
        private var displayLink: CADisplayLink?
        private var baseline: CGFloat?
        private var maximum: CGFloat = 0
        private var samples = 0
        private var ticks = 0
        private var activeTicks = 0
        private var maxTranslation: CGFloat = 0
        private var lastDiagnosticState = ""

        init(report: @escaping (CGFloat, Int, String) -> Void) {
            self.report = report
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            displayLink?.invalidate()
            displayLink = nil
            if window != nil {
                let link = CADisplayLink(target: self, selector: #selector(sample))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }
        deinit { displayLink?.invalidate() }

        private func findMarker(_ root: UIView) -> UIView? {
            if root.accessibilityIdentifier == "academic-title-anchor" { return root }
            for child in root.subviews {
                if let result = findMarker(child) { return result }
            }
            return nil
        }
        private func frame(_ view: UIView, in window: UIWindow) -> CGRect {
            let layer = view.layer.presentation() ?? view.layer
            return layer.convert(view.bounds, to: window.layer.presentation() ?? window.layer)
        }
        private func isPopActive(in controller: UIViewController) -> Bool {
            if let nav = controller as? UINavigationController,
               [nav.interactivePopGestureRecognizer, nav.interactiveContentPopGestureRecognizer]
                .compactMap({ $0 }).contains(where: { $0.state == .began || $0.state == .changed }) {
                return true
            }
            if let presented = controller.presentedViewController, isPopActive(in: presented) { return true }
            return controller.children.contains { isPopActive(in: $0) }
        }
        @objc private func sample() {
            ticks += 1
            guard let window, let root = window.rootViewController else { return }
            guard let marker = findMarker(window) else { return }
            let pageX = frame(self, in: window).minX
            let localTitleX = frame(marker, in: window).midX - pageX
            let active = isPopActive(in: root)
            if active { activeTicks += 1 }
            maxTranslation = max(maxTranslation, abs(pageX))
            if active, abs(pageX) > 2, let baseline {
                samples += 1
                maximum = max(maximum, abs(localTitleX - baseline))
            } else if abs(pageX) <= 2 {
                self.baseline = localTitleX
            }
            if ticks % 30 == 0 {
                let titleState = "active=\(activeTicks) maxX=\(Int(maxTranslation)) baseline=\(baseline != nil) width=\(Int(bounds.width))"
                let state = "\(titleState) \(AcademicTabTransitionDiagnostics.publicationKey)"
                guard state != lastDiagnosticState else { return }
                lastDiagnosticState = state
                report(maximum, samples, "ticks=\(ticks) \(titleState) \(AcademicTabTransitionDiagnostics.tabReport) \(AcademicTabTransitionDiagnostics.entry)")
            }
        }
    }
}
#endif
