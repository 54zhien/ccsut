import SwiftUI
import UIKit

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

struct NagiRefreshButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .medium))
                    .opacity(isLoading ? 0 : 1)
                ProgressView().controlSize(.small).opacity(isLoading ? 1 : 0)
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("刷新")
        .accessibilityIdentifier("page-refresh")
        .disabled(isLoading)
    }
}

/// Both academic lists share the same inset and surface when a section pins.
struct AcademicTermStrip<Content: View>: View {
    let term: String
    @ViewBuilder var content: () -> Content
    @State private var isFloating = false

    var body: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isFloating {
                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 18))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("term-header-\(term)")
            .accessibilityValue(isFloating ? "floating" : "inline")
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.frame(in: .named("academic-scroll")).minY <= 0.5
            } action: { isFloating = $0 }
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
