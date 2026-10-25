//
//  ScoreView.swift
//  CCSUT
//
//  成绩单
//
//  数据源：GET /admin/ydd/inf/getXscjJson?xnxq=111
//    · 111 是服务端约定的「全部学期」，一次拿回 61 门跨 5 学期的记录
//    · 这条接口是移动端成绩页 /admin/ydd/inf/showScore 背后用的
//    · 不是 /admin/xsd/xsdzgcjcx/xscjdy —— 那条是 PC 端 JSP 报表，
//      学校的 .rpx 模板缺失，永远报「报表文件不存在」
//

import SwiftUI

struct ScoreView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onLoaded: ([ScoreItem]) -> Void = { _ in }

    @State private var items: [ScoreItem] = []
    @State private var isLoading = false
    @State private var loadGate = PageLoadGate()
    @State private var errorText: String?
    @State private var termHeaderTracker = AcademicTermHeaderTracker()
#if DEBUG
    @State private var previewPublicationCount = 0
#endif

    var body: some View {
        PageScrollSurface(refresh: { await load(force: true) }) { viewport, proxy in
            VStack(spacing: 0) {
                if isLoading && items.isEmpty {
                    ProgressView("加载成绩…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if errorText != nil, items.isEmpty {
                    ContentUnavailableView {
                        Label(AppMessages.loadFailure, systemImage: "wifi.exclamationmark")
                    } description: {
                        EmptyView()
                    } actions: {
                        Button("重试") { Task { await load(force: true) } }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("暂无成绩", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("这学期还没出成绩，或者还没完成评教。")
                    }
                } else {
                    if let errorText {
                        PageStatusNotice(message: errorText) { Task { await load(force: true) } }
                    }
                    content { term in
                        if reduceMotion {
                            proxy.scrollTo(term, anchor: .top)
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(term, anchor: .top)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: items.isEmpty ? viewport.height : 0)
        }
        .coordinateSpace(name: "academic-scroll")
        .academicDetailChrome(title: "成绩单")
#if DEBUG
        .overlay(alignment: .topTrailing) {
            PageRefreshPublicationDiagnostics(count: previewPublicationCount)
        }
#endif
        .task { if items.isEmpty { await load() } }
    }

    // MARK: - 内容

    private var terms: [ScoreTerm] {
        let groups = Dictionary(grouping: items) { $0.xnxq ?? "未知学期" }
        return groups
            .map { ScoreTerm(name: $0.key, items: $0.value.sorted { ($0.kcbh ?? "") < ($1.kcbh ?? "") }) }
            .sorted { $0.name > $1.name }        // 新学期在前
    }

    private var overallGPA: Double {
        let graded = items.filter(\.hasGrade)
        let weighted = graded.reduce(0.0) { $0 + $1.point * $1.credit }
        let credits = graded.reduce(0.0) { $0 + $1.credit }
        return credits > 0 ? weighted / credits : 0
    }

    private var overallCredits: Double {
        items.reduce(0) { $0 + $1.credit }
    }

    private func content(onSelectTerm: @escaping (String) -> Void) -> some View {
        LazyVStack(spacing: 0, pinnedViews: dynamicTypeSize.isAccessibilitySize ? [] : [.sectionHeaders]) {
            summaryCard.padding(.bottom, 12)

            ForEach(terms) { term in
                Section {
                    VStack(spacing: 0) {
                        ForEach(Array(term.items.enumerated()), id: \.element.id) { idx, item in
                            ScoreRow(item: item)
                            if idx < term.items.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                } header: {
                    termHeader(term, onSelectTerm: onSelectTerm)
                        .id(term.name)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("学业概览", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    summaryRow(value: String(format: "%.2f", overallGPA), label: "加权绩点")
                    Divider()
                    summaryRow(value: String(format: "%.1f", overallCredits), label: "总学分")
                    Divider()
                    summaryRow(value: "\(items.count)", label: "门课程")
                }
            } else {
                HStack(spacing: 0) {
                    statBlock(value: String(format: "%.2f", overallGPA), label: "加权绩点", tint: .accentColor)
                    Divider().frame(height: 34)
                    statBlock(value: String(format: "%.1f", overallCredits), label: "总学分", tint: .accentColor)
                    Divider().frame(height: 34)
                    statBlock(value: "\(items.count)", label: "门课程", tint: .accentColor)
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
        .padding(.horizontal, 16)
    }

    private func statBlock(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryRow(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func termHeader(_ term: ScoreTerm, onSelectTerm: @escaping (String) -> Void) -> some View {
        let termNames = terms.map(\.name)
        let stats = "GPA \(String(format: "%.2f", term.gpa)) · \(String(format: "%.1f", term.credits)) 学分 · \(term.items.count) 门课程"
        return AcademicTermStrip(term: term.name, tracker: termHeaderTracker) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(SchedulePresentation.termTitle(term.name))
                        .font(.headline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stats)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if term.failedCount > 0 {
                        Text("\(term.failedCount) 门未通过")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    if termNames.count > 1 {
                        HStack {
                            Spacer(minLength: 0)
                            AcademicTermJumpMenu(terms: termNames, onSelect: onSelectTerm)
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SchedulePresentation.termTitle(term.name))
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(stats)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if term.failedCount > 0 {
                            Text("\(term.failedCount) 门未通过")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer(minLength: 4)
                    if termNames.count > 1 {
                        AcademicTermJumpMenu(terms: termNames, onSelect: onSelectTerm)
                    }
                }
            }
        }
    }

    // MARK: - 加载

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
            let previewItems = InterfacePreview.emptyPage ? [] : InterfacePreview.scores
            items = previewItems
            onLoaded(previewItems)
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
        do {
            let list = try await APIClient.shared.scoreList()
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            items = list
            onLoaded(list)
        } catch let e as APIError {
            guard CookieJar.generation == generation else { return }
            if case .notLoggedIn = e {
                await session.refresh()
                guard CookieJar.generation == generation else { return }
                errorText = items.isEmpty ? "会话需要更新，请重试。" : "会话需要更新，请重试。原有成绩已保留。"
            } else {
                errorText = items.isEmpty ? e.localizedDescription : "成绩更新失败，当前显示上次加载的结果"
            }
        } catch {
            if CookieJar.generation == generation, !(error is CancellationError) {
                errorText = items.isEmpty ? AppMessages.loadFailure : "成绩更新失败，当前显示上次加载的结果"
            }
        }
    }
}

// MARK: - 单行

private struct ScoreRow: View {
    let item: ScoreItem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreakdownExpanded = false

    var body: some View {
        let breakdown = item.breakdown
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.courseName.isEmpty ? "未命名课程" : item.courseName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.scoreText)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(item.failed ? Color.red : Color.primary)
                    Text("总评")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("总评 \(item.scoreText)")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(creditText) 学分")
                    .font(.subheadline.weight(.semibold).monospacedDigit())

                Spacer(minLength: 8)

                Text("绩点 \(item.jd.map { String(format: "%.2f", $0) } ?? "—")")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let kcxz = item.kcxz, !kcxz.isEmpty {
                Text(kcxz)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !breakdown.isEmpty {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        isBreakdownExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isBreakdownExpanded ? "收起成绩明细" : "查看成绩明细")
                        Text("\(breakdown.count) 项")
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                        Image(systemName: isBreakdownExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isBreakdownExpanded ? "收起成绩明细" : "查看成绩明细")
                .accessibilityHint(isBreakdownExpanded ? "收起课程各项成绩构成" : "展开课程各项成绩构成")
                .accessibilityIdentifier("score-breakdown-\(accessibilityKey)")

                if isBreakdownExpanded {
                    VStack(spacing: 0) {
                        ForEach(Array(breakdown.enumerated()), id: \.offset) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(entry.element.0)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(entry.element.1)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                    .accessibilityIdentifier("score-breakdown-details-\(accessibilityKey)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    private var accessibilityKey: String {
        if let id = item.id, !id.isEmpty { return id }
        if let courseCode = item.kcbh, !courseCode.isEmpty { return courseCode }
        return "\(item.xnxq ?? "unknown")-\(item.courseName)"
    }

    private var creditText: String {
        guard let raw = item.xf?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw != "-", raw != "--" else { return "—" }
        return Double(raw).map { String(format: "%.1f", $0) } ?? raw
    }
}
