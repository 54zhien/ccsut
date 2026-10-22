//
//  ScheduleView.swift
//  CCSUT
//
//  课表 · 原生网格
//
//  数据来源：/admin/xsd/pkgl/xskb/queryKbForXsd（服务端渲染 HTML，由 ScheduleParser 解析）
//  注意：非选课学期可能返回空表（下学期课表未排），这是正常现象
//

import SwiftUI

struct ScheduleView: View {
    @Environment(SessionStore.self) private var session

    @State private var bundle: ScheduleBundle?
    @State private var isLoading = false
    @State private var errorText: String?

    private let periodHeight: CGFloat = 76
    private let timeColumnWidth: CGFloat = 30
    private let headerHeight: CGFloat = 30
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && bundle == nil {
                    ProgressView("加载课表…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorText)
                    } actions: {
                        Button("重试") { Task { await load(force: true) } }
                    }
                } else if let bundle, !bundle.isEmpty {
                    grid(bundle)
                } else {
                    emptyState
                }
            }
            .navigationTitle(bundle?.title.isEmpty == false ? "课表 · \(bundle!.title)" : "课表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .refreshable { await load(force: true) }
            .task {
                if bundle == nil { await load() }
            }
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无课表", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("当前学期还没有排课数据。\n选课结束后课表会出现在这里。")
        } actions: {
            Button("重新加载") { Task { await load(force: true) } }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: 网格

    private func grid(_ bundle: ScheduleBundle) -> some View {
        let rows = max(8, bundle.periods.count)
        let totalHeight = headerHeight + CGFloat(rows) * periodHeight + 12

        return ScrollView(.vertical) {
            GeometryReader { geo in
                let colWidth = max(0, (geo.size.width - timeColumnWidth) / 7)

                ZStack(alignment: .topLeading) {
                    // 表头
                    weekdayHeader(colWidth: colWidth)

                    // 网格线
                    gridLines(rows: rows, colWidth: colWidth, height: totalHeight)

                    // 课程块（同一格可能有多门课，分周上）
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        courseBlock(cell.slot, extra: cell.extra, colWidth: colWidth)
                    }
                }
                .frame(height: totalHeight, alignment: .top)
            }
            .frame(height: totalHeight)
            .padding(.horizontal, 8)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func weekdayHeader(colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumnWidth)
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: colWidth, height: headerHeight)
            }
        }
    }

    private func gridLines(rows: Int, colWidth: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<rows, id: \.self) { i in
                // 横线
                Rectangle()
                    .fill(Color(.separator).opacity(0.35))
                    .frame(height: 0.5)
                    .offset(
                        x: timeColumnWidth,
                        y: headerHeight + CGFloat(i) * periodHeight + periodHeight
                    )

                // 节次
                Text("\(i + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: timeColumnWidth, height: periodHeight)
                    .offset(y: headerHeight + CGFloat(i) * periodHeight)
            }

            // 竖线
            ForEach(0...7, id: \.self) { i in
                Rectangle()
                    .fill(Color(.separator).opacity(0.25))
                    .frame(width: 0.5)
                    .offset(
                        x: timeColumnWidth + CGFloat(i) * colWidth,
                        y: headerHeight
                    )
                    .frame(height: height - headerHeight, alignment: .top)
            }
        }
    }

    private func courseBlock(_ slot: ScheduleSlot, extra: Int, colWidth: CGFloat) -> some View {
        let x = timeColumnWidth + CGFloat(slot.weekday - 1) * colWidth
        let y = headerHeight + CGFloat(slot.startPeriod - 1) * periodHeight
        let h = CGFloat(slot.periodSpan) * periodHeight - 3
        let tint = Self.tint(for: slot.course)

        return VStack(alignment: .leading, spacing: 2) {
            Text(slot.course)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            if !slot.room.isEmpty {
                Text(slot.room)
                    .font(.system(size: 9))
                    .opacity(0.8)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.25), in: .capsule)
            }
        }
        .foregroundStyle(.white)
        .padding(4)
        .frame(width: max(0, colWidth - 3), height: max(0, h), alignment: .topLeading)
        .background(tint.gradient, in: .rect(cornerRadius: 8))
        .offset(x: x, y: y)
    }

    /// 按 (星期, 节次) 归并，一格里可能压着好几门分周上的课
    private var cells: [(slot: ScheduleSlot, extra: Int)] {
        guard let bundle else { return [] }
        let groups = Dictionary(grouping: bundle.slots) { "\($0.weekday)-\($0.startPeriod)" }
        return groups.values
            .compactMap { slots -> (ScheduleSlot, Int)? in
                guard let first = slots.first else { return nil }
                return (first, slots.count - 1)
            }
            .sorted { ($0.0.weekday, $0.0.startPeriod) < ($1.0.weekday, $1.0.startPeriod) }
    }

    // MARK: 加载

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, bundle != nil { return }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            // 1. 学期（选课接口里带着，不用额外请求）
            let initData = try await APIClient.shared.electiveInit()
            let xnxq = initData.xkxnxq ?? "2026-2027-1"

            // 2. xhid（课表页里的隐藏字段）
            let xhid = try await APIClient.shared.scheduleXhid(xnxq: xnxq)

            // 3. 真实课表 JSON
            let items = try await APIClient.shared.scheduleItems(xnxq: xnxq, xhid: xhid)

            let slots = items
                .map(\.slot)
                .filter { !$0.course.isEmpty }

            bundle = ScheduleBundle(
                title: xnxq,
                slots: slots,
                periods: Array(1...8)
            )
        } catch let e as APIError {
            if case .notLoggedIn = e {
                await session.refresh()
                errorText = "会话已过期，已尝试自动续期，请下拉刷新"
            } else {
                errorText = e.localizedDescription
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: 稳定配色

    /// 不用 hashValue（每次运行种子不同），用字符码求和保证颜色稳定
    private static let palette: [Color] = [
        Color(red: 0.26, green: 0.44, blue: 0.92),
        Color(red: 0.85, green: 0.35, blue: 0.40),
        Color(red: 0.18, green: 0.62, blue: 0.52),
        Color(red: 0.72, green: 0.45, blue: 0.86),
        Color(red: 0.92, green: 0.56, blue: 0.26),
        Color(red: 0.30, green: 0.55, blue: 0.72),
        Color(red: 0.62, green: 0.52, blue: 0.28),
        Color(red: 0.45, green: 0.40, blue: 0.78),
    ]

    private static func tint(for name: String) -> Color {
        let seed = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(seed) % palette.count]
    }
}

// MARK: - 课程详情

struct CourseDetailSheet: View {
    let slot: ScheduleSlot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(slot.course)
                        .font(.title3.weight(.semibold))
                }
                Section("安排") {
                    LabeledContent("星期", value: "周\(["", "一", "二", "三", "四", "五", "六", "日"][max(1, min(7, slot.weekday))])")
                    LabeledContent("节次", value: "第 \(slot.startPeriod)–\(slot.endPeriod) 节")
                    if !slot.teacher.isEmpty {
                        LabeledContent("教师", value: slot.teacher)
                    }
                    if !slot.room.isEmpty {
                        LabeledContent("地点", value: slot.room)
                    }
                }
            }
            .navigationTitle("课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
