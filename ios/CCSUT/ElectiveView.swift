//
//  ElectiveView.swift
//  CCSUT
//
//  选课 · 教学班浏览
//
//  数据来源：/admin/xsd/xk/listjxbDataV2（JSON，实测 71 KB）
//  本页只做只读浏览与筛选；真正的选课/退课属于写操作，走教务官方页面。
//

import SwiftUI

struct ElectiveView: View {
    @Environment(SessionStore.self) private var session

    @State private var initData: ElectiveInit?
    @State private var classes: [TeachingClass] = []
    @State private var keyword = ""
    @State private var selectedFilter: Filter = .all
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var detail: TeachingClass?
    @State private var pending: PendingAction?
    @State private var workingId: String?
    @State private var actionMessage: String?

    /// jxbid → pcid，选课/退课时必须带对批次
    @State private var batchMap: [String: String] = [:]

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case selected = "已选"
        case available = "可选"
        case free = "有余量"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && classes.isEmpty {
                    ProgressView("拉取教学班…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText, classes.isEmpty {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(errorText)
                    } actions: {
                        Button("重试") { Task { await load(force: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if classes.isEmpty {
                    ContentUnavailableView {
                        Label("当前没有可选课程", systemImage: "tray")
                    } description: {
                        Text(initData.map { "选课学期 \($0.xkxnxq ?? "—")" } ?? "")
                    } actions: {
                        Button("刷新") { Task { await load(force: true) } }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("选课")
            .searchable(text: $keyword, prompt: "课程名 / 教师")
            .refreshable { await load(force: true) }
            .task {
                if classes.isEmpty { await load() }
            }
            .sheet(item: $detail) { item in
                CourseDetailSheet(item: item)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(26)
            }
        }
    }

    // MARK: 列表

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                filterBar

                if let initData {
                    header(initData)
                }

                ForEach(filtered) { item in
                    ClassCard(
                        item: item,
                        onAction: { pending = PendingAction(item: item, enrolling: !item.isSelected) },
                        isWorking: workingId == item.id
                    )
                    .contentShape(.rect)
                    .onTapGesture { detail = item }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(
            pending.map { $0.enrolling ? "确认选课？" : "确认退课？" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { action in
            Button(action.enrolling ? "选课" : "退课", role: action.enrolling ? nil : .destructive) {
                Task { await perform(action) }
            }
            Button("取消", role: .cancel) { pending = nil }
        } message: { action in
            Text(action.item.kcmc ?? "")
        }
        .alert("操作结果", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("好", role: .cancel) { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private func header(_ data: ElectiveInit) -> some View {
        HStack(spacing: 8) {
            Label(data.xkxnxq ?? "—", systemImage: "calendar")
            Divider().frame(height: 14)
            Label(data.xsxm ?? "—", systemImage: "person")
            Spacer()
            if selectedCount > 0 {
                Label("\(selectedCount) 已选", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text("\(filtered.count) 门")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var selectedCount: Int { classes.filter(\.isSelected).count }

    /// 执行选课/退课
    private func perform(_ action: PendingAction) async {
        pending = nil
        guard let pcid = batchMap[action.item.id] else {
            actionMessage = "找不到这条课程所属的选课批次，请下拉刷新后重试"
            return
        }

        workingId = action.item.id
        defer { workingId = nil }

        do {
            let msg = action.enrolling
                ? try await APIClient.shared.enroll(jxbid: action.item.id, pcid: pcid)
                : try await APIClient.shared.dropClass(jxbid: action.item.id, pcid: pcid)
            actionMessage = msg
            await load(force: true)
        } catch let e as APIError {
            if case .business(_, let text) = e {
                // 服务端把业务限制（超门数、时间冲突、已满）放在 msg 里，直接展示
                actionMessage = text
            } else {
                actionMessage = e.localizedDescription
            }
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { f in
                    let on = f == selectedFilter
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { selectedFilter = f }
                    } label: {
                        HStack(spacing: 4) {
                            Text(f.rawValue)
                                .font(.caption.weight(.medium))
                            if f == .selected, selectedCount > 0 {
                                Text("\(selectedCount)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.white.opacity(on ? 0.25 : 0.15), in: .capsule)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            on ? AnyShapeStyle(Color.accentColor)
                               : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                            in: .capsule
                        )
                        .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.top, 2)
    }

    // MARK: 筛选

    private var filtered: [TeachingClass] {
        classes.filter { item in
            let kw = keyword.trimmingCharacters(in: .whitespaces)
            if !kw.isEmpty {
                let hay = "\(item.kcmc ?? "") \(item.teacher ?? "") \(item.kcid ?? "")"
                if !hay.localizedCaseInsensitiveContains(kw) { return false }
            }
            switch selectedFilter {
            case .all: return true
            case .selected: return item.isSelected
            case .available: return item.canSelect
            case .free: return !item.isFull
            }
        }
    }

    // MARK: 加载

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let initData = try await APIClient.shared.electiveInit()
            self.initData = initData

            // pcencs 里可能有多个选课批次（实测有 2 个：网络课 63 门 + 面授课 75 门）
            // 必须逐个拉、合并去重；只取第一个会漏掉一大半
            var merged: [TeachingClass] = []
            var seen = Set<String>()
            var lastError: Error?


            if let batches = initData.pcencs, !batches.isEmpty {
                for (pcid, pcenc) in batches {
                    do {
                        let page = try await APIClient.shared.teachingClasses(batch: (pcid, pcenc))
                        let n = page.initData?.count ?? 0
                        for item in page.initData ?? [] where !seen.contains(item.id) {
                            seen.insert(item.id)
                            merged.append(item)
                            batchMap[item.id] = pcid
                        }
                    } catch {
                        lastError = error
                    }
                }
            } else {
                let page = try await APIClient.shared.teachingClasses(batch: nil)
                merged = page.initData ?? []
            }


            if merged.isEmpty, let lastError { throw lastError }

            classes = merged.sorted {
                ($0.kcmc ?? "").localizedStandardCompare($1.kcmc ?? "") == .orderedAscending
            }
        } catch let e as APIError {
            if case .notLoggedIn = e {
                await session.refresh()
                errorText = "会话过期，已尝试自动续期，请下拉刷新"
            } else {
                errorText = e.localizedDescription
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 课程卡片

struct PendingAction: Identifiable {
    let id = UUID()
    let item: TeachingClass
    let enrolling: Bool
}

struct ClassCard: View {
    let item: TeachingClass
    var onAction: (() -> Void)? = nil
    var isWorking: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.kcmc ?? "—")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(item.xf ?? "—")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.tint)
                    Text("学分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let teacher = item.teacher, !teacher.isEmpty {
                Label(teacher, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let place = item.sksjdd, !place.isEmpty {
                Label(place, systemImage: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                CapacityBar(item: item)

                if item.isFull && !item.isSelected {
                    Text("已满")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if item.canSelect && !item.isSelected {
                    Text("可选")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 4)

                if let onAction {
                    Button(action: onAction) {
                        HStack(spacing: 4) {
                            if isWorking {
                                ProgressView().controlSize(.mini)
                            }
                            Text(item.isSelected ? "退课" : "选课")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            item.isSelected ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.14),
                            in: .capsule
                        )
                        .foregroundStyle(item.isSelected ? Color.red : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || (!item.isSelected && item.isFull))
                    .opacity((!item.isSelected && item.isFull) ? 0.45 : 1)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if item.isSelected {
                Text("已选")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.green, in: .capsule)
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
        .overlay {
            if item.isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.green.opacity(0.55), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - 容量条

struct CapacityBar: View {
    let item: TeachingClass

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(fillColor.gradient)
                        .frame(width: max(4, geo.size.width * item.fillRatio))
                }
            }
            .frame(height: 5)

            Text("\(item.enrolled)/\(item.capacity)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var fillColor: Color {
        if item.fillRatio >= 1 { return .red }
        if item.fillRatio >= 0.8 { return .orange }
        return .green
    }
}

// MARK: - 详情

struct ClassDetailSheet: View {
    let item: TeachingClass

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.kcmc ?? "—")
                            .font(.title3.weight(.semibold))
                        Text(item.jxbmc ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section("基本信息") {
                    row("课程代码", item.kcid)
                    row("学分", item.xf)
                    row("课程类别", item.kclbname)
                    row("课程性质", item.kcxz)
                    row("教学方式", item.jxms)
                    row("考核方式", item.ksxs)
                }

                Section("安排") {
                    row("教师", item.teacher)
                    row("上课时间地点", item.sksjdd)
                    if let raw = item.sksjddstr, !raw.isEmpty {
                        row("周次编码", ScheduleCodec.humanize(raw))
                    }
                    row("校区", item.kkxqmc)
                }

                Section("选课情况") {
                    LabeledContent("已选 / 容量", value: "\(item.enrolled) / \(item.capacity)")
                    LabeledContent("状态") {
                        if item.isSelected {
                            Label("已选", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text(item.isFull ? "已满" : (item.canSelect ? "可选" : "不可选"))
                                .foregroundStyle(item.isFull ? .orange : (item.canSelect ? .green : .secondary))
                        }
                    }
                }

                if let bz = item.bz, !bz.isEmpty {
                    Section("备注") {
                        Text(bz).font(.footnote)
                    }
                }

                Section {
                    Label(
                        "选课、退课请在教务官方页面操作，本页只做浏览。",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty, value != "--" {
            LabeledContent(title) {
                Text(value)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
