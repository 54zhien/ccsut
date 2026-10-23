import SwiftUI

struct ScheduleDetailSheet: View {
    let slot: ScheduleSlot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("课程详情").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .circle)
                .accessibilityLabel("关闭课程详情")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.tint)
                            .frame(width: 44, height: 44)
                            .background(.tint.opacity(0.09), in: .rect(cornerRadius: 12))
                        Text(slot.course)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }

                    VStack(spacing: 0) {
                        information("person", label: "任课教师", value: slot.teacher.isEmpty ? "未标注" : slot.teacher)
                        Divider().padding(.leading, 48)
                        information("mappin", label: "上课地点", value: slot.room.isEmpty ? "未标注" : slot.room)
                        Divider().padding(.leading, 48)
                        information("clock", label: weekdayName,
                                    value: "第 \(slot.startPeriod)–\(slot.endPeriod) 节", detail: clockRange)
                    }
                    .padding(.horizontal, 14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("上课周次").font(.caption).foregroundStyle(.secondary)
                        Text(slot.weeks.isEmpty ? "未标注" : "第 \(WeekParser.compress(slot.weeks.sorted())) 周")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                }
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func information(_ symbol: String, label: String, value: String, detail: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value).font(.subheadline.weight(.medium))
                    if let detail { Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private var weekdayName: String {
        let days = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
        return days.indices.contains(slot.weekday - 1) ? days[slot.weekday - 1] : "上课时间"
    }

    private var clockRange: String? {
        guard slot.startPeriod % 2 == 1, slot.endPeriod == slot.startPeriod + 1 else { return nil }
        let ranges = ["8:20–10:00", "10:20–12:00", "14:00–15:40", "16:00–17:40"]
        let index = (slot.startPeriod - 1) / 2
        return ranges.indices.contains(index) ? ranges[index] : nil
    }
}
