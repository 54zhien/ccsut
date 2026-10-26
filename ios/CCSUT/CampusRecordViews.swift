import SwiftUI

struct CampusRecordsView: View {
    enum Mode { case leave, travel }
    @Environment(SessionStore.self) private var session
    let mode: Mode
    @State private var model: CampusRecordsModel?
    @State private var accountError = false
    @State private var reconnectRevision: UInt64 = 0
    @State private var selectedKind: CampusTravelKind = .departure
    @State private var boundConnection: Connection?
    private struct Connection: Hashable { let account: String?; let generation: UInt64 }
    private struct ConnectionTask: Hashable { let connection: Connection; let revision: UInt64 }

    var body: some View {
        Group {
            if let model {
                CampusRecordContent(model: model, mode: mode, account: session.studentId ?? "",
                                    selected: $selectedKind) { reconnectRevision &+= 1 }
            } else if accountError {
                ContentUnavailableView {
                    Label("暂时无法读取校园记录", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: { Text("请先确认当前登录账号，再重新打开此页面。") }
            } else {
                ProgressView("正在连接校园服务…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .academicDetailChrome(title: mode == .leave ? "请假" : "节假日离返校")
        .task(id: ConnectionTask(connection: Connection(account: session.studentId, generation: CookieJar.generation), revision: reconnectRevision)) {
            let connection = Connection(account: session.studentId, generation: CookieJar.generation)
            // A dismissed form resumes the same account/session. Refresh its existing model
            // so loaded records stay visible, including when the refresh fails.
            if boundConnection == connection, let model {
                if mode == .leave { await model.loadLeave(reset: true) }
                else { await model.loadTravel(kind: selectedKind) }
                return
            }
            model?.cancel()
            model = nil
            boundConnection = nil
            accountError = false
            #if DEBUG
            if InterfacePreview.enabled {
                model = CampusRecordsModel(api: CampusPreviewReader(), currentGeneration: { CookieJar.generation })
                boundConnection = connection
                return
            }
            #endif
            if session.studentId == nil { await session.loadProfile() }
            guard !Task.isCancelled else { return }
            guard let account = session.studentId, !account.isEmpty else { accountError = true; return }
            let client = CampusClient(account: account, credentials: CampusCookieCredentials())
            model = CampusRecordsModel(api: client, currentGeneration: { CookieJar.generation })
            boundConnection = Connection(account: account, generation: CookieJar.generation)
        }
        .onDisappear { model?.cancel() }
    }
}

private struct CampusRecordContent: View {
    @Environment(\.deviceCornerRadius) private var deviceCornerRadius
    let model: CampusRecordsModel
    let mode: CampusRecordsView.Mode
    let account: String
    @Binding var selected: CampusTravelKind
    let reconnect: () -> Void
    @State private var officialPage: CampusWebDestination?
    @State private var nativeForm: CampusFormKind?
    @State private var addControlSize: CGSize = .zero
    @State private var headerHeight: CGFloat = 0
    private struct ReadTask: Hashable { let model: ObjectIdentifier; let kind: CampusTravelKind }

    var body: some View {
        GeometryReader { viewport in
            PageScrollSurface(refresh: {
                if mode == .leave { await model.loadLeave(reset: true) }
                else { await model.loadTravel(kind: selected) }
            }, refreshHaptics: true) { contentViewport, _ in
                LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        if mode == .travel {
                            Picker("记录类型", selection: $selected) {
                                ForEach(CampusTravelKind.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("campus-travel-kind")
                        }
                        Text(mode == .leave ? "申请记录" : selected.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary).padding(.horizontal, 4).padding(.top, 8).accessibilityAddTraits(.isHeader)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    if mode == .leave {
                        leaveContent(viewportHeight: contentViewport.height)
                    } else {
                        travelContent(viewportHeight: contentViewport.height)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 28)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Button(action: addRecord) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: Circle())
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { addControlSize = $0 }
                    .accessibilityLabel(addRecordTitle)
                    .accessibilityHint(addRecordHint)
                    .accessibilityIdentifier("campus-record-add")
                }
                // Convert the screen-edge inset into this horizontally safe viewport.
                // The measured native circle and the physical corner share a center.
                .padding(.trailing, SheetLayout.controlInset(deviceCornerRadius, diameter: addControlSize.width) - viewport.safeAreaInsets.trailing)
                .padding(.bottom, SheetLayout.controlInset(deviceCornerRadius, diameter: addControlSize.height))
                .padding(.top, 12)
            }
        }
        // Anchor to the physical bottom; retain SwiftUI's keyboard avoidance.
        .ignoresSafeArea(.container, edges: .bottom)
        // A real account/session replacement must start reads even when the selected kind
        // did not change; SwiftUI may retain this content view's identity across model swaps.
        .task(id: ReadTask(model: ObjectIdentifier(model), kind: selected)) {
            if mode == .leave { await model.loadLeave(reset: true) }
            else { await model.loadTravel(kind: selected) }
        }
        .sheet(item: $officialPage, onDismiss: reconnect) { destination in
            CampusWebView(destination: destination, account: account)
        }
        .sheet(item: $nativeForm, onDismiss: reconnect) { kind in
            CampusFormView(kind: kind, account: account)
        }
    }

    private var addRecordTitle: String {
        mode == .leave ? "申请请假" : "办理\(selected == .departure ? "离校" : "返校")登记"
    }

    private var addRecordHint: String {
        mode == .leave ? "打开请假申请表单" : "打开\(selected == .departure ? "离校" : "返校")登记页面"
    }

    private func addRecord() {
        if mode == .leave { nativeForm = .leave }
        else if selected == .departure { nativeForm = .departure }
        else { officialPage = .returning }
    }

    @ViewBuilder private func leaveContent(viewportHeight: CGFloat) -> some View {
        if let error = model.leaveError {
            notice(error) { Task { await model.loadLeave(reset: model.leaveFailureWasRefresh) } }
        }
        if model.isLoadingLeave && model.leave.items.isEmpty {
            ProgressView("正在读取请假记录…").frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if model.leave.items.isEmpty && model.leaveError == nil {
            ContentUnavailableView("暂无请假记录", systemImage: "doc.text.magnifyingglass")
                .accessibilityIdentifier("campus-leave-empty")
                .modifier(CampusRecordEmptyStateLayout(viewportHeight: viewportHeight, headerHeight: headerHeight))
        }
        ForEach(model.leave.items) { record in
            recordCard(title: record.typeName ?? "请假记录", status: record.statusText, pending: record.status == 0) {
                CampusDateRange(start: record.beginTime, end: record.endTime)
                if let days = record.days {
                    Label("\(NSDecimalNumber(decimal: days).stringValue) 天", systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let reason = record.reason, !reason.isEmpty {
                    Divider(); Text(reason).font(.subheadline).fixedSize(horizontal: false, vertical: true).privacySensitive()
                }
                if let applied = record.applyTime { timestamp("申请于", applied) }
            }
        }
        if !model.leave.items.isEmpty && model.leave.hasMore {
            Button { Task { await model.loadLeave(reset: false) } } label: {
                HStack {
                    if model.isLoadingLeave { ProgressView() }
                    Text(model.isLoadingLeave ? "正在加载…" : "加载更多")
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(model.isLoadingLeave)
        }
    }

    @ViewBuilder private func travelContent(viewportHeight: CGFloat) -> some View {
        if let error = model.travelErrors[selected] {
            notice(error) { Task { await model.loadTravel(kind: selected) } }
        }
        let records = model.travel[selected] ?? []
        if model.loadingTravel.contains(selected) && records.isEmpty {
            ProgressView("正在读取\(selected.title)…").frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if records.isEmpty && model.travelErrors[selected] == nil {
            ContentUnavailableView("暂无\(selected.title)", systemImage: "calendar.badge.checkmark")
                .accessibilityIdentifier("campus-travel-empty")
                .modifier(CampusRecordEmptyStateLayout(viewportHeight: viewportHeight, headerHeight: headerHeight))
        }
        ForEach(records) { record in
            recordCard(title: record.title, status: record.statusText, pending: record.statusText == "待审核") {
                CampusDateRange(start: record.startDate, end: record.endDate)
                if record.destination != nil || record.transport != nil { Divider() }
                if let destination = record.destination { detail("去向", destination) }
                if let transport = record.transport { detail("交通", transport) }
                if let reason = record.reason, !reason.isEmpty { Text(reason).font(.subheadline).fixedSize(horizontal: false, vertical: true).privacySensitive() }
                if let applied = record.applyDate { timestamp("登记于", applied) }
            }
        }
    }

    private func notice(_ error: CampusError, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PageStatusNotice(message: error.localizedDescription, retry: retry)
            if error == .authentication {
                Button("打开官方页面认证") {
                    officialPage = mode == .leave ? .leaveList : (selected == .departure ? .departure : .returning)
                }
                .frame(minHeight: 44).padding(.horizontal, 16)
            }
        }
    }

    private func recordCard<Content: View>(title: String, status: String, pending: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader); Spacer(minLength: 0)
                    CampusStatusBadge(text: status, pending: pending)
                }
                VStack(alignment: .leading, spacing: 10) { Text(title).font(.headline).accessibilityAddTraits(.isHeader); CampusStatusBadge(text: status, pending: pending) }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }

    @ViewBuilder private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true).privacySensitive()
            }
        }
    }

    private func timestamp(_ label: String, _ raw: String) -> some View {
        Text(label + " " + CampusDisplayDate.timestamp(raw)).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).privacySensitive()
    }
}

#if DEBUG
private actor CampusPreviewReader: CampusReading {
    private var leaveReads = 0
    private var travelReads: [CampusTravelKind: Int] = [:]

    func leaveRecords(page: Int, size: Int) async throws -> CampusLeavePage {
        leaveReads += 1
        if leaveReads > 1 && ProcessInfo.processInfo.arguments.contains("--preview-controlled-refresh") {
            await PreviewRefreshCompletionGate.shared.waitForRelease()
        }
        if InterfacePreview.emptyPage {
            return try CampusDecoder.leavePage(Data("""
            {"data":{"list":[],"pageNum":1,"pageSize":20,"total":0,"hasNextPage":false}}
            """.utf8))
        }
        return try CampusDecoder.leavePage(Data("""
        {"data":{"list":[{"id":"preview-leave","leaveTypeName":"事假","beginTime":"2026-10-01 08:00",
        "endTime":"2026-10-02 18:00","leaveDay":2,"status":0,"reason":"示例请假记录"}],
        "pageNum":1,"pageSize":20,"total":1,"hasNextPage":false}}
        """.utf8))
    }
    func travelRecords(kind: CampusTravelKind) async throws -> [CampusTravelRecord] {
        travelReads[kind, default: 0] += 1
        if travelReads[kind, default: 0] > 1 && ProcessInfo.processInfo.arguments.contains("--preview-controlled-refresh") {
            await PreviewRefreshCompletionGate.shared.waitForRelease()
        }
        if InterfacePreview.emptyPage { return [] }
        return try CampusDecoder.travelRecords(Data("""
        {"code":"2000","data":[{"openid":"preview-travel","typeName":"节假日登记","status":"待审核",
        "startDate":"2026-10-01","endDate":"2026-10-07","txdz":"示例区县","jtgj":"公共交通"}]}
        """.utf8))
    }
}
#endif

private struct CampusRecordEmptyStateLayout: ViewModifier {
    let viewportHeight: CGFloat
    let headerHeight: CGFloat
    @State private var contentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        let contentTop = 24 + headerHeight + 16
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .padding(.top, max(0, (viewportHeight - contentHeight) / 2 - contentTop))
            .frame(maxWidth: .infinity, minHeight: max(0, viewportHeight - contentTop - 28), alignment: .top)
    }
}
