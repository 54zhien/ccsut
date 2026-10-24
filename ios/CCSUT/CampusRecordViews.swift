import SwiftUI

struct CampusRecordsView: View {
    enum Mode { case leave, travel }
    @Environment(SessionStore.self) private var session
    let mode: Mode
    @State private var model: CampusRecordsModel?
    @State private var accountError = false
    @State private var reconnectRevision: UInt64 = 0
    @State private var selectedKind: CampusTravelKind = .departure
    private struct Connection: Hashable { let account: String?; let revision: UInt64 }

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
        .task(id: Connection(account: session.studentId, revision: reconnectRevision)) {
            model?.cancel()
            model = nil
            accountError = false
            #if DEBUG
            if InterfacePreview.enabled {
                model = CampusRecordsModel(api: CampusPreviewReader(), currentGeneration: { CookieJar.generation })
                return
            }
            #endif
            if session.studentId == nil { await session.loadProfile() }
            guard !Task.isCancelled else { return }
            guard let account = session.studentId, !account.isEmpty else { accountError = true; return }
            let client = CampusClient(account: account, credentials: CampusCookieCredentials())
            model = CampusRecordsModel(api: client, currentGeneration: { CookieJar.generation })
        }
        .onDisappear { model?.cancel() }
    }
}

private struct CampusRecordContent: View {
    let model: CampusRecordsModel
    let mode: CampusRecordsView.Mode
    let account: String
    @Binding var selected: CampusTravelKind
    let reconnect: () -> Void
    @State private var officialPage: CampusWebDestination?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if mode == .travel {
                    Picker("记录类型", selection: $selected) {
                        ForEach(CampusTravelKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("campus-travel-kind")
                }
                Button {
                    officialPage = mode == .leave ? .leaveForm : (selected == .departure ? .departure : .returning)
                } label: {
                    Label(mode == .leave ? "申请请假" : "办理\(selected == .departure ? "离校" : "返校")登记", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                if mode == .leave { leaveContent } else { travelContent }
            }
            .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 28)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollBounceBehavior(.always, axes: .vertical)
        .pageRefreshable {
            if mode == .leave { await model.loadLeave(reset: true) }
            else { await model.loadTravel(kind: selected) }
        }
        .task(id: selected) {
            if mode == .leave { await model.loadLeave(reset: true) }
            else { await model.loadTravel(kind: selected) }
        }
        .sheet(item: $officialPage, onDismiss: reconnect) { destination in
            CampusWebView(destination: destination, account: account)
        }
    }

    @ViewBuilder private var leaveContent: some View {
        if let error = model.leaveError {
            notice(error) { Task { await model.loadLeave(reset: model.leaveFailureWasRefresh) } }
        }
        if model.isLoadingLeave && model.leave.items.isEmpty {
            ProgressView("正在读取请假记录…").frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if model.leave.items.isEmpty && model.leaveError == nil {
            ContentUnavailableView("暂无请假记录", systemImage: "doc.text.magnifyingglass")
        }
        ForEach(model.leave.items) { record in
            recordCard(title: record.typeName ?? "请假记录", status: record.statusText) {
                detail("开始", record.beginTime)
                detail("结束", record.endTime)
                if let days = record.days { detail("时长", "\(NSDecimalNumber(decimal: days).stringValue) 天") }
                detail("事由", record.reason)
                detail("申请时间", record.applyTime)
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

    @ViewBuilder private var travelContent: some View {
        if let error = model.travelErrors[selected] {
            notice(error) { Task { await model.loadTravel(kind: selected) } }
        }
        let records = model.travel[selected] ?? []
        if model.loadingTravel.contains(selected) && records.isEmpty {
            ProgressView("正在读取\(selected.title)…").frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if records.isEmpty && model.travelErrors[selected] == nil {
            ContentUnavailableView("暂无\(selected.title)", systemImage: "calendar.badge.checkmark")
        }
        ForEach(records) { record in
            recordCard(title: record.title, status: record.statusText) {
                detail("开始", record.startDate)
                detail("结束", record.endDate)
                detail("去向", record.destination)
                detail("交通", record.transport)
                detail("事由", record.reason)
                detail("登记时间", record.applyDate)
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

    private func recordCard<Content: View>(title: String, status: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(status).font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }

    @ViewBuilder private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
private actor CampusPreviewReader: CampusReading {
    func leaveRecords(page: Int, size: Int) async throws -> CampusLeavePage {
        try CampusDecoder.leavePage(Data("""
        {"data":{"list":[{"id":"preview-leave","leaveTypeName":"事假","beginTime":"2026-10-01 08:00",
        "endTime":"2026-10-02 18:00","leaveDay":2,"status":0,"reason":"示例请假记录"}],
        "pageNum":1,"pageSize":20,"total":1,"hasNextPage":false}}
        """.utf8))
    }
    func travelRecords(kind: CampusTravelKind) async throws -> [CampusTravelRecord] {
        try CampusDecoder.travelRecords(Data("""
        {"code":"2000","data":[{"openid":"preview-travel","typeName":"节假日登记","status":"待审核",
        "startDate":"2026-10-01","endDate":"2026-10-07","txdz":"示例区县","jtgj":"公共交通"}]}
        """.utf8))
    }
}
#endif
