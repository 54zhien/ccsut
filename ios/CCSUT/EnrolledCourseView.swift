import SwiftUI

/// Personal result records do not contain live capacity or mutation authority.
struct EnrolledCourseCard: View {
    let record: EnrolledCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(record.kcmc ?? "—")
                    .font(.headline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("\(record.xf ?? "—") 学分")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1), in: .capsule)
            }
            if let teacher = record.rkjs, !teacher.isEmpty {
                Label(teacher, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let schedule = record.sksjdd, !schedule.isEmpty {
                Label(schedule, systemImage: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack(alignment: .center, spacing: 10) {
                Label(record.xkfs == "选课" ? "自主选课" : record.xkfs ?? "来源待核实",
                      systemImage: record.xkfs == "选课" ? "checkmark.circle" : "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(record.studyStatus)
                    .fontWeight(.medium)
                    .foregroundStyle(record.xdfs == "1" ? Color.green : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((record.xdfs == "1" ? Color.green : Color.secondary).opacity(0.1),
                                in: .capsule)
            }
            .font(.caption)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appContentCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("enrolled-course-\(record.id)")
    }
}

struct EnrolledCourseDetail: View {
    let record: EnrolledCourse
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    AppDetailHeading(title: record.kcmc ?? "—", subtitle: record.jxbmc ?? "", symbol: "checkmark.seal")
                        .padding(.vertical, 8)
                }
                Section("修读记录") {
                    row("学年学期",SchedulePresentation.termTitle(record.xnxq))
                    row("修读状态",record.studyStatus)
                    row("来源",record.xkfs == "选课" ? "自主选课" : record.xkfs)
                    row("学分",record.xf)
                    row("课程性质",record.kcxz)
                    row("授课方式",record.skfs)
                }
                Section("安排") {
                    row("教师",record.rkjs)
                    row("上课时间地点",record.sksjdd)
                }
                Section("编号") {
                    row("课程",record.kcbh)
                    row("教学班",record.jxbbh)
                }
            }
            .navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SheetHeader(title: "课程详情") { dismiss() }
                    .background(Color(.systemGroupedBackground))
            }
        }
    }
    @ViewBuilder private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty, value != "--" {
            LabeledContent(title) { Text(value).multilineTextAlignment(.trailing) }
        }
    }
}
