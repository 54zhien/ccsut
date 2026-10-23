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

    @State private var items: [ExamItem] = []
    @State private var isLoading = false
    @State private var loadGate = PageLoadGate()
    @State private var errorText: String?
    @State private var loadedTerms: Set<String> = []
    @State private var termHeaderTracker = AcademicTermHeaderTracker()

    /// 从新到旧的学期列表
    private static let terms = [
        "2026-2027-1",
        "2025-2026-2",
        "2025-2026-1",
        "2024-2025-2",
        "2024-2025-1",
    ]

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    if isLoading && items.isEmpty {
                        ProgressView("加载考试安排…")
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
                            Label("暂无考试安排", systemImage: "calendar.badge.clock")
                        } description: {
                            Text("这个学期的考试还没排出来。")
                        }
                    } else {
                        content
                    }
                }
                .frame(maxWidth: .infinity, minHeight: items.isEmpty ? viewport.size.height : 0)
                .pageRefreshControl(showsRefreshCount: true) { await load(force: true) }
            }
            .coordinateSpace(name: "academic-scroll")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .academicDetailChrome(title: "考试")
        .task { if items.isEmpty { await load() } }
    }

    // MARK: 内容

    private var content: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
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
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }

    /// 即将开始的那场（未来 60 天内最近的一场）
    private var upcoming: [ExamItem] {
        let now = Date()
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
        let keys = Set(grouped.keys)
        let known = Self.terms.filter { keys.contains($0) }
        let extra = keys.subtracting(Self.terms).sorted(by: >)
        return known + extra
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

    private func termHeader(_ term: String, count: Int) -> some View {
        AcademicTermStrip(term: term, tracker: termHeaderTracker) {
            HStack {
                Text(SchedulePresentation.termTitle(term))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(count) 场")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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
            try? await Task.sleep(for: .milliseconds(250))
            items = InterfacePreview.emptyPage ? [] : InterfacePreview.exams
            return
        }
        #endif

        guard !isLoading else { return }
        if !force, !items.isEmpty { return }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        var collected: [ExamItem] = []
        var firstError: Error?

        for term in Self.terms {
            do {
                var list = try await APIClient.shared.examList(xnxq: term)
                // 服务端的 dataXnxq 恒为当前学期，不能用来分组。
                // 每条记录真正属于哪个学期，只有发起请求的人知道。
                for i in list.indices { list[i].term = term }
                collected.append(contentsOf: list)
            } catch let e as APIError {
                if case .notLoggedIn = e {
                    await session.refresh()
                    errorText = "会话过期，已尝试续期，请下拉刷新"
                    return
                }
                if firstError == nil { firstError = e }
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if collected.isEmpty, let firstError {
            errorText = firstError.localizedDescription
            return
        }

        // 按时间倒序，没有时间的排最后
        items = collected.sorted { a, b in
            switch (a.startDate, b.startDate) {
            case let (x?, y?): return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return false
            }
        }
    }
}

// MARK: - 行

private struct ExamRow: View {
    let exam: ExamItem
    var showTerm: Bool

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
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(exam.kcmc ?? "—")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

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
