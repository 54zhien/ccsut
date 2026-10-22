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
    @Environment(\.dismiss) private var dismiss

    @State private var items: [ScoreItem] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var selectedTerm: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("加载成绩…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText, items.isEmpty {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorText)
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
                    content
                }
            }
            .navigationTitle("成绩单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
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
            .task { if items.isEmpty { await load() } }
        }
    }

    // MARK: - 内容

    private var terms: [ScoreTerm] {
        let groups = Dictionary(grouping: items) { $0.xnxq ?? "未知学期" }
        return groups
            .map { ScoreTerm(name: $0.key, items: $0.value.sorted { ($0.kcbh ?? "") < ($1.kcbh ?? "") }) }
            .sorted { $0.name > $1.name }        // 新学期在前
    }

    private var overallGPA: Double {
        let weighted = items.reduce(0.0) { $0 + $1.point * $1.credit }
        let credits = items.reduce(0.0) { $0 + $1.credit }
        return credits > 0 ? weighted / credits : 0
    }

    private var overallCredits: Double {
        items.reduce(0) { $0 + $1.credit }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                summaryCard

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
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    } header: {
                        termHeader(term)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                statBlock(value: String(format: "%.2f", overallGPA), label: "加权绩点", tint: .blue)
                Divider().frame(height: 34)
                statBlock(value: String(format: "%.1f", overallCredits), label: "总学分", tint: .green)
                Divider().frame(height: 34)
                statBlock(value: "\(items.count)", label: "门课程", tint: .orange)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
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

    private func termHeader(_ term: ScoreTerm) -> some View {
        HStack {
            Text(term.name)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if term.failedCount > 0 {
                Text("\(term.failedCount) 挂")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.15), in: .capsule)
                    .foregroundStyle(.red)
            }
            Text(String(format: "GPA %.2f", term.gpa))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("· \(String(format: "%.1f", term.credits)) 学分")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - 加载

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, !items.isEmpty { return }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let list = try await APIClient.shared.scoreList()
            items = list
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
}

// MARK: - 单行

private struct ScoreRow: View {
    let item: ScoreItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.courseName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(String(format: "%.2g 学分", item.credit))
                    if let kcxz = item.kcxz, !kcxz.isEmpty {
                        Text("·")
                        Text(kcxz).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if !item.breakdown.isEmpty {
                    Text(item.breakdown.map { "\($0.0):\($0.1)" }.joined(separator: "  "))
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.scoreText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(item.passed ? Color.primary : Color.red)

                Text(String(format: "%.1f", item.point))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}
