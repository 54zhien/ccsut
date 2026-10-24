import SwiftUI
import WebKit
import Combine

struct EcardPaymentView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = EcardPaymentModel()
    @FocusState private var amountFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introduction
                if let receipt = model.receipt { result(receipt) }
                else {
                    roomSelection
                    if let detail = model.detail { meterCard(detail) }
                    amountSelection
                }
                if let message = model.errorText {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(message, systemImage: "exclamationmark.circle")
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
            }
            .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 24)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.receipt == nil { payBar }
        }
        .background(Color(.systemGroupedBackground))
        .academicDetailChrome(title: "电费缴费")
        .sheet(item: $model.loginRequest, onDismiss: model.loginDismissed) { request in
            EcardLoginSheet(request: request, success: model.acceptToken, failure: model.loginFailed)
        }
        .sheet(item: $model.confirmation) { confirmed in
            confirmation(confirmed)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(model.isSubmitting ? .hidden : .visible)
                .interactiveDismissDisabled(model.isSubmitting)
        }
        .task {
            if session.studentId == nil { await session.loadProfile() }
            model.start(account: session.studentId)
        }
        .onDisappear { model.stopQueries() }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 21, weight: .medium)).foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.09), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text("宿舍用电，随时补充").font(.headline)
                Text("选择房间，查询电表余额后缴费。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var roomSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("缴费房间")
            VStack(spacing: 0) {
                if model.campuses.count > 1 {
                    selectionRow("校区", placeholder: "请选择校区", options: model.campuses,
                                 value: model.campus, action: model.selectCampus)
                    Divider().padding(.leading, 16)
                }
                selectionRow("楼栋", placeholder: "请选择楼栋", options: model.buildings,
                             value: model.building, action: model.selectBuilding)
                Divider().padding(.leading, 16)
                selectionRow("房间", placeholder: "请选择房间", options: model.rooms,
                             value: model.room, action: model.selectRoom)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
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
        HStack {
            Text(title).font(.body)
            Spacer(minLength: 8)
            Picker(title, selection: Binding(get: { value }, set: action)) {
                Text(placeholder).tag(nil as String?)
                ForEach(options, id: \.value) { option in Text(option.name).tag(Optional(option.value)) }
            }
            .pickerStyle(.menu).labelsHidden()
            .disabled(options.isEmpty || model.isSubmitting)
            .accessibilityLabel(title)
        }
        .frame(minHeight: 52).padding(.horizontal, 16).padding(.vertical, 4)
    }
    private func meterCard(_ detail: MeterDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("电表信息")
            VStack(spacing: 14) {
                info("房间信息", detail.roomDescription ?? "—")
                info("表类型", detail.meterTypeName ?? "—")
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("剩余金额").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(detail.show["剩余金额"] ?? "—") 元")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle((detail.remainingAmount ?? 0) < 0 ? Color.red : Color.primary)
                        if (detail.remainingAmount ?? 0) < 0 {
                            Text("当前欠费").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
        }
    }

    private var amountSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("缴费金额")
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("¥").font(.title2.weight(.medium)).foregroundStyle(.secondary)
                    TextField("输入金额", text: $model.amountText)
                        .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                        .keyboardType(.decimalPad).focused($amountFocused)
                        .accessibilityLabel("缴费金额，单位元")
                    if amountFocused {
                        Button { amountFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                            .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("收起键盘")
                    }
                }
                if !model.quickAmounts.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
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
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
        }
    }
    private var limitDescription: String {
        guard let fee = model.fee, let max = fee.maxAmount else { return "金额以元为单位，请先完成房间查询" }
        var text = "单笔最高 \(max.ecardAmountText) 元"
        if let dayMax = fee.dayMaxAmount { text += " · 单日最高 \(dayMax.ecardAmountText) 元" }
        return text
    }
    private var payBar: some View {
        VStack(spacing: 10) {
            Button {
                amountFocused = false
                model.prepareConfirmation()
            } label: {
                Text("立即缴费").font(.headline).frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
            .disabled(!model.canPay)
            Text("从一卡通余额扣款，确认后即支付")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
        .background(.bar)
    }
    private func confirmation(_ confirmed: EcardPaymentModel.Confirmation) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(model.isSubmitting ? "正在缴费" : "确认缴费").font(.title2.bold())
                Spacer()
                if !model.isSubmitting {
                    SheetSymbolButton(symbol: "xmark", label: "取消缴费") { model.confirmation = nil }
                }
            }
            VStack(spacing: 16) {
                info("缴费房间", confirmed.room)
                info("支付方式", "一卡通余额")
                Divider()
                HStack {
                    Text("缴费金额").foregroundStyle(.secondary)
                    Spacer()
                    Text("¥\(confirmed.amount.ecardAmountText)").font(.title.bold().monospacedDigit())
                }
            }
            if model.isSubmitting {
                HStack(spacing: 10) { ProgressView(); Text("正在提交，请勿重复缴费").font(.subheadline) }
            } else {
                Text("这是免密支付。请确认房间与金额，点击下方按钮后将直接扣款。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { Task { await model.submit(confirmed) } } label: {
                    Text("确认支付 \(confirmed.amount.ecardAmountText) 元").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
            }
            Spacer(minLength: 0)
        }
        .padding(24).padding(.top, 8)
    }
    private func result(_ receipt: EcardPaymentModel.Receipt) -> some View {
        VStack(spacing: 20) {
            Image(systemName: receipt.status == .completed ? "checkmark.circle.fill" : receipt.status == .pending ? "clock.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(receipt.status == .completed ? Color.accentColor : receipt.status == .pending ? .orange : .red)
                .padding(.top, 8).accessibilityHidden(true)
            Text(receipt.status == .completed ? "缴费成功" : receipt.status == .pending ? "结果待确认" : "缴费未完成")
                .font(.title2.bold())
            Text("¥\(receipt.amount)").font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
            Text(receipt.room).font(.subheadline).multilineTextAlignment(.center)
            Divider()
            if let message = receipt.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            Text(receipt.status == .pending ? "支付结果尚未确认，请查询原订单，勿重复缴费。" : receipt.status == .completed ? "电表到账约 1–5 分钟" : "缴费成功后，电表到账约 1–5 分钟")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let orderID = receipt.orderID {
                Text("订单号 \(orderID)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
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
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
    }
    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EcardLoginSheet: View {
    let request: EcardPaymentModel.LoginRequest
    let success: (String) -> Void
    let failure: (Error) -> Void
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
                Text("请先登录一卡通，再进入电费缴费。\n获取缴费凭证后会自动返回。")
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
            .task {
                do { success(try await request.bridge.fetchToken(forAccount: request.account)) }
                catch { if !Task.isCancelled { failure(error) } }
            }
    }
}
