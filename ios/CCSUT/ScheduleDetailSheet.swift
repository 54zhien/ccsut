//
//  ScheduleDetailSheet.swift
//  CCSUT
//
//  课表详情
//
//  点课表格子里的课程块弹出，展示任课教师、上课地点、
//  星期节次和上课周次。数据全部来自 sdpkkbList。
//

import SwiftUI

struct ScheduleDetailSheet: View {
    let slot: ScheduleSlot

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    block(
                        symbol: "person.fill",
                        title: "任课教师",
                        primary: slot.teacher.isEmpty ? "未标注" : slot.teacher,
                        tint: .blue
                    )

                    block(
                        symbol: "mappin.and.ellipse",
                        title: "上课地点",
                        primary: slot.room.isEmpty ? "未标注" : slot.room,
                        tint: .orange
                    )

                    block(
                        symbol: "clock.fill",
                        title: "上课时间",
                        primary: "\(weekdayName(slot.weekday)) 第 \(slot.startPeriod)-\(slot.endPeriod) 节",
                        secondary: weekDescription,
                        tint: .purple
                    )

                    Spacer(minLength: 8)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(slot.course)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                chip("第 \(slot.startPeriod)-\(slot.endPeriod) 节", tint: .accentColor)
                chip(weekdayName(slot.weekday), tint: .secondary)
                if slot.weeks.count < 20 {
                    chip("\(slot.weeks.count) 周", tint: .secondary)
                }
            }
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: .capsule)
            .foregroundStyle(tint)
    }

    // MARK: 信息块

    private func block(symbol: String,
                       title: String,
                       primary: String,
                       secondary: String? = nil,
                       tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(primary)
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let secondary, !secondary.isEmpty {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    // MARK: 文案

    private func weekdayName(_ d: Int) -> String {
        let names = ["", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
        return names.indices.contains(d) ? names[d] : "第 \(d) 天"
    }

    /// 把 [1,2,3,6,7,8] 压成 "第 1-3、6-8 周"
    private var weekDescription: String {
        guard !slot.weeks.isEmpty else { return "" }
        let sorted = slot.weeks.sorted()
        var ranges: [(Int, Int)] = []
        var start = sorted[0]
        var prev = sorted[0]

        for w in sorted.dropFirst() {
            if w == prev + 1 {
                prev = w
            } else {
                ranges.append((start, prev))
                start = w
                prev = w
            }
        }
        ranges.append((start, prev))

        let parts = ranges.map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0)-\($0.1)" }
        return "第 " + parts.joined(separator: "、") + " 周"
    }
}
