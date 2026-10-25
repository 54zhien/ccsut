//
//  ElectiveView.swift
//  CCSUT
//
//  选课 · 教学班浏览
//
//  数据来源：/admin/xsd/xk/listjxbDataV2（JSON，实测 71 KB）
//  展示教学班并通过官方接口执行选课/退课；写操作只使用已验证的完整快照。
//

import SwiftUI

struct ElectiveView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.deviceCornerRadius) private var deviceCornerRadius

    var onLoaded: (_ selectedCount: Int, _ term: String) -> Void = { _, _ in }
    var onSummaryInvalidated: () -> Void = {}

    @State private var initData: ElectiveInit?
    @State private var electiveState = ElectiveState<TeachingClass>()
    @State private var enrolledModel = makeEnrolledModel()
    @State private var keyword = ""
    @State private var selectedFilter: Filter = .all
    @State private var isLoading = false
    @State private var activeLoadRequests = 0
    @State private var loadGate = PageLoadGate()
    @State private var errorText: String?
    @State private var detail: TeachingClass?
    @State private var enrolledDetail: EnrolledCourse?
    @State private var pending: PendingAction?
    @State private var workingId: String?
    @State private var actionMessage: String?
#if DEBUG
    @State private var previewPublicationCount = 0
    @State private var previewCatalogFailureInjected = false
#endif

    private var classes: [TeachingClass] { electiveState.snapshot?.courses ?? [] }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case selected = "已选"
        case available = "可选"
        case free = "有余量"
        var id: String { rawValue }
    }

    var body: some View {
        PageScrollSurface(refresh: { await load(force: true) }) { viewport, _ in
            VStack(spacing: 0) {
                if isLoading && classes.isEmpty && enrolledModel.context == nil {
                    ProgressView("拉取教学班…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, minHeight: classes.isEmpty ? viewport.height : 0)
        }
        .scrollDismissesKeyboard(.immediately)
        .academicDetailChrome(title: "选课")
#if DEBUG
        .overlay(alignment: .topTrailing) {
            PageRefreshPublicationDiagnostics(count: previewPublicationCount)
        }
#endif
        .task {
            if classes.isEmpty { await load() }
        }
        .onChange(of: enrolledModel.currentSummary) { _, summary in
            if let summary { onLoaded(summary.count, summary.term) }
            else { onSummaryInvalidated() }
        }
        .sheet(item: $detail) { item in
            CourseDetailSheet(item: item, actionBlockReason: actionBlockReason(for: item))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(deviceCornerRadius)
        }
        .sheet(item: $enrolledDetail) { item in
            EnrolledCourseDetail(record:item)
                .presentationDetents([.medium,.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(deviceCornerRadius)
        }
    }

    // MARK: 列表

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("课程名 / 教师", text: $keyword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !keyword.isEmpty {
                Button { keyword = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private var list: some View {
        LazyVStack(spacing: 16) {
            VStack(spacing: 14) {
                searchField
                filterBar
                if selectedFilter == .selected { enrolledHeader }
                else if let initData { header(initData) }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))

            if selectedFilter == .selected {
                enrolledList
            } else {
                if let errorText {
                    PageStatusNotice(message:errorText) { Task { await load(force:true) } }
                }
                ForEach(filtered) { item in catalogCard(item) }
                if classes.isEmpty {
                    ContentUnavailableView(errorText == nil ? "当前没有可选课程" : AppMessages.loadFailure,
                                           systemImage:errorText == nil ? "tray" : "exclamationmark.icloud")
                }
            }

            if selectedFilter != .selected && !classes.isEmpty && filtered.isEmpty {
                ContentUnavailableView {
                    Label("未找到课程", systemImage: "magnifyingglass")
                } description: {
                    Text("当前搜索或筛选条件没有匹配的课程。")
                } actions: {
                    Button("重置搜索与筛选", action: resetSearchAndFilters)
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("清除搜索文字并切换为全部课程")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(
            pending.map { $0.enrolling ? "确认选课？" : "确认退课？" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { action in
            Button(action.enrolling ? "选课" : "退课", role: action.enrolling ? nil : .destructive) {
                Task { await perform(action) }
            }
            Button("取消", role: .cancel) { pending = nil }
        } message: { action in
            Text(action.title ?? "")
        }
        .alert("操作结果", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("好", role: .cancel) { actionMessage = nil }
        } message: {
            Text(AppMessages.readable(actionMessage ?? ""))
        }
    }

    private func header(_ data: ElectiveInit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(SchedulePresentation.termTitle(data.xkxnxq ?? "—"), systemImage: "calendar")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(data.xsxm ?? "—", systemImage: "person")
                Spacer(minLength: 8)
                if let summary = enrolledModel.currentSummary, summary.term == data.xkxnxq {
                    Label("\(summary.count) 已选", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text("\(filtered.count) 门").monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var selectedCount: Int {
        selectedFilter == .selected ? (enrolledModel.snapshot?.count ?? 0) : (enrolledModel.currentSummary?.count ?? 0)
    }

    private var enrolledHeader: some View {
        VStack(alignment:.leading,spacing:8) {
            if let context = enrolledModel.context {
                Menu {
                    ForEach(context.terms,id:\.self) { term in
                        Button(SchedulePresentation.termTitle(term)) {
                            pending = nil; detail = nil; enrolledDetail = nil
                            Task { await enrolledModel.load(term:term) }
                        }
                        .accessibilityIdentifier("enrolled-term-\(term)")
                    }
                } label: {
                    Label(SchedulePresentation.termTitle(enrolledModel.selectedTerm ?? context.defaultTerm),systemImage:"calendar")
                        .fixedSize(horizontal:false,vertical:true)
                }
                .accessibilityIdentifier("enrolled-term-menu")
                .disabled(electiveState.isActionInProgress)
            }
            HStack {
                Text("含自主选课与配课")
                Spacer(minLength:8)
                if let snapshot = enrolledModel.snapshot { Text("\(snapshot.count) 门").monospacedDigit() }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth:.infinity,alignment:.leading)
    }

    private var filteredEnrolled: [EnrolledCourse] {
        let kw = keyword.trimmingCharacters(in:.whitespacesAndNewlines)
        return (enrolledModel.snapshot ?? []).filter { item in
            kw.isEmpty || "\(item.kcmc ?? "") \(item.rkjs ?? "") \(item.kcbh ?? "")".localizedCaseInsensitiveContains(kw)
        }
    }

    @ViewBuilder private var enrolledList: some View {
        if enrolledModel.isLoading {
            ProgressView("读取完整已选结果…")
        }
        if let message = enrolledModel.errorText {
            VStack(spacing:8) {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("enrolled-read-error")
                if enrolledModel.snapshot != nil { Text("当前显示上次结果，尚未重新核实").font(.caption).foregroundStyle(.secondary) }
                Button("重试读取已选") { Task { await enrolledModel.load(refreshContext:true) } }
                    .buttonStyle(.bordered)
            }
        }
        ForEach(filteredEnrolled) { record in
            if let item = enrolledModel.currentCourse(for:record,catalog:electiveState,catalogTerm:initData?.xkxnxq) {
                catalogCard(item)
            } else {
                EnrolledCourseCard(record:record,readOnlyReason:enrolledReadOnlyReason)
                    .contentShape(.rect)
                    .onTapGesture { enrolledDetail = record }
            }
        }
        if !enrolledModel.isLoading && enrolledModel.errorText == nil && filteredEnrolled.isEmpty {
            ContentUnavailableView {
                Label(enrolledModel.snapshot?.isEmpty == true ? "该学期没有已选课程" : "未找到课程",systemImage:"tray")
            } description: {
                Text(enrolledModel.snapshot?.isEmpty == true ? "教务系统返回该学期暂无个人课程。" : "请尝试其他课程名或教师。")
            }
        }
    }

    private var enrolledReadOnlyReason: String {
        if !enrolledModel.isVerified || isLoading { return "课程结果尚未验证完成，仅供查看" }
        if enrolledModel.selectedTerm != enrolledModel.context?.defaultTerm { return "历史学期课程，仅供查看" }
        return "仅供查看，下拉刷新可核实操作条件"
    }

    private func catalogCard(_ item: TeachingClass) -> some View {
        let blockReason = actionBlockReason(for:item)
        return ClassCard(item:item,
            onAction:{ pending = PendingAction(courseID:item.id,title:item.kcmc,enrolling:!item.isSelected) },
            isWorking:workingId == item.id,canPerformAction:blockReason == nil,actionBlockReason:blockReason)
            .contentShape(.rect).onTapGesture { detail = item }
    }

    private static func makeEnrolledModel() -> EnrolledCoursesModel {
        EnrolledCoursesModel(generation:{ CookieJar.generation },contextLoader:{ generation in
            #if DEBUG
            if InterfacePreview.enabled { return InterfacePreview.enrolledContext }
            #endif
            return try await APIClient.shared.enrolledCoursesContext(expectedGeneration:generation)
        },coursesLoader:{ term,generation in
            #if DEBUG
            if InterfacePreview.enabled {
                if InterfacePreview.selectedReadFailure { throw APIError.empty }
                return InterfacePreview.enrolledCourses(term:term)
            }
            #endif
            return try await APIClient.shared.enrolledCourses(term:term,expectedGeneration:generation)
        })
    }

    /// 执行选课/退课
    private func perform(_ action: PendingAction) async {
        pending = nil
        let generation = CookieJar.generation
        if let ownerGeneration = electiveState.snapshotGeneration, ownerGeneration != generation {
            _ = handleCookieGenerationChange(expected: ownerGeneration)
            actionMessage = "登录账号已切换，旧课程状态已清除；请重新加载后再操作"
            return
        }
        guard !isLoading else {
            actionMessage = "课程刷新仍在完成，请等待刷新后重新确认"
            return
        }
        let kind: ElectiveActionKind = action.enrolling ? .enroll : .drop
        let decision = electiveState.beginAction(for: action.courseID, kind: kind, generation: generation)
        guard case .allowed(let pcid) = decision else {
            actionMessage = actionBlockMessage(decision)
            return
        }

        workingId = action.courseID
        defer {
            workingId = nil
            electiveState.finishAction()
        }

        do {
            guard !handleCookieGenerationChange(expected: generation) else {
                actionMessage = "登录状态已切换，操作结果未确认；请先刷新当前账号的课程"
                return
            }
            let msg = action.enrolling
                ? try await APIClient.shared.enroll(jxbid: action.courseID, pcid: pcid,
                                                    expectedGeneration: generation)
                : try await APIClient.shared.dropClass(jxbid: action.courseID, pcid: pcid,
                                                       expectedGeneration: generation)
            guard !handleCookieGenerationChange(expected: generation) else {
                actionMessage = "登录状态已切换，操作结果未确认；请先刷新当前账号的课程"
                return
            }
            await load(force: true, reconcileMutation: true, expectedGeneration: generation)
            guard !handleCookieGenerationChange(expected: generation) else {
                actionMessage = "登录状态已切换，操作结果未确认；请先刷新当前账号的课程"
                return
            }
            actionMessage = hasVerifiedSnapshot(for: generation) && errorText == nil
                ? msg
                : "操作已返回成功，但课程状态刷新失败；请核对页面提示后再操作"
        } catch {
            guard !handleCookieGenerationChange(expected: generation) else {
                actionMessage = "登录状态已切换，操作结果未确认；旧课程数据已清除"
                return
            }
            if let e = error as? APIError {
                switch e {
                case .notLoggedIn:
                    await renewAuthenticationAndReconcile(expectedGeneration: generation)
                case .business(_, let text):
                    if ElectiveMutationRecovery.isAuthenticationRejection(text) {
                        await renewAuthenticationAndReconcile(expectedGeneration: generation)
                    } else {
                        await load(force: true, reconcileMutation: true, expectedGeneration: generation)
                        guard !handleCookieGenerationChange(expected: generation) else {
                            actionMessage = "登录状态已切换，旧课程数据已清除"
                            return
                        }
                        actionMessage = text
                    }
                default:
                    await load(force: true, reconcileMutation: true, expectedGeneration: generation)
                    guard !handleCookieGenerationChange(expected: generation) else {
                        actionMessage = "登录状态已切换，旧课程数据已清除"
                        return
                    }
                    actionMessage = "提交结果未知，已重新查询课程状态；请核对页面提示后再操作"
                }
            } else {
                await load(force: true, reconcileMutation: true, expectedGeneration: generation)
                guard !handleCookieGenerationChange(expected: generation) else {
                    actionMessage = "登录状态已切换，旧课程数据已清除"
                    return
                }
                actionMessage = "提交结果未知，已重新查询课程状态；请核对页面提示后再操作"
            }
        }
    }

    private func renewAuthenticationAndReconcile(expectedGeneration: UInt64) async {
        await session.refresh()
        guard !handleCookieGenerationChange(expected: expectedGeneration) else {
            actionMessage = "登录状态已切换，旧课程数据已清除；请重新加载当前账号"
            return
        }
        await load(force: true, refreshAuthentication: false, reconcileMutation: true,
                   expectedGeneration: expectedGeneration)
        guard !handleCookieGenerationChange(expected: expectedGeneration) else {
            actionMessage = "登录状态已切换，旧课程数据已清除；请重新加载当前账号"
            return
        }
        actionMessage = hasVerifiedSnapshot(for: expectedGeneration)
            ? "会话已续期并刷新课程，请重新确认选课或退课"
            : "会话已续期，但课程刷新未成功；当前已禁用操作，请重试"
    }

    private func hasVerifiedSnapshot(for generation: UInt64) -> Bool {
        electiveState.isSnapshotVerified && electiveState.snapshotGeneration == generation
    }

    /// A request from an old cookie generation must never keep or publish its account's data.
    private func handleCookieGenerationChange(expected: UInt64) -> Bool {
        let currentGeneration = CookieJar.generation
        enrolledModel.discardIfAccountChanged()
        let hasCurrentGenerationSnapshot = electiveState.snapshotGeneration == currentGeneration
        guard !ElectiveMutationRecovery.canContinueAfterAwait(
            expectedGeneration: expected,
            currentGeneration: currentGeneration,
            state: &electiveState
        ) else { return false }
        // A stale continuation must not wipe UI state already loaded for the new account.
        guard !hasCurrentGenerationSnapshot else { return true }
        initData = nil
        pending = nil
        detail = nil
        errorText = "登录账号已切换，旧课程数据已清除；请刷新验证当前账号"
        return true
    }

    private func actionBlockReason(for item: TeachingClass) -> String? {
        if isLoading { return "课程刷新仍在完成，请等待刷新后重新确认" }
        let kind: ElectiveActionKind = item.isSelected ? .drop : .enroll
        let decision = electiveState.actionDecision(for: item.id, kind: kind,
                                                    generation: CookieJar.generation)
        guard case .denied = decision else { return nil }
        return actionBlockMessage(decision)
    }

    private func resetSearchAndFilters() {
        withAnimation(.snappy(duration: 0.18)) {
            keyword = ""
            selectedFilter = .all
        }
    }

    private func actionBlockMessage(_ decision: ElectiveActionDecision) -> String {
        guard case .denied(let reason) = decision else { return "课程状态已变化，请重新确认" }
        switch reason {
        case .snapshotUnverified:
            return "课程数据尚未验证完成，请刷新后再操作"
        case .courseMissing:
            return "课程已不在当前列表，请刷新后重新选择"
        case .missingBatch:
            return "找不到这条课程所属的选课批次，请下拉刷新后重试"
        case .ambiguousBatch:
            return "这条课程出现在多个选课批次，无法确定操作批次；请在教务官方页面操作"
        case .unavailable:
            return "该课程当前不可选"
        case .full:
            return "该课程名额已满"
        case .alreadySelected:
            return "这条课程已选，请刷新后确认状态"
        case .notSelected:
            return "这条课程当前未选，无法退课；请刷新后确认状态"
        case .actionInProgress:
            return "已有选课或退课操作正在处理，请稍后再试"
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { f in
                    let on = f == selectedFilter
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { selectedFilter = f }
                    } label: {
                        HStack(spacing: 4) {
                            Text(f.rawValue)
                                .font(.caption.weight(.medium))
                            if f == .selected, selectedCount > 0 {
                                Text("\(selectedCount)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background((on ? Color("AccentForeground") : Color.accentColor)
                                        .opacity(0.15), in: .capsule)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            on ? AnyShapeStyle(Color.accentColor)
                               : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                            in: .capsule
                        )
                        .foregroundStyle(on ? Color("AccentForeground") : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.top, 2)
    }

    // MARK: 筛选

    private var filtered: [TeachingClass] {
        classes.filter { item in
            let kw = keyword.trimmingCharacters(in: .whitespaces)
            if !kw.isEmpty {
                let hay = "\(item.kcmc ?? "") \(item.teacher ?? "") \(item.kcid ?? "")"
                if !hay.localizedCaseInsensitiveContains(kw) { return false }
            }
            switch selectedFilter {
            case .all: return true
            case .selected: return item.isSelected
            case .available: return item.canSelect
            case .free: return !item.isFull
            }
        }
    }

    // MARK: 加载

    private func load(force: Bool = false, refreshAuthentication: Bool = true,
                      reconcileMutation: Bool = false,
                      expectedGeneration: UInt64? = nil) async {
        guard reconcileMutation || !electiveState.isActionInProgress else { return }
        if let expectedGeneration, handleCookieGenerationChange(expected: expectedGeneration) { return }
        activeLoadRequests += 1
        isLoading = true
        enrolledModel.invalidate()
        defer {
            activeLoadRequests -= 1
            isLoading = activeLoadRequests > 0
        }
        await loadGate.run {
            if let expectedGeneration,
               handleCookieGenerationChange(expected: expectedGeneration) { return }
            await fetch(force: force, refreshAuthentication: refreshAuthentication,
                        expectedGeneration: expectedGeneration)
            if let expectedGeneration, handleCookieGenerationChange(expected:expectedGeneration) { return }
            guard !Task.isCancelled else { return }
            let owner = CookieJar.generation
            await enrolledModel.load(refreshContext:force,catalogGeneration:hasVerifiedSnapshot(for:owner) ? owner : nil)
        }
    }

    private func fetch(force: Bool, refreshAuthentication: Bool,
                       expectedGeneration: UInt64? = nil) async {
        let generation = CookieJar.generation
        if let expectedGeneration, expectedGeneration != generation {
            _ = handleCookieGenerationChange(expected: expectedGeneration)
            return
        }
        if electiveState.refreshStarted(generation: generation) {
            initData = nil
            pending = nil
            detail = nil
        }
        #if DEBUG
        if InterfacePreview.enabled {
            if previewPublicationCount > 0 && ProcessInfo.processInfo.arguments.contains("--preview-controlled-refresh") {
                await PreviewRefreshCompletionGate.shared.waitForRelease()
            } else {
                try? await Task.sleep(for: InterfacePreview.refreshFixtureDelay)
            }
            guard !handleCookieGenerationChange(expected: generation), !Task.isCancelled else { return }
            if InterfacePreview.catalogReadFailureOnce && !previewCatalogFailureInjected {
                previewCatalogFailureInjected = true
                errorText = "教学班读取失败，请重试核实操作条件"
                electiveState.refreshFailed()
                return
            }
            errorText = nil
            let previewClasses = InterfacePreview.emptyPage ? [] : InterfacePreview.classes
            var builder = ElectiveSnapshotBuilder<TeachingClass>()
            builder.append(records(for: previewClasses))
            let snapshot = builder.snapshot
            let fixtureInit = InterfacePreview.electiveInit
            electiveState.publish(snapshot, generation: generation)
            guard !handleCookieGenerationChange(expected: generation), !Task.isCancelled else { return }
            initData = fixtureInit
            previewPublicationCount += 1
            return
        }
        #endif

        errorText = nil

        do {
            let initData = try await APIClient.shared.electiveInit()
            guard !handleCookieGenerationChange(expected: generation), !Task.isCancelled else { return }
            // pcencs 里可能有多个选课批次（实测有 2 个：网络课 63 门 + 面授课 75 门）
            // 必须逐个拉、合并去重；只取第一个会漏掉一大半
            var builder = ElectiveSnapshotBuilder<TeachingClass>()
            var batchError: Error?
            if let batches = initData.pcencs, !batches.isEmpty {
                for (pcid, pcenc) in batches.sorted(by: { $0.key < $1.key }) {
                    guard !handleCookieGenerationChange(expected: generation), !Task.isCancelled else { return }
                    let normalizedPCID = pcid.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalizedPCENC = pcenc.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalizedPCID.isEmpty,
                          !normalizedPCENC.isEmpty else {
                        if batchError == nil { batchError = APIError.decoding("选课批次缺少编号或加密串") }
                        continue
                    }
                    do {
                        let page = try await APIClient.shared.teachingClasses(batch: (normalizedPCID, normalizedPCENC))
                        guard !handleCookieGenerationChange(expected: generation), !Task.isCancelled else { return }
                        guard let items = page.initData else { throw APIError.empty }
                        builder.append(records(for: items), batchID: normalizedPCID)
                    } catch {
                        guard !handleCookieGenerationChange(expected: generation) else { return }
                        if error is CancellationError { throw error }
                        if batchError == nil { batchError = error }
                    }
                }
                if let batchError { throw batchError }
            } else {
                let page = try await APIClient.shared.teachingClasses(batch: nil)
                guard !handleCookieGenerationChange(expected: generation), !Task.isCancelled else { return }
                guard let items = page.initData else { throw APIError.empty }
                builder.append(records(for: items))
            }

            let fetched = builder.snapshot
            let sortedClasses = fetched.courses.sorted {
                ($0.kcmc ?? "").localizedStandardCompare($1.kcmc ?? "") == .orderedAscending
            }
            // Course rows and their batch memberships become visible in one verified snapshot.
            let sortedSnapshot = ElectiveSnapshot(
                courses: sortedClasses,
                courseIDs: fetched.courseIDs,
                batchIDsByCourse: fetched.batchIDsByCourse,
                actionFactsByCourse: fetched.actionFactsByCourse
            )
            guard !handleCookieGenerationChange(expected: generation), !Task.isCancelled else { return }
            electiveState.publish(sortedSnapshot, generation: generation)
            guard !handleCookieGenerationChange(expected: generation), !Task.isCancelled else { return }
            self.initData = initData
        } catch let e as APIError {
            guard !handleCookieGenerationChange(expected: generation) else { return }
            if Task.isCancelled {
                electiveState.refreshFailed()
                return
            }
            if case .notLoggedIn = e {
                if refreshAuthentication {
                    await session.refresh()
                    guard !handleCookieGenerationChange(expected: generation) else { return }
                    errorText = "会话已失效，已尝试续期；请重试验证课程数据"
                } else {
                    errorText = "会话续期后仍无法读取课程数据，请重新登录或重试"
                }
            } else {
                errorText = e.localizedDescription
            }
            electiveState.refreshFailed()
        } catch {
            guard !handleCookieGenerationChange(expected: generation) else { return }
            if Task.isCancelled {
                electiveState.refreshFailed()
                return
            }
            errorText = error.localizedDescription
            electiveState.refreshFailed()
        }
    }

    private func records(for items: [TeachingClass]) -> [ElectiveCourseRecord<TeachingClass>] {
        items.map {
            ElectiveCourseRecord(
                id: $0.id,
                value: $0,
                actionFacts: ElectiveCourseActionFacts(
                    isSelected: $0.isSelected,
                    selectionFlag: $0.sfkxk,
                    isFull: $0.isFull
                )
            )
        }
    }
}

// MARK: - 课程卡片

struct PendingAction: Identifiable {
    let id = UUID()
    let courseID: String
    let title: String?
    let enrolling: Bool
}

struct ClassCard: View {
    let item: TeachingClass
    var onAction: (() -> Void)? = nil
    var isWorking: Bool = false
    var canPerformAction: Bool = true
    var actionBlockReason: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.kcmc ?? "—")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(item.xf ?? "—")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.tint)
                    Text("学分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if let teacher = item.teacher, !teacher.isEmpty {
                    Label(teacher, systemImage: "person.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if item.isSelected {
                    Label("已选", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            if let place = item.sksjdd, !place.isEmpty {
                Label(place, systemImage: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                CapacityBar(item: item)

                if item.isFull && !item.isSelected {
                    Text("已满")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if item.canSelect && !item.isSelected {
                    Text("可选")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 4)

                if let onAction {
                    Button(action: onAction) {
                        HStack(spacing: 4) {
                            if isWorking {
                                ProgressView().controlSize(.mini)
                            }
                            Text(item.isSelected ? "退课" : "选课")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            item.isSelected ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.14),
                            in: .capsule
                        )
                        .foregroundStyle(item.isSelected ? Color.red : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || !canPerformAction)
                    .opacity(canPerformAction || isWorking ? 1 : 0.45)
                    .accessibilityHint(Text(actionBlockReason ?? (item.isSelected ? "点按后确认退课" : "点按后确认选课")))
                }
            }
            .padding(.top, 2)

            if let actionBlockReason {
                Label(actionBlockReason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .overlay {
            if item.isSelected {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(.green.opacity(0.55), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - 容量条

struct CapacityBar: View {
    let item: TeachingClass

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(fillColor.gradient)
                        .frame(width: max(4, geo.size.width * item.fillRatio))
                }
            }
            .frame(height: 5)

            Text("\(item.enrolled)/\(item.capacity)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var fillColor: Color {
        if item.fillRatio >= 1 { return .red }
        if item.fillRatio >= 0.8 { return .orange }
        return .green
    }
}

// MARK: - 详情

struct ClassDetailSheet: View {
    let item: TeachingClass

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.kcmc ?? "—")
                            .font(.title3.weight(.semibold))
                        Text(item.jxbmc ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section("基本信息") {
                    row("课程代码", item.kcid)
                    row("学分", item.xf)
                    row("课程类别", item.kclbname)
                    row("课程性质", item.kcxz)
                    row("教学方式", item.jxms)
                    row("考核方式", item.ksxs)
                }

                Section("安排") {
                    row("教师", item.teacher)
                    row("上课时间地点", item.sksjdd)
                    if let raw = item.sksjddstr, !raw.isEmpty {
                        row("周次编码", ScheduleCodec.humanize(raw))
                    }
                    row("校区", item.kkxqmc)
                }

                Section("选课情况") {
                    LabeledContent("已选 / 容量", value: "\(item.enrolled) / \(item.capacity)")
                    LabeledContent("状态") {
                        if item.isSelected {
                            Label("已选", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text(item.isFull ? "已满" : (item.canSelect ? "可选" : "不可选"))
                                .foregroundStyle(item.isFull ? .orange : (item.canSelect ? .green : .secondary))
                        }
                    }
                }

                if let bz = item.bz, !bz.isEmpty {
                    Section("备注") {
                        Text(bz).font(.footnote)
                    }
                }
            }
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty, value != "--" {
            LabeledContent(title) {
                Text(value)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
