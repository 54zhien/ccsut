import SwiftUI

/// A live, bounded vertical drum. The artwork supplies the physical glass and
/// housing; every digit here is real, adjustable application content.
struct VintageAmountDrum: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0

    let digit: Int
    let digits: [Int]
    let height: CGFloat
    let isEnabled: Bool
    let onMove: (Int) -> Void

    private var choices: [Int] { digits.isEmpty ? [digit] : digits }
    private var selectedIndex: Int { choices.firstIndex(of: digit) ?? 0 }
    private var pitch: CGFloat { max(24, height * 0.46) }

    var body: some View {
        ZStack {
            if reduceMotion {
                numeral(digit)
            } else {
                ForEach(Array(choices.enumerated()), id: \.element) { item in
                    let offset = CGFloat(item.offset - selectedIndex) * pitch + dragOffset
                    let distance = offset / pitch
                    numeral(item.element)
                        .rotation3DEffect(.degrees(-Double(distance) * 48), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                        .opacity(max(0, 1 - abs(Double(distance)) * 0.66))
                        .offset(y: offset)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(44, height))
        .contentShape(Rectangle())
        .clipped()
        .overlay {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.28), location: 0),
                .init(color: .clear, location: 0.30),
                .init(color: .white.opacity(0.035), location: 0.49),
                .init(color: .clear, location: 0.68),
                .init(color: .black.opacity(0.24), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.86), value: digit)
        .highPriorityGesture(turn, including: isEnabled ? .all : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(String(digit))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onMove(1)
            case .decrement: onMove(-1)
            @unknown default: break
            }
        }
    }

    private func numeral(_ value: Int) -> some View {
        Text(String(value))
            .font(.system(size: pitch * 1.06, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.89))
            .shadow(color: .black.opacity(0.60), radius: 1, x: 0, y: 1)
            .frame(maxWidth: .infinity)
            .frame(height: pitch)
    }

    private var turn: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, offset, transaction in
                guard isEnabled, !reduceMotion else { return }
                transaction.animation = nil
                let upper = CGFloat(selectedIndex) * pitch
                let lower = -CGFloat(choices.count - 1 - selectedIndex) * pitch
                offset = min(upper, max(lower, value.translation.height))
            }
            .onEnded { value in
                guard isEnabled, abs(value.translation.height) > abs(value.translation.width),
                      abs(value.translation.height) >= pitch * 0.27 else { return }
                let count = max(1, Int((abs(value.translation.height) / pitch).rounded()))
                onMove(value.translation.height < 0 ? count : -count)
            }
    }
}
