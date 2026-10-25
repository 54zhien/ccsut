import SwiftUI

struct CampusView: View {
    private enum Destination: Hashable { case leave, travel, electricity }
    @State private var path: [Destination] = []
    @State private var headerScrollOffset: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink(value: Destination.leave) {
                        service("请假", subtitle: "查看请假记录与办理申请", symbol: "doc.text")
                    }
                    .accessibilityIdentifier("campus-leave")
                    NavigationLink(value: Destination.travel) {
                        service("节假日离返校", subtitle: "查看假期离校、返校记录", symbol: "figure.walk.departure")
                    }
                    .accessibilityIdentifier("campus-travel")
                    NavigationLink(value: Destination.electricity) {
                        service("电表缴费", subtitle: "查询宿舍电表余额与充值", symbol: "bolt.fill")
                    }
                    .accessibilityIdentifier("campus-electricity")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 28)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollBounceBehavior(.always, axes: .vertical)
            .trackVerticalPageOffset($headerScrollOffset)
            .background(Color(.systemGroupedBackground))
            .nagiPageChrome(title: "校园", scrollOffset: headerScrollOffset) { AccountButton() }
            .navigationTitle("校园")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .leave: CampusRecordsView(mode: .leave)
                case .travel: CampusRecordsView(mode: .travel)
                case .electricity: EcardPaymentView()
                }
            }
            .task {
                guard InterfacePreview.enabled, path.isEmpty else { return }
                if InterfacePreview.page == "campus-leave" { path = [.leave] }
                if InterfacePreview.page == "campus-travel" { path = [.travel] }
            }
        }
    }

    private func service(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium)).foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.09), in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
        .contentShape(.rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}
