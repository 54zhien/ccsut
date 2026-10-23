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

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
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
    let report: (CGFloat, Int) -> Void

    func makeUIView(context: Context) -> ProbeView { ProbeView(report: report) }
    func updateUIView(_ view: ProbeView, context: Context) { view.report = report }

    final class ProbeView: UIView {
        var report: (CGFloat, Int) -> Void
        private var displayLink: CADisplayLink?
        private var baseline: CGFloat?
        private var maximum: CGFloat = 0
        private var samples = 0

        init(report: @escaping (CGFloat, Int) -> Void) {
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
            guard let window, let root = window.rootViewController, let marker = findMarker(window) else { return }
            let pageX = frame(self, in: window).minX
            let localTitleX = frame(marker, in: window).midX - pageX
            if isPopActive(in: root), abs(pageX) > 2, let baseline {
                samples += 1
                maximum = max(maximum, abs(localTitleX - baseline))
                if samples % 8 == 0 { report(maximum, samples) }
            } else if abs(pageX) <= 2 {
                self.baseline = localTitleX
            }
        }
    }
}
#endif
