import SwiftUI

/// Stable, independently spaced entry cards; optional reminders follow the entries.
struct AcademicView: View {
    private enum Destination: Hashable { case scores, exams, electives }
    @State private var nextExam: ExamItem?
    @State private var loadGate = PageLoadGate()
    @State private var path: [Destination] = []
    @State private var didNavigatePreview = false
    @State private var headerScrollOffset: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { viewport in
                let cardHeight: CGFloat = 96
                ScrollView {
                    VStack(spacing: 12) {
                        NavigationLink(value: Destination.scores) {
                            service("成绩查询", subtitle: "课程成绩、学分与绩点", symbol: "chart.bar.doc.horizontal", tint: .accentColor, height: cardHeight)
                        }
                        .accessibilityIdentifier("academic-scores")
                        NavigationLink(value: Destination.exams) {
                            service("考试安排", subtitle: "考试时间、考场与座位", symbol: "calendar.badge.clock", tint: .accentColor, height: cardHeight)
                        }
                        .accessibilityIdentifier("academic-exams")
                        NavigationLink(value: Destination.electives) {
                            service("选课", subtitle: "浏览课程与管理已选课程", symbol: "list.bullet.rectangle.portrait", tint: .accentColor, height: cardHeight)
                        }
                        .accessibilityIdentifier("academic-electives")
                        if let nextExam {
                            NavigationLink(value: Destination.exams) { upcomingCard(nextExam) }
                                .padding(.top, 8)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .pageRefreshControl { await loadUpcomingExam() }
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollBounceBehavior(.always, axes: .vertical)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
                } action: { _, offset in headerScrollOffset = offset }
            }
            .background(Color(.systemGroupedBackground))
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
                await loadUpcomingExam()
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

    private func service(_ title: String, subtitle: String, symbol: String, tint: Color, height: CGFloat) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.09), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
        .contentShape(.rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }

    private func upcomingCard(_ exam: ExamItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("近期考试", systemImage: "calendar.badge.clock")
                .font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
            Text(exam.kcmc ?? "考试安排").font(.headline).foregroundStyle(.primary)
            if let date = exam.startDate {
                Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
                                                    locale: Locale(identifier: "zh_CN"),
                                                    timeZone: TimeZone(identifier: "Asia/Shanghai")!)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !exam.location.isEmpty {
                Text(exam.location).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }

    private func loadUpcomingExam() async {
        await loadGate.run { await fetchUpcomingExam() }
    }

    private func fetchUpcomingExam() async {
        #if DEBUG
        if InterfacePreview.enabled {
            nextExam = ProcessInfo.processInfo.arguments.contains("--preview-no-upcoming") ? nil : InterfacePreview.exam
            return
        }
        #endif
        do {
            let info = try await APIClient.shared.electiveInit()
            guard let term = info.xkxnxq, !term.isEmpty else { return }
            let exams = try await APIClient.shared.examList(xnxq: term)
            let now = Date()
            let limit = now.addingTimeInterval(60 * 86400)
            nextExam = exams.filter {
                guard let date = $0.startDate else { return false }
                return date >= now && date <= limit
            }.min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        } catch {
            // An optional reminder never prevents access to the full academic pages.
        }
    }
}
