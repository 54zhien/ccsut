import SwiftUI
import UIKit
import CoreHaptics

struct LeaveTicketPrinter: UIViewRepresentable {
    let record: CampusLeaveRecord
    let completion: () -> Void
    func makeUIView(context: Context) -> LeavePrinterSurface {
        let view = LeavePrinterSurface()
        view.completion = completion
        view.configure(title: record.typeName ?? "请假条", date: record.beginTime ?? "", status: record.statusText)
        return view
    }
    func updateUIView(_ uiView: LeavePrinterSurface, context: Context) {}
    static func dismantleUIView(_ uiView: LeavePrinterSurface, coordinator: ()) { uiView.cancel() }
}

final class LeavePrinterSurface: UIView {
    var completion: (() -> Void)?
    private let machine = UIView()
    private let channel = UIView()
    private let lip = UIView()
    private let body = UIView()
    private let paper = UIView()
    private let text = UILabel()
    private var started = false
    private var generation = 0
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        machine.backgroundColor = UIColor(white: 0.055, alpha: 1)
        machine.layer.cornerRadius = 20
        machine.layer.cornerCurve = .continuous
        channel.clipsToBounds = true
        lip.backgroundColor = UIColor(white: 0.035, alpha: 1)
        lip.layer.cornerRadius = 3
        lip.layer.borderColor = UIColor(white: 0.3, alpha: 1).cgColor
        lip.layer.borderWidth = 1 / traitCollection.displayScale
        paper.backgroundColor = UIColor(red: 0.99, green: 0.97, blue: 0.91, alpha: 1)
        paper.layer.cornerRadius = 6
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.textColor = UIColor(white: 0.2, alpha: 1)
        text.numberOfLines = 3
        text.textAlignment = .center
        addSubview(machine); addSubview(channel); addSubview(lip)
        channel.addSubview(body); body.addSubview(paper); paper.addSubview(text)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(title: String, date: String, status: String) { text.text = "\(title)\n\(date)\n\(status)" }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !started, bounds.width > 0, window != nil else { return }
        started = true
        machine.frame = CGRect(x: bounds.midX - 62, y: 0, width: 124, height: 49.5)
        let slot = CGRect(x: bounds.midX - 48, y: 32, width: 96, height: 11.5)
        channel.frame = CGRect(x: slot.minX, y: slot.minY, width: slot.width, height: 180)
        // Foreground lip covers the cut edge; its highlight remains visible.
        lip.frame = slot
        body.bounds = CGRect(x: 0, y: 0, width: 150, height: 180)
        paper.bounds = CGRect(x: 0, y: 0, width: 150, height: 78)
        paper.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        paper.layer.position = CGPoint(x: body.bounds.midX, y: body.bounds.midY)
        paper.transform = CGAffineTransform(rotationAngle: .pi / 2).scaledBy(x: 0.9, y: 0.9)
        text.frame = paper.bounds.insetBy(dx: 8, dy: 8)
        body.center = CGPoint(x: channel.bounds.midX, y: -0.9 * body.bounds.width)
        let token = generation
        if UIAccessibility.isReduceMotionEnabled {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.completion?()
            }
            return
        }
        startHaptics()
        UIView.animate(springDuration: 0.52, bounce: 0.06, initialSpringVelocity: 0.08,
                       delay: 0, options: [.allowUserInteraction]) {
            self.body.center.y = 0
        } completion: { [weak self] finished in
            guard let self, finished, self.generation == token, self.window != nil else { return }
            self.stopHaptics()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
            // Lift the same paper out of its clipping window and tuck it into the wallet above.
            let position = self.convert(self.body.center, from: self.channel)
            self.addSubview(self.body)
            self.body.center = position
            UIView.animate(withDuration: 0.48, delay: 0.12, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.body.center = CGPoint(x: self.bounds.midX, y: -70)
                self.body.transform = CGAffineTransform(rotationAngle: -.pi / 2).scaledBy(x: 0.35, y: 0.35)
                self.body.alpha = 0
                self.machine.alpha = 0
                self.lip.alpha = 0
            } completion: { [weak self] finished in
                guard let self, finished, self.generation == token, self.window != nil else { return }
                self.completion?()
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancel() } else { setNeedsLayout() }
    }
    func cancel() {
        generation += 1
        body.layer.removeAllAnimations()
        machine.layer.removeAllAnimations()
        lip.layer.removeAllAnimations()
        stopHaptics()
        completion = nil
    }
    private func startHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            self.engine = engine
            try engine.start()
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.28),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.16)
            ], relativeTime: 0, duration: 1.2)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            self.player = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch { stopHaptics() }
    }
    private func stopHaptics() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop(completionHandler: nil)
        engine = nil
    }
}
