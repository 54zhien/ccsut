import SwiftUI

/// A small directory of academic tasks; each destination keeps its existing UI.
struct AcademicView: View {
    private enum Destination: Hashable { case scores, exams, electives }
    @State private var nextExam: ExamItem?
    @State private var path: [Destination] = []
    @State private var didNavigatePreview = false
    @State private var headerScrollOffset: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let nextExam {
                    Section("近期安排") {
                        NavigationLink(value: Destination.exams) {
                            VStack(alignment: .leading, spacing: 9) {
                                Label("即将考试", systemImage: "calendar.badge.clock")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tint)
                                Text(nextExam.kcmc ?? "考试安排")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let date = nextExam.startDate {
                                    Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
                                                                        locale: Locale(identifier: "zh_CN"),
                                                                        timeZone: TimeZone(identifier: "Asia/Shanghai")!)))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if !nextExam.location.isEmpty {
                                    Text(nextExam.location)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 7)
                        }
                    }
                }

                Section {
                    NavigationLink(value: Destination.scores) {
                        service("成绩查询", subtitle: "课程成绩、学分与绩点", symbol: "chart.bar.doc.horizontal", tint: .blue)
                    }
                    NavigationLink(value: Destination.exams) {
                        service("考试安排", subtitle: "考试时间、考场与座位", symbol: "calendar.badge.clock", tint: .teal)
                    }
                    NavigationLink(value: Destination.electives) {
                        service("选课", subtitle: "浏览课程与管理已选课程", symbol: "list.bullet.rectangle.portrait", tint: .indigo)
                    }
                }

                if InterfacePreview.enabled {
                    Section { Text("界面预览 · 示例数据").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
            } action: { _, offset in
                headerScrollOffset = offset
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
        }
    }

    private func service(_ title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.09), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
        }
        .accessibilityElement(children: .combine)
    }

    private func loadUpcomingExam() async {
        #if DEBUG
        if InterfacePreview.enabled { nextExam = InterfacePreview.exam; return }
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
