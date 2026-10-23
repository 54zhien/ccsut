import SwiftUI

struct ScheduleView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var courseFont: CGFloat = 12
    @State private var bundle: ScheduleBundle?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var selectedWeek = 1
    @State private var currentWeek = 1
    @State private var didPickWeek = false
    @State private var referenceDate: Date?
    @State private var detail: ScheduleSlot?
    @State private var choosing: ScheduleCell?
    private let railWidth: CGFloat = 44
    private let headerHeight: CGFloat = 52
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if bundle?.isEmpty == false { termSummary; weekBar }
                if isLoading && bundle == nil {
                    Spacer()
                    ProgressView("加载课表…")
                    Spacer()
                } else if let errorText, bundle == nil {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: { Text(errorText) } actions: {
                        Button("重试") { Task { await load(force: true) } }
                    }
                } else if let bundle, !bundle.isEmpty {
                    timetable
                } else {
                    ContentUnavailableView {
                        Label("暂无课表", systemImage: "calendar.badge.exclamationmark")
                    } description: { Text("当前学期还没有排课数据。") } actions: {
                        Button("重新加载") { Task { await load(force: true) } }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("课表")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await load(force: true) } } label: {
                        if isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityLabel("刷新课表")
                    .disabled(isLoading)
                    AccountButton()
                }
            }
            .refreshable { await load(force: true) }
            .task { if bundle == nil { await load() } }
            .sheet(item: $detail) { slot in
                ScheduleDetailSheet(slot: slot)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(26)
            }
            .confirmationDialog("此时段的课程", isPresented: Binding(
                get: { choosing != nil }, set: { if !$0 { choosing = nil } }
            ), presenting: choosing) { cell in
                ForEach(cell.courses) { slot in
                    Button(choiceLabel(slot)) { detail = slot; choosing = nil }
                }
                Button("取消", role: .cancel) { choosing = nil }
            } message: { _ in Text("此时段有多条安排，请选择查看。") }
        }
    }

    private var termSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(bundle?.title ?? "")
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            if selectedWeek != currentWeek {
                Button("回到本周") { selectWeek(currentWeek) }
                    .font(.caption.weight(.medium)).frame(minHeight: 44)
            } else {
                Text("第 \(selectedWeek) 周").font(.subheadline.weight(.medium).monospacedDigit())
            }
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 20)
    }

    private var maxWeek: Int { max(18, bundle?.slots.flatMap(\.weeks).max() ?? 18, currentWeek) }

    private func selectWeek(_ week: Int) {
        didPickWeek = true
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { selectedWeek = week }
    }

    private var weekBar: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(1...maxWeek, id: \.self) { week in
                            Button { selectWeek(week) } label: {
                                HStack(spacing: 3) {
                                    Text("\(week)").font(.subheadline.weight(.semibold).monospacedDigit())
                                    Text("周").font(.caption)
                                }
                                .frame(width: 54, height: 44)
                                .foregroundStyle(week == selectedWeek ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(week == selectedWeek ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                            .overlay(alignment: .bottom) {
                                if week == currentWeek && week != selectedWeek {
                                    Circle().fill(Color.accentColor).frame(width: 4, height: 4).padding(.bottom, 4)
                                }
                            }
                            .accessibilityLabel("第 \(week) 周\(week == currentWeek ? "，本周" : "")")
                            .accessibilityAddTraits(week == selectedWeek ? [.isSelected] : [])
                            .id(week)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .onChange(of: selectedWeek) { _, week in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { proxy.scrollTo(week, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(selectedWeek, anchor: .center) }
            }
        }
    }

    private var cells: [ScheduleCell] { SchedulePresentation.cells(bundle?.slots ?? [], week: selectedWeek) }

    private func choiceLabel(_ slot: ScheduleSlot) -> String {
        let weeks = slot.weeks.isEmpty ? "周次未标注" : "第 \(WeekParser.compress(slot.weeks.sorted())) 周"
        let title = slot.teacher.isEmpty ? slot.course : "\(slot.course)（\(slot.teacher)）"
        return "\(title) · \(slot.room) · 第 \(slot.startPeriod)–\(slot.endPeriod) 节 · \(weeks)"
    }

    private var timetable: some View {
        GeometryReader { geo in
            let minColumn: CGFloat = dynamicTypeSize.isAccessibilitySize ? max(94, courseFont * 4) : 42
            let colWidth = max(minColumn, (geo.size.width - railWidth) / 7)
            let rowHeight = dynamicTypeSize.isAccessibilitySize ? max(180, courseFont * 10) : max(116, min(148, (geo.size.height - headerHeight - 16) / 4))
            let width = railWidth + colWidth * 7
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    weekdayHeader(colWidth: colWidth)
                    ScrollViewReader { verticalProxy in
                      ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(1...4, id: \.self) { section in
                                HStack(alignment: .top, spacing: 0) {
                                    periodLabel(section, height: rowHeight)
                                    ForEach(1...7, id: \.self) { day in
                                        timetableCell(day: day, section: section, width: colWidth, height: rowHeight)
                                    }
                                }
                                .frame(height: rowHeight)
                                .id(section)
                            }
                        }
                        .padding(.bottom, 88)
                      }
                      .scrollIndicators(.hidden)
                      .onAppear {
                          if InterfacePreview.page == "bottom" { verticalProxy.scrollTo(4, anchor: .bottom) }
                      }
                    }
                }
                .frame(width: width, height: geo.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 12)
    }

    private func weekdayHeader(colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 5) {
                if let monday = date(for: 1) {
                    Text("\(calendar.component(.month, from: monday))月").font(.system(size: 12, weight: .medium))
                }
                Text("节次").font(.system(size: 10, weight: .medium))
            }
                .foregroundStyle(Color.primary.opacity(0.6))
                .frame(width: railWidth, height: headerHeight)
            ForEach(1...7, id: \.self) { day in
                let today = isToday(day)
                VStack(spacing: 5) {
                    Text(weekdays[day - 1]).font(.system(size: 11, weight: .medium))
                    if let date = date(for: day) {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 14, weight: today ? .bold : .medium).monospacedDigit())
                    }
                }
                .foregroundStyle(today ? (colorScheme == .dark ? Color(red: 0.42, green: 0.64, blue: 1) : Color.accentColor) : Color.primary.opacity(day > 5 ? 0.65 : 0.8))
                .frame(width: colWidth - 4, height: headerHeight - 6)
                .background(today ? Color.accentColor.opacity(0.09) : .clear, in: .rect(cornerRadius: 12))
                .frame(width: colWidth, height: headerHeight)
                .accessibilityLabel("\(weekdays[day - 1])\(today ? "，今天" : "")")
            }
        }
    }

    private func periodLabel(_ section: Int, height: CGFloat) -> some View {
        VStack(spacing: 5) {
            Text(String(format: "%02d", section))
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(section * 2 - 1)–\(section * 2)节")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Color.primary.opacity(0.6))
            if section == 1 || section == 3 {
                Text(section == 1 ? "上午" : "下午")
                    .font(.system(size: 9)).foregroundStyle(.tertiary).padding(.top, 2)
            }
        }
        .padding(.top, 13)
        .frame(width: railWidth, height: height, alignment: .top)
        .accessibilityLabel("第 \(section * 2 - 1) 至 \(section * 2) 节")
    }

    private func timetableCell(day: Int, section: Int, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isToday(day) ? Color.accentColor.opacity(0.025) : Color(.secondarySystemGroupedBackground).opacity(0.45))
            if let cell = cells.first(where: { $0.weekday == day && $0.section == section }), let slot = cell.courses.first {
                courseCard(slot, count: cell.courses.count) {
                    if cell.courses.count == 1 { detail = slot } else { choosing = cell }
                }
            }
        }
        .frame(width: width - 4, height: height - 6)
        .frame(width: width, height: height, alignment: .top)
    }

    private func courseCard(_ slot: ScheduleSlot, count: Int, action: @escaping () -> Void) -> some View {
        let tint = Self.tint(for: slot.course)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.course).font(.system(size: courseFont, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.primary : tint)
                    .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 4)
                if count > 1 {
                    Text("另\(count - 1)项").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                if !slot.room.isEmpty {
                    Text(slot.room).font(.system(size: max(10, courseFont - 2), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? Color.secondary : tint.opacity(0.9))
                        .lineLimit(slot.room.unicodeScalars.allSatisfy { $0.isASCII } ? 1 : 3)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tint.opacity(colorScheme == .dark ? 0.23 : 0.10), in: .rect(cornerRadius: 12))
            .overlay(alignment: .leading) {
                Capsule().fill(tint.opacity(0.75)).frame(width: 3).padding(.vertical, 12)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.course)，\(slot.room)，\(slot.teacher)\(count > 1 ? "，此时段共\(count)条安排" : "")")
        .accessibilityHint(count > 1 ? "选择此时段的课程" : "查看课程详情")
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(for day: Int) -> Date? {
        guard let referenceDate else { return nil }
        let weekday = (calendar.component(.weekday, from: referenceDate) + 5) % 7
        let offset = (selectedWeek - currentWeek) * 7 + day - 1 - weekday
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: referenceDate))
    }

    private func isToday(_ day: Int) -> Bool {
        guard selectedWeek == currentWeek, let referenceDate, let date = date(for: day) else { return false }
        return calendar.isDate(date, inSameDayAs: referenceDate)
    }

    private func load(force: Bool = false) async {
        #if DEBUG
        if InterfacePreview.enabled {
            bundle = InterfacePreview.schedule
            currentWeek = 7
            selectedWeek = 7
            didPickWeek = true
            referenceDate = ISO8601DateFormatter().date(from: "2026-10-23T09:41:00+08:00")
            if InterfacePreview.page == "course" { detail = cells.first?.courses.first }
            if InterfacePreview.page == "conflict" { choosing = cells.first(where: { $0.courses.count > 1 }) }
            return
        }
        #endif
        guard !isLoading else { return }
        if !force, bundle != nil { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let initData = try await APIClient.shared.electiveInit()
            let term = initData.xkxnxq ?? "2026-2027-1"
            if let week = try? await APIClient.shared.currentTeachingWeek(), week > 0 {
                currentWeek = week
                referenceDate = Date()
                if !didPickWeek { selectedWeek = week; didPickWeek = true }
            }
            let xhid = try await APIClient.shared.scheduleXhid(xnxq: term)
            let items = try await APIClient.shared.scheduleItems(xnxq: term, xhid: xhid)
            bundle = ScheduleBundle(title: term, slots: items.map(\.slot).filter { !$0.course.isEmpty }, periods: [1, 2, 3, 4])
        } catch let error as APIError {
            if case .notLoggedIn = error {
                await session.refresh()
                errorText = "会话过期，已尝试续期，请下拉刷新"
            } else { errorText = error.localizedDescription }
        } catch { errorText = error.localizedDescription }
    }

    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.33, blue: 0.62),
        Color(red: 0.16, green: 0.46, blue: 0.42),
        Color(red: 0.54, green: 0.34, blue: 0.24),
        Color(red: 0.45, green: 0.33, blue: 0.56),
        Color(red: 0.56, green: 0.37, blue: 0.17),
    ]
    private static func tint(for name: String) -> Color {
        palette[name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % palette.count]
    }
}
