import SwiftUI

/// Upcoming commitments first, followed by grouped academic services.
struct AcademicView: View {
    private enum Destination: Hashable { case scores, exams, electives }
    @Environment(\.scenePhase) private var scenePhase
    @State private var nextExam: ExamItem?
    @State private var upcomingError: String?
    @State private var reminderGeneration: UInt64?
    @State private var loadGate = PageLoadGate()
    @State private var path: [Destination] = []
    @State private var didNavigatePreview = false
    @State private var headerScrollOffset: CGFloat = 0
#if DEBUG
    @State private var previewLoaded = false
#endif

    var body: some View {
        NavigationStack(path: $path) {
            PageScrollSurface(onOffsetChange: { headerScrollOffset = $0 }) { _, _ in
                VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                    if let nextExam {
                        VStack(spacing: 12) {
                            AppSectionHeading("接下来的考试")
                            if let upcomingError {
                                PageStatusNotice(message: upcomingError) { Task { await loadUpcomingExam() } }
                            }
                            NavigationLink(value: Destination.exams) { upcomingCard(nextExam) }
                        }
                    }
                    VStack(spacing: 12) {
                        AppSectionHeading("学习与课程")
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
            .task {
                guard !InterfacePreview.enabled else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    if scenePhase == .active, let date = nextExam?.startDate, date < Date() {
                        nextExam = nil
                        await loadUpcomingExam()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadUpcomingExam() } }
            }
        }
    }



    private func upcomingCard(_ exam: ExamItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Text(exam.kcmc ?? "考试安排").font(.title2.weight(.bold)).foregroundStyle(.primary)
            if let date = exam.startDate {
                Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
                                                    locale: Locale(identifier: "zh_CN"),
                                                    timeZone: TimeZone(identifier: "Asia/Shanghai")!)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !exam.location.isEmpty {
                Label(exam.location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }

    private func loadUpcomingExam() async {
        await loadGate.run { await fetchUpcomingExam() }
    }

    private func fetchUpcomingExam() async {
        #if DEBUG
        if InterfacePreview.enabled {
            if previewLoaded && InterfacePreview.page == "academic" && ProcessInfo.processInfo.arguments.contains("--preview-controlled-refresh") {
                await PreviewRefreshCompletionGate.shared.waitForRelease()
            }
            previewLoaded = true
            nextExam = ProcessInfo.processInfo.arguments.contains("--preview-no-upcoming") ? nil : InterfacePreview.exam
            return
        }
        #endif
        let generation = CookieJar.generation
        if let reminderGeneration, reminderGeneration != generation {
            nextExam = nil
            upcomingError = nil
        }
        do {
            let context = try await APIClient.shared.timetableContext()
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            let exams = try await APIClient.shared.examList(xnxq: context.term)
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            let now = Date()
            let limit = now.addingTimeInterval(60 * 86400)
            nextExam = exams.filter {
                guard let date = $0.startDate else { return false }
                return date >= now && date <= limit
            }.min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            reminderGeneration = generation
            upcomingError = nil
        } catch {
            // An optional reminder never prevents access to the full academic pages.
            guard CookieJar.generation == generation, !(error is CancellationError) else { return }
            if let date = nextExam?.startDate, date >= Date() {
                upcomingError = "近期考试暂未更新，当前显示上次记录"
            } else {
                nextExam = nil
                upcomingError = nil
            }
        }
    }
}
