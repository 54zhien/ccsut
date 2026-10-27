// Details use the fields already returned by listjxbDataV2; sksjdd is server-formatted.

import SwiftUI

struct CourseDetailSheet: View {
    let item: TeachingClass
    var actionBlockReason: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let actionBlockReason {
                        section("操作状态") {
                            Label(actionBlockReason, systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("操作不可用：\(actionBlockReason)")
                        }
                    }
                    infoGrid.padding(20).appContentCard()
                    if !item.sksjddText.isEmpty {
                        section("上课时间地点") {
                            Text(item.sksjddText)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }
                    if let name = item.jxbmc, !name.isEmpty, name != item.kcmc {
                        section("教学班") {
                            Text(name)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }
                    section("编号") {
                        HStack(spacing: 16) {
                            labeled("课程", item.kcbh)
                            labeled("教学班", String(item.jxbbh?.suffix(12) ?? ""))
                        }
                    }
                    Spacer(minLength: 8)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SheetHeader(title: "课程详情") { dismiss() }
                    .background(Color(.systemGroupedBackground))
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppDetailHeading(title: item.kcmc ?? "—", subtitle: "", symbol: "book.closed")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 8) {
                tag("\(item.xf ?? "—") 学分", tint: .accentColor)
                if let lx = item.kclx, !lx.isEmpty { tag(lx, tint: .secondary) }
                if let ks = item.ksxs, !ks.isEmpty { tag(ks, tint: .secondary) }
                if item.isSelected {
                    tag("已选", tint: .green)
                } else if item.isFull {
                    tag("已满", tint: .orange)
                }
            }

            if let teacher = item.teacher, !teacher.isEmpty, teacher != "-" {
                Label(teacher, systemImage: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: .capsule)
            .foregroundStyle(tint)
    }

    // MARK: 信息网格

    private var infoGrid: some View {
        VStack(spacing: 0) {
            gridRow("课程类别", item.kclbname)
            gridRow("课程性质", item.kcxz)
            gridRow("教学方式", item.jxms)
            gridRow("校区", item.kkxqmc)
            gridRow("容量", item.yxrl)
        }
    }

    private func gridRow(_ title: String, _ value: String?) -> some View {
        guard let v = value, !v.isEmpty, v != "-", v != "--" else {
            return AnyView(EmptyView())
        }
        return AnyView(
            HStack(alignment: .top, spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(v)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 9)
        )
    }

    // MARK: 通用区块

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AppSectionHeading(title)
            content()
                .padding(20).frame(maxWidth: .infinity, alignment: .leading).appContentCard()
        }
    }

    private func labeled(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text((value?.isEmpty == false) ? value! : "—")
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

// MARK: - 便捷取值

extension TeachingClass {
    /// sksjdd 是服务端给的可读文本，如「第8-15周 星期四 第3-4节【7-南102】」
    var sksjddText: String {
        let v = sksjdd ?? ""
        return (v.isEmpty || v == "-" || v == "--") ? "" : v
    }
}
