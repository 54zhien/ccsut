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
    @State private var batchLog: [String] = []

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
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
                    VStack(spacing: 16) {
                        ContentUnavailableView {
                            Label("当前没有可选课程", systemImage: "tray")
                        } description: {
                            Text(initData.map { "选课学期 \($0.xkxnxq ?? "—")" } ?? "")
                        } actions: {
                            Button("刷新") { Task { await load(force: true) } }
                        }

                        Text("若显示 0 门，可能是本学期选课名额已满或批次已关闭")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        if !batchLog.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(batchLog, id: \.self) { line in
                                    Text(line)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                        }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("选课")
            .searchable(text: $keyword, prompt: "课程名 / 教师")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("筛选", selection: $selectedFilter) {
                            ForEach(Filter.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable { await load(force: true) }
            .task {
                if classes.isEmpty { await load() }
            }
            .sheet(item: $detail) { item in
                ClassDetailSheet(item: item)
            }
        }
    }

    // MARK: 列表

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let initData {
                    header(initData)
                }

                ForEach(filtered) { item in
                    Button {
                        detail = item
                    } label: {
                        ClassCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemGroupedBackground))
    }

    private func header(_ data: ElectiveInit) -> some View {
        HStack(spacing: 8) {
            Label(data.xkxnxq ?? "—", systemImage: "calendar")
            Divider().frame(height: 14)
            Label(data.xsxm ?? "—", systemImage: "person")
            Spacer()
            Text("\(filtered.count) 门")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 4)
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

            var log: [String] = []
            log.append("strategy: \(initData.pcencs?.count ?? 0) 个批次")

            if let batches = initData.pcencs, !batches.isEmpty {
                for (pcid, pcenc) in batches {
                    do {
                        let page = try await APIClient.shared.teachingClasses(batch: (pcid, pcenc))
                        let n = page.initData?.count ?? 0
                        log.append("\(pcid.prefix(8))… enc\(pcenc.count)字 → \(n) 门")
                        for item in page.initData ?? [] where !seen.contains(item.id) {
                            seen.insert(item.id)
                            merged.append(item)
                        }
                    } catch {
                        log.append("\(pcid.prefix(8))… → 失败 \(error.localizedDescription.prefix(40))")
                        lastError = error
                    }
                }
            } else {
                let page = try await APIClient.shared.teachingClasses(batch: nil)
                merged = page.initData ?? []
            }

            batchLog = log
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

struct ClassCard: View {
    let item: TeachingClass

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

                if item.isFull {
                    Text("已满")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if item.canSelect {
                    Text("可选")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if item.canSelect && !item.isFull {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.green.opacity(0.25), lineWidth: 1)
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
                        Text(item.isFull ? "已满" : (item.canSelect ? "可选" : "不可选"))
                            .foregroundStyle(item.isFull ? .orange : (item.canSelect ? .green : .secondary))
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
