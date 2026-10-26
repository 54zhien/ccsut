import SwiftUI

struct ScheduleDetailSheet: View {
    let slot: ScheduleSlot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppDetailHeading(title: slot.course,
                                     subtitle: "\(weekdayName) · \(SchedulePresentation.periodCaption(slot))",
                                     symbol: "book.closed")
                        .padding(.horizontal, 4)

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
                    .padding(.horizontal, 20)
                    .appContentCard()
                }
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetSymbolButton(symbol: "xmark", label: "关闭课程详情") { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
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
