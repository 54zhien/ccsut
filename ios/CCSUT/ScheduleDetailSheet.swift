import SwiftUI

struct ScheduleDetailSheet: View {
    let slot: ScheduleSlot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "课程详情") { dismiss() }
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(slot.course)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(weekdayName) · \(SchedulePresentation.periodCaption(slot))")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        information("person", label: "任课教师", value: slot.teacher.isEmpty ? "未标注" : slot.teacher)
                        Divider().padding(.leading, 28)
                        information("mappin", label: "上课地点", value: slot.room.isEmpty ? "未标注" : slot.room)
                        Divider().padding(.leading, 28)
                        information("clock", label: "上课时间", value: clockRange ?? "未标注")
                        Divider().padding(.leading, 28)
                        information("calendar", label: "上课周次",
                                    value: slot.weeks.isEmpty ? "未标注" : "第 \(WeekParser.compress(slot.weeks.sorted())) 周")
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
    }

    private func information(_ symbol: String, label: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Label(label, systemImage: symbol)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }

    private var weekdayName: String {
        let days = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
        return days.indices.contains(slot.weekday - 1) ? days[slot.weekday - 1] : "时间待定"
    }

    private var clockRange: String? {
        guard slot.startPeriod % 2 == 1, slot.endPeriod == slot.startPeriod + 1 else { return nil }
        let ranges = ["8:20–10:00", "10:20–12:00", "14:00–15:40", "16:00–17:40"]
        let index = (slot.startPeriod - 1) / 2
        return ranges.indices.contains(index) ? ranges[index] : nil
    }
}
