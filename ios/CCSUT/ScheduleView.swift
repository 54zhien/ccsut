import SwiftUI

struct ScheduleView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.deviceCornerRadius) private var deviceCornerRadius
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var courseFont: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var timeFont: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var dayFont: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var dateFont: CGFloat = 14
    @ScaledMetric(relativeTo: .headline) private var periodFont: CGFloat = 17
    @State private var bundle: ScheduleBundle?
    @State private var isLoading = false
    @State private var loadGate = PageLoadGate()
    @State private var errorText: String?
    @State private var selectedWeek = 1
    @State private var currentWeek: Int?
    @State private var weekUnavailable = false
    @State private var didPickWeek = false
    @State private var referenceDate: Date?
    @State private var weekSnapshot: TeachingWeekSnapshot?
    @State private var verifiedAccount: String?
    @State private var bundleGeneration: UInt64?
    @State private var calendarCheckedAt = Date()
    @State private var detail: ScheduleSlot?
    @State private var choosing: ScheduleCell?
    @State private var pendingDetail: ScheduleSlot?
    @State private var headerScrollOffset: CGFloat = 0
    @State private var previewRefreshCount = 0
    private var railWidth: CGFloat { max(48, timeFont * 4.5) }
    private var headerHeight: CGFloat { max(52, dayFont + dateFont + 24) }
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    private let classTimes = [("8:20", "10:00"), ("10:20", "12:00"),
                              ("14:00", "15:40"), ("16:00", "17:40")]

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            if let bundle, !bundle.isEmpty {
                                VStack(spacing: 16) {
                                    if let errorText {
                                        PageStatusNotice(message: errorText) { Task { await load(force: true) } }
                                    }
                                    weekBar().id("page-top")
                                    VStack(spacing: 8) {
                                        termSummary
                                        timetable(viewport: viewport.size)
                                    }
                                    .padding(.top, 12)
                                    .padding(.bottom, 12)
                                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
                                    .clipShape(.rect(cornerRadius: 28))
                                    .padding(.horizontal, 12)
                                    .id("timetable-panel")
                                    Color.clear.frame(height: 1).id("page-end")
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 20)
                                .frame(maxWidth: .infinity)
                            } else {
                                Group {
                                    if isLoading {
                                        ProgressView("加载课表…")
                                    } else if errorText != nil {
                                        ContentUnavailableView {
                                            Label(AppMessages.loadFailure, systemImage: "wifi.exclamationmark")
                                        } description: { EmptyView() } actions: {
                                            Button("重试") { Task { await load(force: true) } }
                                        }
                                    } else {
                                        ContentUnavailableView {
                                            Label("暂无课表", systemImage: "calendar.badge.exclamationmark")
                                        } description: { Text("当前学期还没有排课数据。") } actions: {
                                            Button("重新加载") { Task { await load(force: true) } }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                            }
                        }
                        .pageRefreshControl { await load(force: true) }
                    }
                    .accessibilityIdentifier("schedule-scroll")
                    .scrollIndicators(.hidden)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
                    } action: { _, offset in headerScrollOffset = offset }
                    .task {
                        #if DEBUG
                        if InterfacePreview.page == "bottom" || InterfacePreview.page == "header-hidden" {
                            try? await Task.sleep(for: .milliseconds(300))
                            proxy.scrollTo("page-end", anchor: .bottom)
                        } else if InterfacePreview.page == "header-motion" {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo("page-end", anchor: .bottom) }
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo("page-top", anchor: .top) }
                        }
                        #endif
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("schedule-surface")
            .background(Color(.systemGroupedBackground))
            .nagiPageChrome(title: "课表", scrollOffset: headerScrollOffset) {
                AccountButton()
            }
            .task { if bundle == nil { await load() } }
            .task {
                guard !InterfacePreview.enabled else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    if scenePhase == .active { await updateCalendar() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await updateCalendar(refresh: true) } }
            }
            .overlay(alignment: .bottomTrailing) {
                if InterfacePreview.page == "interactions" {
                    VStack {
                        Text("\(previewRefreshCount)").accessibilityIdentifier("refresh-count")
                        Text("\(deviceCornerRadius)").accessibilityIdentifier("device-corner-radius")
                    }
                    .padding(.bottom, 100)
                }
            }
            .sheet(item: $detail) { slot in
                ScheduleDetailSheet(slot: slot)
                    .presentationDetents([.medium])
                    .presentationContentInteraction(.scrolls)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(SheetLayout.cornerRadius(deviceCornerRadius))
            }
            .sheet(item: $choosing, onDismiss: {
                detail = pendingDetail
                pendingDetail = nil
            }) { cell in
                NavigationStack {
                    List(cell.courses) { slot in
                        Button {
                            pendingDetail = slot
                            choosing = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(slot.course).font(.headline).foregroundStyle(.primary)
                                Text([slot.teacher, slot.room].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text("第 \(slot.startPeriod)–\(slot.endPeriod) 节 · \(slot.weeks.isEmpty ? "周次未标注" : "第 \(WeekParser.compress(slot.weeks.sorted())) 周")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .navigationTitle("此时段的课程")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { choosing = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(deviceCornerRadius)
            }
        }
    }

    private var termSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SchedulePresentation.termTitle(bundle?.title ?? ""))
                    .font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if let currentWeek, selectedWeek != currentWeek {
                    Button("回到本周") { selectWeek(currentWeek) }
                        .font(.caption.weight(.medium)).frame(minHeight: 44)
                }
            }
            if weekUnavailable {
                Text("本周周次暂未获取，请下拉重试")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 28)
        .padding(.horizontal, 16)
    }

    private var maxWeek: Int { max(18, bundle?.slots.flatMap(\.weeks).max() ?? 18, currentWeek ?? 1) }

    private func selectWeek(_ week: Int) {
        didPickWeek = true
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            selectedWeek = week
        }
    }

    private func weekBar() -> some View {
        WeekSelector(
            selectedWeek: $selectedWeek,
            currentWeek: currentWeek,
            maxWeek: maxWeek,
            onSelectWeek: selectWeek
        )
    }

    private var cells: [ScheduleCell] { SchedulePresentation.cells(bundle?.slots ?? [], week: selectedWeek) }

    private func timetable(viewport: CGSize) -> some View {
        let minColumn: CGFloat = dynamicTypeSize.isAccessibilitySize ? max(94, courseFont * 4) : max(42, dayFont * 3.5)
        let width = max(viewport.width - 32, railWidth + 7 * minColumn)
        let colWidth = (width - railWidth) / 7
        let rowHeight = dynamicTypeSize.isAccessibilitySize ? max(180, courseFont * 10) : max(116, min(136, (viewport.height - 180) / 4))
        return ScrollView(.horizontal) {
            VStack(spacing: 0) {
                weekdayHeader(colWidth: colWidth)
                ForEach(1...4, id: \.self) { section in
                    HStack(alignment: .top, spacing: 0) {
                        periodLabel(section, height: rowHeight)
                        ForEach(1...7, id: \.self) { day in
                            timetableCell(day: day, section: section, width: colWidth, height: rowHeight)
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
            .frame(width: width)
        }
        .frame(height: headerHeight + rowHeight * 4)
        .padding(.horizontal, 4)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func weekdayHeader(colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 5) {
                if let monday = date(for: 1) {
                    Text("\(calendar.component(.month, from: monday))月").font(.system(size: dayFont, weight: .medium))
                }
                Text("节次").font(.system(size: timeFont, weight: .medium))
            }
                .foregroundStyle(.secondary)
                .frame(width: railWidth, height: headerHeight)
            ForEach(1...7, id: \.self) { day in
                let today = isToday(day)
                VStack(spacing: 5) {
                    Text(weekdays[day - 1]).font(.system(size: dayFont, weight: .medium))
                    if let date = date(for: day) {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: dateFont, weight: today ? .bold : .medium).monospacedDigit())
                    }
                }
                .foregroundStyle(today ? Color.accentColor : Color.primary.opacity(day > 5 ? 0.65 : 0.8))
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
                .font(.system(size: periodFont, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(section * 2 - 1)–\(section * 2)节")
                .font(.system(size: timeFont, weight: .medium)).foregroundStyle(.secondary)
            VStack(spacing: 2) {
                Text(classTimes[section - 1].0)
                Text(classTimes[section - 1].1)
            }
            .font(.system(size: timeFont).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.top, 3)
            if section == 1 || section == 3 {
                Text(section == 1 ? "上午" : "下午")
                    .font(.system(size: timeFont)).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
        .padding(.top, 13)
        .frame(width: railWidth, height: height, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(section * 2 - 1) 至 \(section * 2) 节，\(classTimes[section - 1].0) 至 \(classTimes[section - 1].1)")
        .accessibilityIdentifier("schedule-period-\(section)")
    }

    private func timetableCell(day: Int, section: Int, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isToday(day) ? Color.accentColor.opacity(0.025) :
                        (colorScheme == .dark ? Color.white.opacity(0.025) : Color(.systemGroupedBackground).opacity(0.7)))
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
                    Text("另\(count - 1)项").font(.system(size: timeFont, weight: .semibold)).foregroundStyle(.secondary)
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
        guard let referenceDate, let currentWeek else { return nil }
        let weekday = (calendar.component(.weekday, from: referenceDate) + 5) % 7
        let offset = (selectedWeek - currentWeek) * 7 + day - 1 - weekday
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: referenceDate))
    }

    private func isToday(_ day: Int) -> Bool {
        guard selectedWeek == currentWeek, let referenceDate, let date = date(for: day) else { return false }
        return calendar.isDate(date, inSameDayAs: referenceDate)
    }

    private func load(force: Bool = false) async {
        await loadGate.run { await fetch(force: force) }
    }

    private func fetch(force: Bool) async {
        #if DEBUG
        if InterfacePreview.enabled {
            if InterfacePreview.page == "loading" {
                isLoading = true
                defer { isLoading = false }
                try? await Task.sleep(for: .seconds(30))
                return
            }
            if force { previewRefreshCount += 1 }
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
        let generation = CookieJar.generation
        if let bundleGeneration, bundleGeneration != generation { clearAccountData() }
        do {
            let context = try await APIClient.shared.timetableContext()
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            let term = context.term
            if let previousTerm = bundle?.title, previousTerm != term {
                currentWeek = nil
                referenceDate = nil
                weekSnapshot = nil
                weekUnavailable = true
                didPickWeek = false
                selectedWeek = 1
            }
            let profile = try await APIClient.shared.authenticatedProfile()
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            guard let account = profile.xsxh?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !account.isEmpty else { throw APIError.notLoggedIn }
            if let verifiedAccount, verifiedAccount != account { clearAccountData() }
            let cacheKey = "ccsut.teachingWeek.v1"
            var candidate: TeachingWeekSnapshot?
            if let data = UserDefaults.standard.data(forKey: cacheKey),
               let saved = try? JSONDecoder().decode(TeachingWeekSnapshot.self, from: data),
               saved.week(on: Date(), term: term, account: account) != nil {
                candidate = saved
            }
            do {
                let week = try await APIClient.shared.currentTeachingWeek()
                guard CookieJar.generation == generation, !Task.isCancelled else { return }
                candidate = TeachingWeekSnapshot(term: term, account: account, week: week, verifiedAt: Date())
            } catch {
                if error is CancellationError { throw error }
                if let apiError = error as? APIError, case .notLoggedIn = apiError { throw error }
            }
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            let items = try await APIClient.shared.scheduleItems(xnxq: term, xhid: context.studentKey)
            let slots = try ScheduleValidation.slots(items)
            guard CookieJar.generation == generation, !Task.isCancelled else { return }
            bundle = ScheduleBundle(title: term, slots: slots, periods: [1, 2, 3, 4])
            verifiedAccount = account
            bundleGeneration = generation
            weekSnapshot = candidate
            rebaseCurrentWeek(at: Date())
            if let candidate, let data = try? JSONEncoder().encode(candidate) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
        } catch {
            guard CookieJar.generation == generation, !(error is CancellationError) else { return }
            rebaseCurrentWeek(at: Date())
            if let apiError = error as? APIError, case .notLoggedIn = apiError {
                await session.refresh()
                guard CookieJar.generation == generation else { return }
                errorText = "会话需要更新，请重试。"
            } else {
                errorText = bundle == nil ? error.localizedDescription : "课表更新失败，当前显示上次完整的课表，请重试"
            }
        }
    }

    private func rebaseCurrentWeek(at date: Date) {
        if let bundleGeneration, bundleGeneration != CookieJar.generation { clearAccountData() }
        guard let term = bundle?.title, let account = verifiedAccount,
              let week = weekSnapshot?.week(on: date, term: term, account: account) else {
            currentWeek = nil
            referenceDate = nil
            weekUnavailable = true
            return
        }
        currentWeek = week
        referenceDate = date
        weekUnavailable = false
        if !didPickWeek { selectedWeek = week }
    }

    private func clearAccountData() {
        bundle = nil
        bundleGeneration = nil
        verifiedAccount = nil
        weekSnapshot = nil
        currentWeek = nil
        referenceDate = nil
        weekUnavailable = true
        selectedWeek = 1
        didPickWeek = false
        detail = nil
        choosing = nil
        pendingDetail = nil
    }

    private func updateCalendar(refresh: Bool = false) async {
        guard !InterfacePreview.enabled else { return }
        let now = Date()
        let changedDay = !calendar.isDate(now, inSameDayAs: calendarCheckedAt)
        calendarCheckedAt = now
        rebaseCurrentWeek(at: now)
        if refresh || changedDay { await load(force: true) }
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

private struct WeekSelector: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedWeek: Int
    let currentWeek: Int?
    let maxWeek: Int
    let onSelectWeek: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(1...maxWeek, id: \.self) { week in
                        Button {
                            onSelectWeek(week)
                        } label: {
                            Text(week == currentWeek ? "本周" : "第 \(week) 周")
                                .font(.subheadline.weight(week == selectedWeek ? .semibold : .medium))
                                .monospacedDigit()
                                .padding(.horizontal, 14)
                                .frame(minWidth: 84, minHeight: 44)
                                .foregroundStyle(week == selectedWeek ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(week == selectedWeek ? .regular.tint(.accentColor.opacity(0.18)) : .regular, in: .capsule)
                        .overlay(alignment: .bottom) {
                            if week == currentWeek && week != selectedWeek {
                                Circle().fill(Color.accentColor).frame(width: 4, height: 4).padding(.bottom, 4)
                            }
                        }
                        .accessibilityLabel(week == currentWeek ? "本周" : "第 \(week) 周")
                        .accessibilityAddTraits(week == selectedWeek ? [.isSelected] : [])
                        .id(week)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            // Automatic view-aligned settling overrides the requested center on iOS 26.
            .onAppear { proxy.scrollTo(selectedWeek, anchor: .center) }
            .onChange(of: selectedWeek) { _, week in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    proxy.scrollTo(week, anchor: .center)
                }
            }
        }
    }
}
