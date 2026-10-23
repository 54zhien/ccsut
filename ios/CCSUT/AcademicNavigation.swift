import SwiftUI
import UIKit

#if DEBUG
/// Observe presentation geometry during a real UIKit interactive transition.
struct AcademicTransitionProbe: UIViewControllerRepresentable {
    let title: String
    let report: (CGFloat, Int) -> Void

    func makeUIViewController(context: Context) -> ProbeController {
        ProbeController(title: title, report: report)
    }
    func updateUIViewController(_ controller: ProbeController, context: Context) {
        controller.report = report
    }

    final class ProbeController: UIViewController {
        let titleText: String
        var report: (CGFloat, Int) -> Void
        private var displayLink: CADisplayLink?
        private var baseline: CGFloat?
        private var maximum: CGFloat = 0
        private var samples = 0

        init(title: String, report: @escaping (CGFloat, Int) -> Void) {
            titleText = title
            self.report = report
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            let link = CADisplayLink(target: self, selector: #selector(sample))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            displayLink?.invalidate()
            displayLink = nil
        }
        deinit { displayLink?.invalidate() }

        private func find(_ root: UIView, matching predicate: (UIView) -> Bool) -> UIView? {
            if predicate(root) { return root }
            for child in root.subviews {
                if let result = find(child, matching: predicate) { return result }
            }
            return nil
        }
        private func frame(_ view: UIView, in window: UIWindow) -> CGRect {
            let layer = view.layer.presentation() ?? view.layer
            return layer.convert(view.bounds, to: window.layer.presentation() ?? window.layer)
        }
        @objc private func sample() {
            guard let window = view.window else { return }
            let marker = find(window) { $0.accessibilityIdentifier == "academic-title-anchor" }
            let label = navigationController.flatMap { nav in
                find(nav.navigationBar) { ($0 as? UILabel)?.text == self.titleText && !$0.isHidden }
            }
            guard let titleView = marker ?? label else { return }
            let localTitleX = frame(titleView, in: window).midX - frame(view, in: window).minX
            if let transition = navigationController?.transitionCoordinator {
                guard transition.isInteractive, let baseline else { return }
                samples += 1
                maximum = max(maximum, abs(localTitleX - baseline))
                if samples % 8 == 0 { report(maximum, samples) }
            } else {
                baseline = localTitleX
            }
        }
    }
}
#endif
