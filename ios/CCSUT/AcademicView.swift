import SwiftUI

/// Direct access to academic services.
struct AcademicView: View {
    private enum Destination: Hashable { case scores, exams, electives }
    @State private var path: [Destination] = []
    @State private var didNavigatePreview = false
    @State private var headerScrollOffset: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            PageScrollSurface(onOffsetChange: { headerScrollOffset = $0 }) { _, _ in
                VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                    VStack(spacing: 12) {
                        VStack(spacing: 0) {
                            NavigationLink(value: Destination.scores) {
                                AppServiceRow(title: "成绩查询", symbol: "chart.bar.doc.horizontal")
                            }
                            .accessibilityIdentifier("academic-scores")
                            Divider().padding(.leading, 80)
                            NavigationLink(value: Destination.exams) {
                                AppServiceRow(title: "考试安排", symbol: "calendar.badge.clock")
                            }
                            .accessibilityIdentifier("academic-exams")
                            Divider().padding(.leading, 80)
                            NavigationLink(value: Destination.electives) {
                                AppServiceRow(title: "选课", symbol: "list.bullet.rectangle.portrait")
                            }
                            .accessibilityIdentifier("academic-electives")
                        }
                        .appContentCard()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppLayout.pageInset)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .nagiPageChrome(title: "教务", scrollOffset: headerScrollOffset) {
                AccountButton()
            }
            .navigationTitle("教务")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .scores: ScoreView()
                case .exams: ExamView()
                case .electives: ElectiveView()
                }
            }
            .task {
                if InterfacePreview.enabled && !didNavigatePreview {
                    didNavigatePreview = true
                    switch InterfacePreview.page {
                    case "scores": path = [.scores]
                    case "exams": path = [.exams]
                    case "electives": path = [.electives]
                    default: break
                    }
                }
            }
        }
    }
}
