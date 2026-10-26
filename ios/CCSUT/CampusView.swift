import SwiftUI

struct CampusView: View {
    private enum Destination: Hashable { case leave, travel, electricity }
    @State private var path: [Destination] = []
    @State private var headerScrollOffset: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                    VStack(spacing: 12) {
                        AppSectionHeading("校园事务")
                        VStack(spacing: 0) {
                            NavigationLink(value: Destination.leave) {
                                AppServiceRow(title: "请假", symbol: "doc.text")
                            }
                            .accessibilityIdentifier("campus-leave")
                            Divider().padding(.leading, 80)
                            NavigationLink(value: Destination.travel) {
                                AppServiceRow(title: "节假日离返校", symbol: "figure.walk.departure")
                            }
                            .accessibilityIdentifier("campus-travel")
                        }
                        .appContentCard()
                    }
                    VStack(spacing: 12) {
                        AppSectionHeading("生活缴费")
                    NavigationLink(value: Destination.electricity) {
                        AppServiceRow(title: "电表缴费", symbol: "bolt")
                    }
                    .appContentCard()
                    .accessibilityIdentifier("campus-electricity")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppLayout.pageInset).padding(.top, 20).padding(.bottom, 28)
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


}
