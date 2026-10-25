import SwiftUI

/// Personal result records do not contain live capacity or mutation authority.
struct EnrolledCourseCard: View {
    let record: EnrolledCourse

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:8) {
                Text(record.kcmc ?? "—").font(.headline).lineLimit(2)
                Spacer(minLength:4)
                Text("\(record.xf ?? "—") 学分").font(.caption).foregroundStyle(.tint)
            }
            if let teacher = record.rkjs, !teacher.isEmpty {
                Label(teacher,systemImage:"person.fill").font(.caption).foregroundStyle(.secondary)
            }
            if let schedule = record.sksjdd, !schedule.isEmpty {
                Label(schedule,systemImage:"clock.fill").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Text(record.xkfs == "选课" ? "自主选课" : record.xkfs ?? "来源待核实")
                Spacer(minLength:8)
                Text(record.studyStatus).foregroundStyle(record.xdfs == "1" ? Color.green : Color.secondary)
            }.font(.caption)
        }
        .padding(16).frame(maxWidth:.infinity,alignment:.leading)
        .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:26))
        .accessibilityElement(children:.contain)
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
                    Text(record.kcmc ?? "—").font(.title3.weight(.semibold))
                    Text(record.jxbmc ?? "").font(.caption).foregroundStyle(.secondary)
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
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    @ViewBuilder private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty, value != "--" {
            LabeledContent(title) { Text(value).multilineTextAlignment(.trailing) }
        }
    }
}
