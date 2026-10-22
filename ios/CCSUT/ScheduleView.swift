//
//  ScheduleView.swift
//  CCSUT
//
//  课表 · 4 大节 × 7 天
//
//  学校按「2 小节 = 1 大节」排课，所以 8 节要压成 4 行：
//    djc 1,2 → 第 1 大节   3,4 → 第 2 大节   5,6 → 第 3 大节   7,8 → 第 4 大节
//
//  数据：POST /admin/xsd/pkgl/xskb/sdpkkbList（JSON，98 条记录）
//  必须先 GET queryKbForXsd 拿隐藏字段 xhid
//

import SwiftUI

struct ScheduleView: View {
    @Environment(SessionStore.self) private var session

    @State private var bundle: ScheduleBundle?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var selectedWeek = 1
    @State private var currentWeek = 1
    @State private var didPickWeek = false

    // 4 大节，每行给足高度
    private let rows = 4
    private let periodHeight: CGFloat = 108
    private let timeColumnWidth: CGFloat = 26
    private let headerHeight: CGFloat = 26
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if bundle?.isEmpty == false {
                    weekBar
                }

                if isLoading && bundle == nil {
                    Spacer()
                    ProgressView("加载课表…")
                    Spacer()
                } else if let errorText, bundle == nil {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorText)
                    } actions: {
                        Button("重试") { Task { await load(force: true) } }
                    }
                } else if let bundle, !bundle.isEmpty {
                    timetable
                } else {
                    ContentUnavailableView {
                        Label("暂无课表", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("当前学期还没有排课数据。")
                    } actions: {
                        Button("重新加载") { Task { await load(force: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(navTitle)
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

    private var navTitle: String {
        guard let t = bundle?.title, !t.isEmpty else { return "课表" }
        return t
    }

    // MARK: - 周次胶囊（Liquid Glass）

    private var maxWeek: Int {
        let m = bundle?.slots.flatMap(\.weeks).max() ?? 18
        return max(18, m)
    }

    private var weekBar: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(1...maxWeek, id: \.self) { w in
                            weekPill(w)
                                .id(w)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .onChange(of: selectedWeek) { _, w in
                    withAnimation(.smooth(duration: 0.3)) {
                        proxy.scrollTo(w, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedWeek, anchor: .center)
                }
            }
        }
    }

    private func weekPill(_ w: Int) -> some View {
        let isSelected = w == selectedWeek
        let isCurrent = w == currentWeek

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedWeek = w }
        } label: {
            VStack(spacing: 0) {
                Text("\(w)")
                    .font(.system(size: 15, weight: isSelected ? .bold : .medium).monospacedDigit())
                Text(isCurrent ? "本周" : "周")
                    .font(.system(size: 8, weight: .medium))
                    .opacity(0.75)
            }
            .frame(width: 46, height: 46)
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected
                ? .regular.tint(.accentColor).interactive()
                : .regular.interactive(),
            in: .capsule
        )
        .overlay(alignment: .topTrailing) {
            if isCurrent && !isSelected {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .padding(6)
            }
        }
    }

    // MARK: - 网格

    private var timetable: some View {
        GeometryReader { geo in
            let colWidth = max(0, (geo.size.width - timeColumnWidth) / 7)

            VStack(spacing: 0) {
                // 表头固定，不参与滚动，也不会被课程块盖住
                weekdayHeader(colWidth: colWidth)

                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        gridLines(colWidth: colWidth)
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                            courseBlock(cell.slot, extra: cell.extra, colWidth: colWidth)
                        }
                    }
                    .frame(height: CGFloat(rows) * periodHeight)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func weekdayHeader(colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumnWidth)

            ForEach(Array(weekdays.enumerated()), id: \.offset) { i, day in
                Text(day)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: colWidth, height: headerHeight)
            }
        }
        .frame(height: headerHeight)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.4))
                .frame(height: 0.5)
        }
    }

    private func gridLines(colWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<rows, id: \.self) { i in
                // 大节号
                VStack(spacing: 0) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .frame(width: timeColumnWidth, height: periodHeight)
                .offset(y: CGFloat(i) * periodHeight)

                // 横线
                Rectangle()
                    .fill(Color(.separator).opacity(0.28))
                    .frame(width: colWidth * 7, height: 0.5)
                    .offset(x: timeColumnWidth, y: CGFloat(i + 1) * periodHeight)

                // 上午 / 下午 分隔稍粗
                if i == 1 {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.55))
                        .frame(width: colWidth * 7, height: 1)
                        .offset(x: timeColumnWidth, y: CGFloat(i + 1) * periodHeight)
                }
            }

            // 竖线
            ForEach(0...7, id: \.self) { i in
                Rectangle()
                    .fill(Color(.separator).opacity(0.2))
                    .frame(width: 0.5, height: CGFloat(rows) * periodHeight)
                    .offset(x: timeColumnWidth + CGFloat(i) * colWidth)
            }
        }
    }

    // MARK: - 课程块

    private func courseBlock(_ slot: ScheduleSlot, extra: Int, colWidth: CGFloat) -> some View {
        let x = timeColumnWidth + CGFloat(slot.weekday - 1) * colWidth
        let y = CGFloat(slot.bigSection - 1) * periodHeight
        let h = periodHeight - 4
        let tint = Self.tint(for: slot.course)

        return VStack(alignment: .leading, spacing: 3) {
            Text(slot.course)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            if !slot.room.isEmpty {
                Text(slot.room)
                    .font(.system(size: 10))
                    .opacity(0.85)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(width: max(0, colWidth - 4), height: h, alignment: .topLeading)
        .background(tint.gradient, in: .rect(cornerRadius: 9))
        .overlay(alignment: .topTrailing) {
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.25), in: .capsule)
                    .padding(3)
            }
        }
        .offset(x: x, y: y)
    }

    /// 按 (星期, 大节) 归并
    private var cells: [(slot: ScheduleSlot, extra: Int)] {
        guard let bundle else { return [] }
        let groups = Dictionary(grouping: bundle.slots) {
            "\($0.weekday)-\($0.bigSection)"
        }
        return groups.values
            .compactMap { slots -> (ScheduleSlot, Int)? in
                guard let first = slots.first else { return nil }
                return (first, slots.count - 1)
            }
            .sorted { ($0.0.weekday, $0.0.bigSection) < ($1.0.weekday, $1.0.bigSection) }
    }

    private var visibleSlots: [ScheduleSlot] {
        guard let bundle else { return [] }
        return bundle.slots.filter { slot in
            slot.weeks.isEmpty || slot.weeks.contains(selectedWeek)
        }
    }

    // MARK: - 加载

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, bundle != nil { return }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let initData = try await APIClient.shared.electiveInit()
            let xnxq = initData.xkxnxq ?? "2026-2027-1"

            if let w = try? await APIClient.shared.currentTeachingWeek(), w > 0 {
                currentWeek = w
                if !didPickWeek { selectedWeek = w; didPickWeek = true }
            }

            let xhid = try await APIClient.shared.scheduleXhid(xnxq: xnxq)
            let items = try await APIClient.shared.scheduleItems(xnxq: xnxq, xhid: xhid)

            let slots = items.map(\.slot).filter { !$0.course.isEmpty }
            bundle = ScheduleBundle(title: xnxq, slots: slots, periods: Array(1...rows))
        } catch let e as APIError {
            if case .notLoggedIn = e {
                await session.refresh()
                errorText = "会话过期，已尝试续期，请下拉刷新"
            } else {
                errorText = e.localizedDescription
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - 稳定配色

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
