//
//  ExamView.swift
//  CCSUT
//
//  考试安排
//
//  数据源：POST /admin/xsd/kwglXsdKscx/getXsKsxx  { xnxq }
//  实测 2025-2026-2 有 8 场，含教学楼、教室、座位号、考试批次。
//
//  页面结构：即将到来的考试置顶，其余按学期分组倒序。
//

import SwiftUI

struct ExamView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var items: [ExamItem] = []
    @State private var isLoading = false
    @State private var loadGate = PageLoadGate()
    @State private var errorText: String?
    @State private var termHeaderTracker = AcademicTermHeaderTracker()
    @State private var referenceDate = Date()
#if DEBUG
    @State private var previewPublicationCount = 0
#endif

    var body: some View {
        PageScrollSurface(refresh: { await load(force: true) }) { viewport, proxy in
            VStack(spacing: 0) {
                if isLoading && items.isEmpty {
                    ProgressView("加载考试安排…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if errorText != nil, items.isEmpty {
                    ContentUnavailableView {
                        Label(AppMessages.loadFailure, systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorText ?? AppMessages.loadFailure)
                    } actions: {
                        Button("重试") { Task { await load(force: true) } }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("暂无考试安排", systemImage: "calendar.badge.clock")
                    } description: {
                        Text("教务系统暂未返回考试安排。")
                    }
                } else {
                    if let errorText {
                        PageStatusNotice(message: errorText) { Task { await load(force: true) } }
                    }
                    content(proxy: proxy)
                }
            }
            .frame(maxWidth: .infinity, minHeight: items.isEmpty ? viewport.height : 0)
        }
        .coordinateSpace(name: "academic-scroll")
        .academicDetailChrome(title: "考试")
#if DEBUG
        .overlay(alignment: .topTrailing) {
            PageRefreshPublicationDiagnostics(count: previewPublicationCount)
        }
#endif
        .task { if items.isEmpty { await load() } }
        .task {
            guard !InterfacePreview.enabled else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if scenePhase == .active { referenceDate = Date() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { referenceDate = Date() }
        }
    }

    // MARK: 内容

    private func content(proxy: ScrollViewProxy) -> some View {
        LazyVStack(spacing: 0, pinnedViews: dynamicTypeSize.isAccessibilitySize ? [] : [.sectionHeaders]) {
            if let next = upcoming.first {
                nextCard(next).padding(.bottom, 12)
            }

            ForEach(terms, id: \.self) { term in
                let list = grouped[term] ?? []
                if !list.isEmpty {
                    Section {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { idx, exam in
                                ExamRow(exam: exam, showTerm: false)
                                if idx < list.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    } header: {
                        termHeader(term, count: list.count) { target in
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                                proxy.scrollTo("exam-term-\(target)", anchor: .top)
                            }
                        }
                            .id("exam-term-\(term)")
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }

    /// 即将开始的那场（未来 60 天内最近的一场）
    private var upcoming: [ExamItem] {
        let now = referenceDate
        let limit = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now
        return items
            .filter { exam in
                guard let d = exam.startDate else { return false }
                return d >= now && d <= limit
            }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
    }

    private var grouped: [String: [ExamItem]] {
        Dictionary(grouping: items) { $0.term ?? $0.dataXnxq ?? "未知学期" }
    }

    private var terms: [String] {
        grouped.keys.sorted(by: >)
    }

    // MARK: 置顶卡片

    private func nextCard(_ exam: ExamItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("即将开始", systemImage: "alarm.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("AccentForeground").opacity(0.9))
                Spacer()
                if let d = exam.startDate {
                    Text(d, format: .relative(presentation: .named))
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color("AccentForeground").opacity(0.85))
                }
            }

            Text(exam.kcmc ?? "—")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color("AccentForeground"))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label(timeText(exam), systemImage: "clock.fill")
                if !exam.location.isEmpty {
                    Label(exam.location, systemImage: "mappin.and.ellipse")
                }
            }
            .font(.caption)
            .foregroundStyle(Color("AccentForeground").opacity(0.92))

            if let seat = exam.zwh, !seat.isEmpty, seat != "0" {
                Text("座位 \(seat)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color("AccentForeground").opacity(0.12), in: .capsule)
                    .foregroundStyle(Color("AccentForeground"))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 16)
    }

    private func termHeader(_ term: String, count: Int, onSelectTerm: @escaping (String) -> Void) -> some View {
        AcademicTermStrip(term: term, tracker: termHeaderTracker) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(SchedulePresentation.termTitle(term))
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(count) 场")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if terms.count > 1 {
                    AcademicTermJumpMenu(terms: terms, onSelect: onSelectTerm)
                }
            }
        }
    }

    private func timeText(_ exam: ExamItem) -> String {
        guard let raw = exam.kssj, !raw.isEmpty else {
            return [exam.ksrq, exam.qssj].compactMap { $0 }.joined(separator: " ")
        }
        // "2026-09-15 14:20~15:50" → "09-15 14:20~15:50"
        if let space = raw.firstIndex(of: " ") {
            let date = raw[raw.startIndex..<space]
            let time = raw[raw.index(after: space)...]
            let parts = date.split(separator: "-")
            if parts.count == 3 {
                return "\(parts[1])-\(parts[2]) \(time)"
            }
            return "\(date) \(time)"
        }
        return raw
    }

    // MARK: 加载

    private func load(force: Bool = false) async {
        await loadGate.run { await fetch(force: force) }
    }

    private func fetch(force: Bool) async {
        #if DEBUG
        if InterfacePreview.enabled {
            isLoading = true
            defer { isLoading = false }
            if previewPublicationCount > 0 && ProcessInfo.processInfo.arguments.contains("--preview-controlled-refresh") {
                await PreviewRefreshCompletionGate.shared.waitForRelease()
            } else {
                try? await Task.sleep(for: InterfacePreview.refreshFixtureDelay)
            }
            guard !Task.isCancelled else { return }
            items = InterfacePreview.emptyPage ? [] : InterfacePreview.exams
            previewPublicationCount += 1
            return
        }
        #endif

        guard !isLoading else { return }
        if !force, !items.isEmpty { return }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let generation = CookieJar.generation
        var loadingStage = "读取考试学期"
        do {
            let terms = try await APIClient.shared.availableExamTerms()
            let complete = try await ExamSnapshotLoader.load(terms: terms) { term in
                guard CookieJar.generation == generation else { throw CancellationError() }
                loadingStage = "读取\(SchedulePresentation.termTitle(term))考试"
                return try await APIClient.shared.examList(xnxq: term)
            }
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            items = complete
            referenceDate = Date()
        } catch {
            guard CookieJar.generation == generation, !(error is CancellationError) else { return }
            if let apiError = error as? APIError, case .notLoggedIn = apiError {
                await session.refresh()
            }
            guard CookieJar.generation == generation else { return }
            let reason: String
            if let contextError = error as? AcademicContextError {
                reason = contextError.localizedDescription
            } else if let apiError = error as? APIError {
                reason = apiError.localizedDescription
            } else if let networkError = error as? URLError, networkError.code == .timedOut {
                reason = "请求超时，请稍后重试"
            } else {
                reason = "连接未完成，请检查网络后重试"
            }
            errorText = "\(loadingStage)失败：\(reason)" + (items.isEmpty ? "" : "。已保留上次完整的考试安排")
        }
    }
}

// MARK: - 行

private struct ExamRow: View {
    let exam: ExamItem
    var showTerm: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var dateColumnWidth: CGFloat = 34

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                if let d = exam.startDate {
                    Text(d, format: .dateTime.month(.defaultDigits))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(d, format: .dateTime.day())
                        .font(.title3.weight(.bold).monospacedDigit())
                } else {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: dateColumnWidth)

            VStack(alignment: .leading, spacing: 4) {
                Text(exam.kcmc ?? "—")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exam.qssj ?? "—")
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if !exam.location.isEmpty {
                            Text(exam.location)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Text(exam.qssj ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !exam.location.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(exam.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 6) {
                    if let seat = exam.zwh, !seat.isEmpty, seat != "0" {
                        Text("座位 \(seat)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: .capsule)
                            .foregroundStyle(Color.accentColor)
                    }
                    if exam.isMakeup {
                        Text("补缓考")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.14), in: .capsule)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
