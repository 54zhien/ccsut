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
    @State private var selectedTerm: String?
    @State private var referenceDate = Date()
#if DEBUG
    @State private var previewPublicationCount = 0
#endif

    var body: some View {
        PageScrollSurface(refresh: { await load(force: true) }, refreshHaptics: true) { viewport, proxy in
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
                    content()
                }
            }
            .frame(maxWidth: .infinity, minHeight: items.isEmpty ? viewport.height : 0)
            .onChange(of: selectedTerm) { _, term in
                guard let term else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    proxy.scrollTo("exam-term-\(term)", anchor: .top)
                }
            }
            .onChange(of: allTerms) { _, availableTerms in
                guard let selectedTerm, !availableTerms.contains(selectedTerm) else { return }
                self.selectedTerm = nil
            }
        }
        .coordinateSpace(name: "academic-scroll")
        .academicDetailChrome(title: "考试") {
            if !allTerms.isEmpty { termFilter }
        }
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

    private func content() -> some View {
        LazyVStack(spacing: 0, pinnedViews: dynamicTypeSize.isAccessibilitySize ? [] : [.sectionHeaders]) {
            if let selectedTerm {
                Text("筛选学期：\(SchedulePresentation.termTitle(selectedTerm))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

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
                        termHeader(term, count: list.count)
                            .id("exam-term-\(term)")
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var termFilter: some View {
        Menu {
            Picker("学期", selection: $selectedTerm) {
                Text("全部学期").tag(nil as String?)
                ForEach(allTerms, id: \.self) { term in
                    Text(SchedulePresentation.termTitle(term)).tag(Optional(term))
                }
            }
        } label: {
            Image(systemName: selectedTerm == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(selectedTerm == nil ? Color.secondary : Color.accentColor)
                .frame(width: 44, height: 44)
                .background(selectedTerm == nil ? Color.clear : Color.accentColor.opacity(0.1), in: .circle)
                .contentShape(.circle)
        }
        .accessibilityLabel("学期筛选")
        .accessibilityValue(selectedTerm.map(SchedulePresentation.termTitle) ?? "全部学期")
        .accessibilityHint("选择学期后筛选并跳转到对应内容")
        .accessibilityIdentifier("exam-term-filter")
    }

    /// 即将开始的那场（未来 60 天内最近的一场）
    private var upcoming: [ExamItem] {
        let now = referenceDate
        let limit = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now
        return displayedItems
            .filter { exam in
                guard let d = exam.startDate else { return false }
                return d >= now && d <= limit
            }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
    }

    private var allGrouped: [String: [ExamItem]] {
        Dictionary(grouping: items) { $0.term ?? $0.dataXnxq ?? "未知学期" }
    }

    private var allTerms: [String] {
        allGrouped.keys.sorted(by: >)
    }

    private var grouped: [String: [ExamItem]] {
        Dictionary(grouping: displayedItems) { $0.term ?? $0.dataXnxq ?? "未知学期" }
    }

    private var terms: [String] {
        grouped.keys.sorted(by: >)
    }

    private var displayedItems: [ExamItem] {
        guard let selectedTerm else { return items }
        return items.filter { ($0.term ?? $0.dataXnxq ?? "未知学期") == selectedTerm }
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
                Label("考试日期：\(dateText(exam))", systemImage: "calendar")
                Label("考试时间：\(timeText(exam))", systemImage: "clock.fill")
                if !locationText(exam).isEmpty {
                    Label("考场：\(locationText(exam))", systemImage: "mappin.and.ellipse")
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

    private func termHeader(_ term: String, count: Int) -> some View {
        AcademicTermStrip(term: term, tracker: termHeaderTracker) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SchedulePresentation.termTitle(term))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(count) 场")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dateText(_ exam: ExamItem) -> String {
        guard let date = exam.startDate else { return nonempty(exam.ksrq) ?? "—" }
        let style = Date.FormatStyle.dateTime
            .year()
            .month(.defaultDigits)
            .day()
            .weekday(.wide)
            .locale(Locale(identifier: "zh_CN"))
        return date.formatted(style)
    }

    private func locationText(_ exam: ExamItem) -> String {
        ExamLocationPresentation.concise(building: exam.jxlmc, room: exam.jsmc)
    }

    private func timeText(_ exam: ExamItem) -> String {
        if let raw = nonempty(exam.kssj) {
            guard let space = raw.firstIndex(of: " ") else { return raw }
            let time = raw[raw.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return time.isEmpty ? raw : time
        }
        return nonempty(exam.qssj) ?? "—"
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    @ScaledMetric(relativeTo: .title3) private var dateColumnWidth: CGFloat = 64

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text("日期")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let d = exam.startDate {
                    Text(d, format: .dateTime.month(.defaultDigits).day())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(d, format: .dateTime.weekday(.wide))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(rawDateLabel)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: dateColumnWidth)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("考试日期：\(visibleDateText)")

            VStack(alignment: .leading, spacing: 4) {
                Text(exam.kcmc ?? "—")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                Label("时间：\(visibleTimeText)", systemImage: "clock")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !visibleLocation.isEmpty {
                    Label("考场：\(visibleLocation)", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private var visibleDateText: String {
        guard let d = exam.startDate else {
            let raw = exam.ksrq?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "—" : raw
        }
        let format = Date.FormatStyle.dateTime
            .year()
            .month(.defaultDigits)
            .day()
            .weekday(.wide)
            .locale(Locale(identifier: "zh_CN"))
        return d.formatted(format)
    }

    private var visibleTimeText: String {
        if let raw = exam.kssj?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
           let space = raw.firstIndex(of: " ") {
            let time = raw[raw.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !time.isEmpty { return time }
        }
        if let raw = exam.kssj?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty { return raw }
        let start = exam.qssj?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return start.isEmpty ? "—" : start
    }

    private var rawDateLabel: String {
        let raw = exam.ksrq?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "—" : raw
    }

    private var visibleLocation: String {
        ExamLocationPresentation.concise(building: exam.jxlmc, room: exam.jsmc)
    }
}
