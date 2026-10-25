import SwiftUI
import WebKit
import Combine

struct EcardPaymentView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var model = EcardPaymentModel()
    @State private var showingRecoveryHelp = false
    @FocusState private var amountFocused: Bool

    init() {
        let value = EcardPaymentModel()
        #if DEBUG
        if InterfacePreview.enabled && InterfacePreview.page.hasPrefix("campus-electricity") {
            value.fee = try! JSONDecoder().decode(FeeItem.self, from: Data("""
            {"feeitemid":"preview-fee","name":"电费","flag":"0000000100","maxmoney":"400","daymaxmoney":"1000","dayout":"10,50,100"}
            """.utf8))
            func option(_ name: String, _ id: String) -> ThirdOption {
                let data = try! JSONSerialization.data(withJSONObject: ["name": name, "value": id])
                return try! JSONDecoder().decode(ThirdOption.self, from: data)
            }
            value.campuses = [option("示例校区", "preview-campus")]; value.campus = "preview-campus"
            value.buildings = [option("示例宿舍 1 栋", "preview-building")]; value.building = "preview-building"
            value.rooms = [option("101 室", "preview-room")]; value.room = "preview-room"
            let context = MeterContext()
            value.detail = MeterDetail(context: context, show: ["房间信息": "示例宿舍 1 栋 · 101 室", "表类型": "电表", "剩余金额": "36.80"], dataType: nil)
            if InterfacePreview.page.hasPrefix("campus-electricity-recovery") {
                switch InterfacePreview.page {
                case "campus-electricity-recovery-read": value.recoveryIssue = .readUnavailable
                case "campus-electricity-recovery-version": value.recoveryIssue = .unsupportedVersion(99)
                case "campus-electricity-recovery-missing": value.recoveryIssue = .missingRecord
                default: value.recoveryIssue = .corrupted
                }
            }
            if InterfacePreview.page == "campus-electricity-confirmation" {
                value.confirmation = .init(amount: 50, room: "示例宿舍 1 栋 · 101 室", roomValue: "preview-room", context: context)
            } else if InterfacePreview.page == "campus-electricity-result" || InterfacePreview.page == "campus-electricity-pending" {
                value.receipt = .init(status: InterfacePreview.page == "campus-electricity-result" ? .completed : .pending,
                                      room: "示例宿舍 1 栋 · 101 室", amount: "50", orderID: "preview-order")
            }
        }
        #endif
        _model = State(initialValue: value)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let issue = model.recoveryIssue { recoveryCard(issue) }
                else if let receipt = model.receipt { result(receipt) }
                else {
                    if let detail = model.detail { meterCard(detail) }
                    roomSelection
                    amountSelection
                }
                if model.recoveryIssue == nil, let message = model.errorText {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(CampusPrivacy.redact(message), systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if model.receipt == nil {
                            Button("重新加载") { model.start(account: session.studentId, force: true) }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .contain)
                }
                if model.receipt != nil, model.isStarting {
                    ProgressView("正在连接一卡通…").font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                if model.recoveryIssue == nil, model.canOpenLogin {
                    Button("打开认证页面", action: model.openLogin)
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 24)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.recoveryIssue == nil, model.receipt == nil { payBar }
        }
        .background(Color(.systemGroupedBackground))
        .academicDetailChrome(title: "电费缴费")
        .sheet(item: $model.loginRequest, onDismiss: model.loginDismissed) { request in
            EcardLoginSheet(request: request)
        }
        .sheet(item: $model.confirmation) { confirmed in
            confirmation(confirmed)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(model.isSubmitting ? .hidden : .visible)
                .interactiveDismissDisabled(model.isSubmitting)
        }
        .sheet(isPresented: $showingRecoveryHelp) { recoveryHelp }
        .onChange(of: session.studentId) { _, _ in showingRecoveryHelp = false }
        .onChange(of: model.recoveryIssue) { _, issue in
            if issue == nil { showingRecoveryHelp = false }
        }
        .task {
            #if DEBUG
            // No client, account or network preparation exists in these synthetic fixtures.
            if InterfacePreview.enabled && InterfacePreview.page.hasPrefix("campus-electricity") { return }
            #endif
            if session.studentId == nil { await session.loadProfile() }
            guard !Task.isCancelled else { return }
            model.start(account: session.studentId)
        }
        .onDisappear { model.stopQueries() }
    }

    private func recoveryCard(_ issue: EcardReceiptRecoveryError) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("待确认订单需要恢复", systemImage: "exclamationmark.shield")
                .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(issue.localizedDescription)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("在找回原订单并核实结果前，暂不能发起新的缴费。")
                .font(.footnote).foregroundStyle(.secondary)
            Button("重试读取") { model.retryRecovery(account: session.studentId) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.isStarting || model.isSubmitting || model.isChecking)
                .accessibilityIdentifier("payment-recovery-retry")
            Button("核实原订单") { showingRecoveryHelp = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("payment-recovery-help")
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
        .accessibilityIdentifier("payment-recovery-card")
    }

    private var recoveryHelp: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("先核实，再处理").font(.title2.weight(.semibold))
                    Text("请通过学校官方缴费记录或联系一卡通服务人员，核实上次电费缴费的扣款与到账情况。可准备缴费时间、金额和房间信息，避免再次缴费。")
                    Text("如果只是暂时无法读取，解锁设备后返回重试；如果提示版本不支持，请更新 App 后重试。请保留此 App 的数据，卸载或清除数据可能丢失原订单线索。")
                    Text("本页只提供处理说明，不会查询服务器或解锁付款。即使已在线下核实，也不能在这里手动确认或清除记录。找回原待确认记录后，App 才能继续查询原订单；记录仍无法恢复时，请保留现状等待进一步处理。")
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .navigationTitle("核实原订单").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { showingRecoveryHelp = false }
                        .accessibilityIdentifier("payment-recovery-close")
                }
            }
        }
    }

    private var roomSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CampusSection("缴费房间") {
                if model.campuses.count > 1 {
                    selectionRow("校区", placeholder: "请选择校区", options: model.campuses,
                                 value: model.campus, action: model.selectCampus)
                    Divider()
                }
                selectionRow("楼栋", placeholder: "请选择楼栋", options: model.buildings,
                             value: model.building, action: model.selectBuilding)
                Divider()
                selectionRow("房间", placeholder: "请选择房间", options: model.rooms,
                             value: model.room, action: model.selectRoom)
            }
            if model.isStarting || model.loadingText != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.loadingText ?? "正在连接一卡通…").font(.footnote).foregroundStyle(.secondary)
                }.padding(.horizontal, 4)
            }
        }
    }
    private func selectionRow(_ title: String, placeholder: String, options: [ThirdOption],
                              value: String?, action: @escaping (String?) -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                selectionPicker(title, placeholder: placeholder, options: options, value: value, action: action)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).foregroundStyle(.secondary)
                selectionPicker(title, placeholder: placeholder, options: options, value: value, action: action)
            }
        }.frame(minHeight: 44)
    }
    private func selectionPicker(_ title: String, placeholder: String, options: [ThirdOption],
                                 value: String?, action: @escaping (String?) -> Void) -> some View {
        Picker(title, selection: Binding(get: { value }, set: action)) {
            Text(placeholder).tag(nil as String?)
            ForEach(options, id: \.value) { option in Text(CampusPrivacy.redact(option.name)).tag(Optional(option.value)) }
        }.pickerStyle(.menu).labelsHidden().disabled(options.isEmpty || model.isSubmitting).accessibilityLabel(title)
    }
    private func meterCard(_ detail: MeterDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("剩余金额", systemImage: "bolt.fill").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if (detail.remainingAmount ?? 0) < 0 {
                    Text("当前欠费").font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }
            ViewThatFits(in: .horizontal) {
                balance(detail).fixedSize(horizontal: true, vertical: false)
                balance(detail).minimumScaleFactor(0.5)
            }
            Divider()
            CampusInfoRow("房间信息", value: detail.roomDescription ?? "—")
            CampusInfoRow("表类型", value: detail.meterTypeName ?? "—")
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }
    private func balance(_ detail: MeterDetail) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(CampusPrivacy.redact(detail.show["剩余金额"] ?? "—"))
                .font(.largeTitle.weight(.semibold).monospacedDigit()).lineLimit(1)
                .foregroundStyle((detail.remainingAmount ?? 0) < 0 ? Color.red : Color.primary)
            Text("元").font(.subheadline).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private var amountSelection: some View {
        CampusSection("缴费金额") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("¥").font(.title2.weight(.medium)).foregroundStyle(.secondary)
                    TextField("输入金额", text: $model.amountText)
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                        .keyboardType(.decimalPad).focused($amountFocused)
                        .accessibilityLabel("缴费金额，单位元")
                    if amountFocused {
                        Button { amountFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                            .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("收起键盘")
                    }
                }
                if !model.quickAmounts.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 140 : 80))], spacing: 10) {
                        ForEach(model.quickAmounts, id: \.self) { amount in
                            Button { model.amountText = amount.ecardAmountText; amountFocused = false } label: {
                                Text("\(amount.ecardAmountText) 元")
                                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                                    .foregroundStyle(model.amount == amount ? Color("AccentForeground") : Color.accentColor)
                                    .background(model.amount == amount ? Color.accentColor : Color.accentColor.opacity(0.08),
                                                in: .rect(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.amount == amount ? .isSelected : [])
                        }
                    }
                }
                if let hint = model.amountHint {
                    Text(hint).font(.footnote).foregroundStyle(.red)
                } else {
                    Text(limitDescription).font(.footnote).foregroundStyle(.secondary)
                }
        }
    }
    private var limitDescription: String {
        guard let fee = model.fee, let max = fee.maxAmount else { return "金额以元为单位，请先完成房间查询" }
        var text = "单笔最高 \(max.ecardAmountText) 元"
        if let dayMax = fee.dayMaxAmount { text += " · 单日最高 \(dayMax.ecardAmountText) 元" }
        return text
    }
    private var payBar: some View {
        CampusActionDock {
            VStack(spacing: 10) {
                Button {
                    amountFocused = false
                    model.prepareConfirmation()
                } label: {
                    Text("立即缴费").font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
                .campusActionControl()
                .disabled(!model.canPay)
                Text("从一卡通余额扣款，确认后即支付")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
        }
    }
    private func confirmation(_ confirmed: EcardPaymentModel.Confirmation) -> some View {
        VStack(spacing: 0) {
            SheetHeader(title: model.isSubmitting ? "正在缴费" : "确认缴费") { model.confirmation = nil }
                .disabled(model.isSubmitting)
            ScrollView {
                CampusSection("支付明细") {
                    Text("¥\(confirmed.amount.ecardAmountText)").font(.largeTitle.weight(.semibold).monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    info("缴费房间", confirmed.room)
                    info("支付方式", "一卡通余额")
                }
                .padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            CampusActionDock {
                VStack(spacing: 12) {
                    if model.isSubmitting {
                        HStack(spacing: 10) { ProgressView(); Text("正在提交，请勿重复缴费").font(.subheadline) }
                    } else {
                        Text("这是免密支付。请确认房间与金额，点击下方按钮后将直接扣款。")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { Task { await model.submit(confirmed) } } label: {
                            Text("确认支付 \(confirmed.amount.ecardAmountText) 元").font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                        .campusActionControl()
                    }
                }
                .padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
    private func result(_ receipt: EcardPaymentModel.Receipt) -> some View {
        VStack(spacing: 20) {
            Image(systemName: receipt.status == .completed ? "checkmark.circle.fill" : receipt.status == .pending ? "clock.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(receipt.status == .completed ? Color.accentColor : receipt.status == .pending ? .orange : .red)
                .padding(.top, 8).accessibilityHidden(true)
            Text(receipt.status == .completed ? "缴费成功" : receipt.status == .pending ? "结果待确认" : "缴费未完成")
                .font(.title2.bold())
            Text("¥\(CampusPrivacy.redact(receipt.amount))").font(.largeTitle.weight(.semibold).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Text(CampusPrivacy.redact(receipt.room)).font(.subheadline).multilineTextAlignment(.center)
            Divider()
            if let message = receipt.message { Text(CampusPrivacy.redact(message)).font(.footnote).foregroundStyle(.secondary) }
            Text(receipt.status == .pending ? "支付结果尚未确认，请查询原订单，勿重复缴费。" : receipt.status == .completed ? "电表到账约 1–5 分钟" : "缴费成功后，电表到账约 1–5 分钟")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let orderID = receipt.orderID {
                Text("订单号 \(CampusPrivacy.redact(orderID))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if receipt.status == .pending {
                Button { Task { await model.checkOrder() } } label: {
                    HStack { if model.isChecking { ProgressView() }; Text("查询支付结果") }.frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .disabled(model.isChecking || model.isStarting)
            } else {
                Button(receipt.status == .completed ? "返回缴费页面" : "返回修改") { model.returnToForm() }
                    .buttonStyle(.glass).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity).padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }
    private func info(_ label: String, _ value: String) -> some View {
        CampusInfoRow(label, value: value)
    }
}

private struct EcardLoginSheet: View {
    let request: EcardPaymentModel.LoginRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.deviceCornerRadius) private var cornerRadius
    @State private var isLoading = true
    @State private var controlHeight: CGFloat = 0

    var body: some View {
        WebPanel(webView: request.bridge.webView, extendsUnderControls: true)
            .overlay(alignment: .top) {
                HStack {
                    SheetSymbolButton(symbol: "xmark", label: "关闭一卡通登录") { dismiss() }
                    Spacer()
                    HStack(spacing: 8) {
                        if isLoading { ProgressView().controlSize(.small) }
                        Text("一卡通登录").font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16).frame(height: controlHeight > 0 ? controlHeight : 48)
                    .glassEffect(.regular, in: .capsule)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlHeight = $0 }
                .padding(.horizontal, SheetLayout.controlInset(cornerRadius, diameter: controlHeight))
                .padding(.top, SheetLayout.controlInset(cornerRadius, diameter: controlHeight))
            }
            .overlay(alignment: .bottom) {
                Text("正在尝试复用 App 登录。\n若学校要求验证，请在此完成；随后会自动返回。")
                    .font(.footnote).foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .padding(.horizontal, 24).padding(.bottom, 32)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(.container)
            .presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationCornerRadius(SheetLayout.cornerRadius(cornerRadius))
            .onReceive(request.bridge.webView.publisher(for: \.isLoading)) { isLoading = $0 }
    }
}
