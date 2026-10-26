import SwiftUI
import WebKit
import Combine

struct EcardPaymentView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var model = EcardPaymentModel()
    @State private var showingRecoveryHelp = false

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
            value.amountText = "50"
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
        PageScrollSurface(refresh: { await model.refreshMeter(account: session.studentId) }, refreshHaptics: true) { _, _ in
            VStack(alignment: .leading, spacing: 20) {
                if let issue = model.recoveryIssue { recoveryCard(issue) }
                else if let receipt = model.receipt { result(receipt) }
                else {
                    meterCard(model.detail)
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
            .padding(.horizontal, AppLayout.pageInset).padding(.top, 20).padding(.bottom, 24)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
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
        .onChange(of: amountMaximum, initial: true) { _, _ in
            normalizeDisplayedAmount()
        }
        .onChange(of: model.receipt != nil) { _, hasReceipt in
            if !hasReceipt { normalizeDisplayedAmount() }
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
            Button { showingRecoveryHelp = true } label: {
                Text("核实原订单").frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("payment-recovery-help")
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
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
        VStack(alignment: .leading, spacing: 10) {
            Text("缴费房间")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if model.campuses.count > 1 { campusChoice }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buildingChoice; roomChoice }
                VStack(spacing: 10) { buildingChoice; roomChoice }
            }
            if model.isStarting || model.loadingText != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.loadingText ?? "正在连接一卡通…")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }

    private var campusChoice: some View {
        selectionNameplate("校区", symbol: "mappin.and.ellipse", placeholder: "请选择校区",
                           options: model.campuses, value: model.campus, action: model.selectCampus)
    }
    private var buildingChoice: some View {
        selectionNameplate("楼栋", symbol: "building.2", placeholder: "选择楼栋",
                           options: model.buildings, value: model.building, action: model.selectBuilding)
    }
    private var roomChoice: some View {
        selectionNameplate("房间", symbol: "door.left.hand.closed", placeholder: "选择房间",
                           options: model.rooms, value: model.room, action: model.selectRoom)
    }
    private func selectionNameplate(_ title: String, symbol: String, placeholder: String,
                                    options: [ThirdOption], value: String?,
                                    action: @escaping (String?) -> Void) -> some View {
        Menu {
            Picker(title, selection: Binding(get: { value }, set: action)) {
                Text(placeholder).tag(nil as String?)
                ForEach(options, id: \.value) { option in
                    Text(CampusPrivacy.redact(option.name)).tag(Optional(option.value))
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label(title, systemImage: symbol)
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CampusPrivacy.redact(options.first(where: { $0.value == value })?.name ?? placeholder))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 1)
                    }
            }
        }
        .disabled(options.isEmpty || model.isSubmitting)
        .accessibilityLabel("选择\(title)")
    }

    private func meterCard(_ detail: MeterDetail?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.headline.weight(.semibold)).foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10), in: .circle)
                Text("电费计量")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                if let type = detail?.meterTypeName {
                    Text(CampusPrivacy.redact(type))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                }
            }

            meterSeam.padding(.vertical, 14)
            roomSelection
            meterSeam.padding(.vertical, 14)
            meterDisplay(detail)
            meterSeam.padding(.vertical, 14)
            amountSelection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(chassisSurface(cornerRadius: 30))
        .overlay {
            GeometryReader { geometry in
                ZStack {
                    meterFastener.position(x: 10, y: 10)
                    meterFastener.position(x: geometry.size.width - 10, y: 10)
                    meterFastener.position(x: 10, y: geometry.size.height - 10)
                    meterFastener.position(x: geometry.size.width - 10, y: geometry.size.height - 10)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 14, x: 0, y: 9)
    }

    private var meterFastener: some View {
        Circle()
            .fill(LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.24), Color.black.opacity(0.48)]
                    : [Color.white.opacity(0.92), Color.black.opacity(0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 0.5)
            }
            .overlay {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.36 : 0.30))
                    .frame(width: 3.5, height: 0.7)
                    .rotationEffect(.degrees(-35))
            }
            .frame(width: 6, height: 6)
    }

    private var meterSeam: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black.opacity(0.48), Color.white.opacity(0.08), Color.black.opacity(0.35)]
                    : [Color.black.opacity(0.14), Color.white.opacity(0.88), Color.black.opacity(0.08)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func chassisSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.28, green: 0.29, blue: 0.29), Color(red: 0.16, green: 0.17, blue: 0.17), Color(red: 0.23, green: 0.24, blue: 0.24)]
                    : [Color(.systemGray5), Color(.secondarySystemGroupedBackground), Color(.systemGray4), Color(.systemGray5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color.white.opacity(0.20), Color.black.opacity(0.45)]
                        : [Color.white.opacity(0.90), Color.black.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(1, cornerRadius - 5), style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.66), lineWidth: 0.7)
                    .padding(4)
            }
    }

    private var lcdSurface: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.13, green: 0.19, blue: 0.15), Color(red: 0.09, green: 0.14, blue: 0.11)]
                    : [Color(red: 0.87, green: 0.91, blue: 0.76), Color(red: 0.78, green: 0.84, blue: 0.65)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.50 : 0.22), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.42), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 30)
                    .allowsHitTesting(false)
            }
    }

    private var lcdInk: Color {
        colorScheme == .dark ? Color(red: 0.79, green: 0.91, blue: 0.75) : Color(red: 0.18, green: 0.25, blue: 0.14)
    }

    private func meterDisplay(_ detail: MeterDetail?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("剩余金额", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(lcdInk.opacity(0.82))
                Spacer(minLength: 8)
                if (detail?.remainingAmount ?? 0) < 0 {
                    Text("当前欠费").font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }
            if let detail {
                ViewThatFits(in: .horizontal) {
                    balance(detail).fixedSize(horizontal: true, vertical: false)
                    balance(detail).minimumScaleFactor(0.5)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(CampusPrivacy.redact(detail.roomDescription ?? "—"))
                        Spacer(minLength: 0)
                        Text(CampusPrivacy.redact(detail.meterTypeName ?? "—"))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CampusPrivacy.redact(detail.roomDescription ?? "—"))
                        Text(CampusPrivacy.redact(detail.meterTypeName ?? "—"))
                    }
                }
                .font(.caption).foregroundStyle(lcdInk.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.isStarting ? "正在读取余额…" : "余额暂不可用")
                    .font(.title3.weight(.medium)).foregroundStyle(lcdInk.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(lcdSurface)
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.42 : 0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 3, x: 0, y: 2)
    }

    private func balance(_ detail: MeterDetail) -> some View {
        let rawValue = detail.show["剩余金额"] ?? "—"
        let valueInk = (detail.remainingAmount ?? 0) < 0 ? Color.red : lcdInk
        return Group {
            if SevenSegmentBalanceDisplay.canRender(rawValue) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 8) {
                        SevenSegmentBalanceDisplay(value: rawValue, ink: valueInk)
                        Text("元").font(.subheadline).foregroundStyle(lcdInk.opacity(0.78))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    textBalance(rawValue, ink: valueInk)
                }
            } else {
                textBalance(rawValue, ink: valueInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rawValue) 元")
    }

    private func textBalance(_ value: String, ink: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.45)
                .foregroundStyle(ink)
            Text("元").font(.subheadline).foregroundStyle(lcdInk.opacity(0.78))
        }
    }

    private var amountSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("充值金额").font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                Text("人民币 · 元").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                Text("¥").font(.title2.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.leading, 10).padding(.trailing, 6).accessibilityHidden(true)
                amountDrum(place: 100, label: "百位")
                amountDrum(place: 10, label: "十位")
                amountDrum(place: 1, label: "个位")
            }
            .padding(.trailing, 8)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.black.opacity(0.34), Color.black.opacity(0.20)]
                            : [Color.white.opacity(0.54), Color(.systemGray6).opacity(0.68)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07), lineWidth: 1)
                    }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("缴费金额，\(amountValue)元，上下滑动数字调整")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { amountPresets }
                VStack(spacing: 8) { amountPresets }
            }
            Text(amountMaximum > 0 ? "可充值 \(MeterAmount.minimum)–\(amountMaximum) 元" : "正在获取可充值金额范围")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            if let hint = model.amountHint {
                Label(hint, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var amountPresets: some View {
        ForEach([50, 100, 200], id: \.self) { amount in
            Button {
                model.amountText = String(amount)
            } label: {
                Text("\(amount) 元").font(.subheadline.weight(.semibold)).monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle)
            .tint(amountValue == amount ? Color.accentColor : Color.secondary)
            .disabled(amountMaximum < amount || model.isSubmitting)
            .accessibilityLabel("充值\(amount)元")
            .accessibilityAddTraits(amountValue == amount ? [.isSelected] : [])
        }
    }
    private var amountMaximum: Int {
        MeterAmount.maximum(perPayment: model.fee?.maxAmount, perDay: model.fee?.dayMaxAmount)
    }
    private var amountValue: Int {
        MeterAmount.clamp(model.amount.map { NSDecimalNumber(decimal: $0).intValue } ?? 0, maximum: amountMaximum)
    }
    private var canPayDisplayedAmount: Bool {
        model.canPay && amountValue >= MeterAmount.minimum && model.amount == Decimal(amountValue)
    }
    private func normalizeDisplayedAmount() {
        guard amountMaximum >= MeterAmount.minimum, model.receipt == nil, !model.isSubmitting else { return }
        model.amountText = String(MeterAmount.clamp(amountValue, maximum: amountMaximum))
    }
    private func amountDrum(place: Int, label: String) -> some View {
        Picker(label, selection: Binding(
            get: { amountValue / place % 10 },
            set: { digit in
                model.amountText = String(MeterAmount.replacing(amount: amountValue, place: place,
                                                              digit: digit, maximum: amountMaximum))
            }
        )) {
            ForEach(MeterAmount.digits(amount: amountValue, place: place, maximum: amountMaximum), id: \.self) { digit in
                Text(String(digit)).font(.system(size: textSize.isAccessibilitySize ? 44 : 40, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .tag(digit)
            }
        }
        .pickerStyle(.wheel).labelsHidden()
        .frame(minWidth: 44, maxWidth: .infinity).frame(height: textSize.isAccessibilitySize ? 180 : 156)
        .clipped()
        .disabled(amountMaximum == 0 || model.isSubmitting)
        .accessibilityLabel("金额\(label)")
    }
    private var payBar: some View {
        VStack(spacing: 10) {
            Button {
                guard canPayDisplayedAmount else { return }
                model.prepareConfirmation()
            } label: {
                Text("立即缴费").font(.headline).frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
            .campusActionControl()
            .disabled(!canPayDisplayedAmount)
            Text("从一卡通余额扣款，确认后即支付")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 720)
        .background(chassisSurface(cornerRadius: 22))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.09), radius: 10, x: 0, y: 4)
        .padding(.horizontal, AppLayout.pageInset)
        .padding(.top, 8).padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground).opacity(0.97).ignoresSafeArea(edges: .bottom))
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

private struct SevenSegmentBalanceDisplay: View {
    let value: String
    let ink: Color
    @ScaledMetric(relativeTo: .largeTitle) private var digitHeight: CGFloat = 44

    static func canRender(_ value: String) -> Bool {
        let characters = Array(value)
        guard !characters.isEmpty, characters.count <= 12 else { return false }
        var hasDigit = false
        var hasDecimal = false
        for (index, character) in characters.enumerated() {
            if let ascii = character.asciiValue, (48...57).contains(ascii) {
                hasDigit = true
            } else if character == ".", !hasDecimal, hasDigit, index < characters.count - 1 {
                hasDecimal = true
            } else if character == "-", index == 0 {
                continue
            } else {
                return false
            }
        }
        return hasDigit
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: digitHeight * 0.055) {
            ForEach(Array(value.enumerated()), id: \.offset) { item in
                if item.element == "." {
                    Circle()
                        .fill(ink.opacity(0.92))
                        .frame(width: digitHeight * 0.12, height: digitHeight * 0.12)
                        .padding(.horizontal, digitHeight * 0.035)
                        .padding(.bottom, digitHeight * 0.055)
                } else {
                    SevenSegmentDigit(character: item.element, ink: ink)
                        .frame(width: digitHeight * 0.60, height: digitHeight)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }
}

private struct SevenSegmentDigit: View {
    private enum Segment: CaseIterable, Hashable {
        case top, upperRight, lowerRight, bottom, lowerLeft, upperLeft, middle
    }

    let character: Character
    let ink: Color

    private var activeSegments: Set<Segment> {
        switch character {
        case "0": return [.top, .upperRight, .lowerRight, .bottom, .lowerLeft, .upperLeft]
        case "1": return [.upperRight, .lowerRight]
        case "2": return [.top, .upperRight, .middle, .lowerLeft, .bottom]
        case "3": return [.top, .upperRight, .middle, .lowerRight, .bottom]
        case "4": return [.upperLeft, .middle, .upperRight, .lowerRight]
        case "5": return [.top, .upperLeft, .middle, .lowerRight, .bottom]
        case "6": return [.top, .upperLeft, .middle, .lowerRight, .bottom, .lowerLeft]
        case "7": return [.top, .upperRight, .lowerRight]
        case "8": return Set(Segment.allCases)
        case "9": return [.top, .upperRight, .lowerRight, .bottom, .upperLeft, .middle]
        case "-": return [.middle]
        default: return []
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let thickness = max(1.5, height * 0.085)
            let horizontalLength = max(0, width - thickness * 1.8)
            let verticalLength = max(0, (height - thickness * 3) / 2)

            ZStack {
                segment(.top, width: horizontalLength, height: thickness,
                        x: width / 2, y: thickness / 2)
                segment(.middle, width: horizontalLength, height: thickness,
                        x: width / 2, y: height / 2)
                segment(.bottom, width: horizontalLength, height: thickness,
                        x: width / 2, y: height - thickness / 2)
                segment(.upperLeft, width: thickness, height: verticalLength,
                        x: thickness / 2, y: thickness + verticalLength / 2)
                segment(.upperRight, width: thickness, height: verticalLength,
                        x: width - thickness / 2, y: thickness + verticalLength / 2)
                segment(.lowerLeft, width: thickness, height: verticalLength,
                        x: thickness / 2, y: height - thickness - verticalLength / 2)
                segment(.lowerRight, width: thickness, height: verticalLength,
                        x: width - thickness / 2, y: height - thickness - verticalLength / 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func segment(_ segment: Segment, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Capsule()
            .fill(ink.opacity(activeSegments.contains(segment) ? 0.92 : 0.055))
            .frame(width: width, height: height)
            .position(x: x, y: y)
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
