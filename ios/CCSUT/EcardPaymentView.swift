import SwiftUI
import WebKit
import Combine

struct EcardPaymentView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var model = EcardPaymentModel()
    @State private var showingRecoveryHelp = false
    @State private var activeSelection: MeterSelectionField?

    init() {
        let value = EcardPaymentModel()
        #if DEBUG
        if InterfacePreview.enabled && (InterfacePreview.page == "campus" || InterfacePreview.page.hasPrefix("campus-electricity")) {
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
        PageScrollSurface(refresh: { await model.refreshMeter(account: session.studentId) }, refreshHaptics: true) { viewport, _ in
            let meterWidth = max(280, min(390, viewport.width - 24))
            instrumentPage(width: meterWidth)
                .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 14)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("电费缴费")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .safeAreaBar(edge: .top, spacing: 0) {
            HStack(spacing: 0) {
                NagiBackButton()
                Spacer(minLength: 0)
                Text("电费缴费")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("academic-detail-title")
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                Color.clear.frame(width: 48, height: 48).accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color(.systemGroupedBackground))
        }
        .background { AcademicPopSupport() }
        .sheet(item: $model.loginRequest, onDismiss: model.loginDismissed) { request in
            EcardLoginSheet(request: request)
        }
        .sheet(item: $model.confirmation) { confirmed in
            confirmation(confirmed)
                .presentationDetents([.large])
                .presentationDragIndicator(model.isSubmitting ? .hidden : .visible)
                .interactiveDismissDisabled(model.isSubmitting)
        }
        .sheet(isPresented: $showingRecoveryHelp) { recoveryHelp }
        .sheet(item: $activeSelection) { field in
            selectionInspectionPanel(field)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .onChange(of: session.studentId) { _, _ in
            showingRecoveryHelp = false
            activeSelection = nil
        }
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
            if InterfacePreview.enabled && (InterfacePreview.page == "campus" || InterfacePreview.page.hasPrefix("campus-electricity")) { return }
            #endif
            if session.studentId == nil { await session.loadProfile() }
            guard !Task.isCancelled else { return }
            model.start(account: session.studentId)
        }
        .onDisappear { model.stopQueries() }
    }

    private func instrumentPage(width: CGFloat) -> some View {
        let isRecovering = model.recoveryIssue != nil
        let hasReceipt = model.receipt != nil
        return VStack(spacing: -9) {
            meterHanger(width: min(88, width * 0.24))
                .frame(height: 34)
                .zIndex(1)

            meterHousing(width: width) {
                VStack(alignment: .leading, spacing: 7) {
                    if let issue = model.recoveryIssue {
                        recoveryCard(issue)
                    } else if let receipt = model.receipt {
                        result(receipt)
                    } else {
                        VStack(spacing: 7) {
                            engravedPlate
                            roomSelection
                            meterDisplay(model.detail)
                            observationSlot
                            amountSelection()
                        }
                    }
                    if model.recoveryIssue == nil, let message = model.errorText {
                        meterNotice(CampusPrivacy.redact(message)) {
                            if model.receipt == nil {
                                Button("重新加载") { model.start(account: session.studentId, force: true) }
                                    .buttonStyle(MeterKeyButtonStyle())
                            }
                        }
                    }
                    if model.receipt != nil, model.isStarting {
                        HStack(spacing: 8) {
                            ProgressView().tint(enamelInk)
                            Text("正在连接一卡通…").font(.footnote)
                        }
                        .foregroundStyle(enamelInk.opacity(0.76))
                        .padding(.top, 10)
                    }
                    if model.recoveryIssue == nil, model.canOpenLogin {
                        Button("打开认证页面", action: model.openLogin)
                            .buttonStyle(MeterKeyButtonStyle())
                            .padding(.top, 10)
                    }
                }
            }

            if !isRecovering && !hasReceipt {
                paymentTerminal(width: width)
            } else {
                sealedTerminalCover(width: width)
            }
        }
        .frame(maxWidth: width, alignment: .top)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func meterHanger(width: CGFloat) -> some View {
        ZStack {
            MeterHangerShape()
                .fill(LinearGradient(colors: bakeliteColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    MeterHangerShape().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.20), lineWidth: 1)
                }
            Circle()
                .fill(Color(.systemGroupedBackground))
                .frame(width: 13, height: 13)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.36), lineWidth: 1.2) }
                .shadow(color: .black.opacity(0.50), radius: 1.5, x: 0, y: 1)
                .offset(y: -3)
            Capsule()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.13 : 0.12))
                .frame(width: width * 0.28, height: 1)
                .offset(y: 11)
        }
        .frame(width: width * 0.58, height: 38)
        .accessibilityHidden(true)
    }

    private func meterHousing<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let horizontalRim = max(20, width * 0.055)
        let verticalRim = max(18, width * 0.05)
        return content()
            .padding(.horizontal, horizontalRim + 8)
            .padding(.vertical, verticalRim + 6)
            .frame(width: width)
            .frame(minHeight: width * 0.92)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LinearGradient(colors: engravedPlateColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(LinearGradient(colors: enamelColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(3)
                }
                .padding(.horizontal, horizontalRim)
                .padding(.vertical, verticalRim)
            }
            .background {
                MeterBakeliteShape()
                    .fill(LinearGradient(colors: bakeliteColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                MeterBakeliteShape().strokeBorder(LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.24 : 0.22),
                             Color.black.opacity(0.78),
                             Color.white.opacity(colorScheme == .dark ? 0.10 : 0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1.2)
            }
            .overlay {
                MeterBakeliteShape().inset(by: 4).strokeBorder(Color.black.opacity(0.68), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                    .clipShape(MeterBakeliteShape())
                    .allowsHitTesting(false)
            }
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        meterFastener().position(x: 15, y: 15)
                        meterFastener().position(x: geometry.size.width - 15, y: 15)
                        meterFastener().position(x: 15, y: geometry.size.height - 15)
                        meterFastener().position(x: geometry.size.width - 15, y: geometry.size.height - 15)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.52 : 0.34), radius: 10, x: 0, y: 7)
    }

    private func terminalHousing<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 7) { content() }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .frame(width: width)
            .background {
                MeterBakeliteShape()
                    .fill(LinearGradient(colors: bakeliteColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        MeterBakeliteShape().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
                    .overlay {
                        MeterBakeliteShape().inset(by: 3).strokeBorder(Color.black.opacity(0.76), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.36), radius: 4, x: 0, y: 3)
    }

    private var bakeliteColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.16, green: 0.17, blue: 0.17), Color(red: 0.035, green: 0.04, blue: 0.042), Color(red: 0.12, green: 0.13, blue: 0.13)]
            : [Color(red: 0.20, green: 0.21, blue: 0.21), Color(red: 0.045, green: 0.05, blue: 0.052), Color(red: 0.15, green: 0.16, blue: 0.16)]
    }

    private var enamelColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.72, green: 0.69, blue: 0.61), Color(red: 0.57, green: 0.55, blue: 0.49)]
            : [Color(red: 0.98, green: 0.96, blue: 0.88), Color(red: 0.91, green: 0.88, blue: 0.78)]
    }

    private var engravedPlateColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.48, green: 0.47, blue: 0.42), Color(red: 0.37, green: 0.37, blue: 0.34)]
            : [Color(red: 0.84, green: 0.82, blue: 0.75), Color(red: 0.68, green: 0.68, blue: 0.62)]
    }

    private var enamelInk: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.12) : Color(red: 0.15, green: 0.16, blue: 0.15)
    }

    private var counterInk: Color { Color(red: 0.94, green: 0.93, blue: 0.86) }

    private var engravedPlateFill: LinearGradient {
        LinearGradient(colors: engravedPlateColors, startPoint: .top, endPoint: .bottom)
    }

    private func meterFastener() -> some View {
        Circle()
            .fill(LinearGradient(colors: [Color.white.opacity(0.76), Color(red: 0.40, green: 0.41, blue: 0.40)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Circle().strokeBorder(Color.black.opacity(0.76), lineWidth: 0.8) }
            .overlay {
                ZStack {
                    Capsule().fill(Color.black.opacity(0.78)).frame(width: 5, height: 1)
                    Capsule().fill(Color.black.opacity(0.72)).frame(width: 1, height: 5)
                }
                .rotationEffect(.degrees(-28))
            }
            .frame(width: 9, height: 9)
    }

    private var observationSlot: some View {
        Capsule()
            .fill(LinearGradient(colors: [Color.black, Color(red: 0.04, green: 0.05, blue: 0.05), Color.black],
                                 startPoint: .top, endPoint: .bottom))
            .frame(height: 15)
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.42), lineWidth: 0.8) }
            .overlay {
                Circle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.76), Color(red: 0.43, green: 0.44, blue: 0.41), .black],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 13, height: 13)
                    .overlay { Circle().strokeBorder(Color.black.opacity(0.78), lineWidth: 1) }
            }
            .padding(.horizontal, 24)
            .accessibilityHidden(true)
    }

    private var meterSealWire: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: 12, y: 16), control: CGPoint(x: 0, y: 10))
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: 26, y: 16), control: CGPoint(x: 24, y: 5))
        }
        .stroke(Color(red: 0.57, green: 0.38, blue: 0.22), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        .frame(width: 28, height: 17)
        .overlay(alignment: .bottomTrailing) {
            Circle().fill(Color(red: 0.70, green: 0.51, blue: 0.32)).frame(width: 5, height: 5)
        }
        .accessibilityHidden(true)
    }

    private func sealedTerminalCover(width: CGFloat) -> some View {
        terminalHousing(width: min(270, width * 0.76)) {
            HStack {
                meterFastener()
                Spacer()
                Text(model.recoveryIssue != nil ? "订单核实" : "缴费结果")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Color.white.opacity(0.78))
                Spacer()
                meterFastener()
            }
            .frame(minHeight: 36)
            .overlay(alignment: .bottom) { meterSealWire }
        }
        .padding(.top, 1)
    }

    private var engravedPlate: some View {
        HStack(spacing: 7) {
            meterFastener()
            Image(systemName: "bolt.fill")
                .font(.caption2.weight(.bold)).foregroundStyle(enamelInk.opacity(0.78))
                .accessibilityHidden(true)
            Text("电费计量")
                .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(enamelInk)
            Spacer(minLength: 6)
            Text(CampusPrivacy.redact(model.detail?.meterTypeName ?? "电费"))
                .font(.caption2.weight(.medium)).foregroundStyle(enamelInk.opacity(0.70))
                .lineLimit(1).minimumScaleFactor(0.75)
            meterFastener()
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(engravedPlateFill)
        .overlay {
            Rectangle().strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.40 : 0.46), lineWidth: 0.8)
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.42)).frame(height: 0.7) }
        .accessibilityElement(children: .combine)
    }

    private var meterSeam: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Color.black.opacity(0.42), Color.white.opacity(0.38), Color.black.opacity(0.30)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var roomSelection: some View {
        VStack(spacing: 0) {
            if model.campuses.count > 1 {
                selectorWindow(field: .campus, symbol: "mappin.and.ellipse", placeholder: "请选择校区",
                               options: model.campuses, value: model.campus)
                meterSeam
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    selectorWindow(field: .building, symbol: "building.2", placeholder: "选择楼栋",
                                   options: model.buildings, value: model.building)
                    Rectangle().fill(Color.black.opacity(0.22)).frame(width: 1).accessibilityHidden(true)
                    selectorWindow(field: .room, symbol: "door.left.hand.closed", placeholder: "选择房间",
                                   options: model.rooms, value: model.room)
                }
                VStack(spacing: 0) {
                    selectorWindow(field: .building, symbol: "building.2", placeholder: "选择楼栋",
                                   options: model.buildings, value: model.building)
                    meterSeam
                    selectorWindow(field: .room, symbol: "door.left.hand.closed", placeholder: "选择房间",
                                   options: model.rooms, value: model.room)
                }
            }
            if model.isStarting || model.loadingText != nil {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small).tint(enamelInk)
                    Text(model.loadingText ?? "正在连接一卡通…")
                        .font(.caption2).foregroundStyle(enamelInk.opacity(0.76))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
        .background {
            Rectangle().fill(LinearGradient(colors: enamelColors, startPoint: .top, endPoint: .bottom))
        }
        .overlay { Rectangle().strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.32 : 0.42), lineWidth: 1) }
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.36)).frame(height: 0.8) }
        .accessibilityElement(children: .contain)
    }

    private func selectorWindow(field: MeterSelectionField, symbol: String, placeholder: String,
                                options: [ThirdOption], value: String?) -> some View {
        let selectedName = CampusPrivacy.redact(options.first(where: { $0.value == value })?.name ?? placeholder)
        return Button { activeSelection = field } label: {
            HStack(alignment: .center, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(field.title, systemImage: symbol)
                        .font(.caption2.weight(.semibold)).foregroundStyle(enamelInk.opacity(0.68))
                    Text(selectedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(value == nil ? enamelInk.opacity(0.68) : enamelInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold)).foregroundStyle(enamelInk.opacity(0.62))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.12))
        .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { gesture in
            turnSelector(field, options: options, value: value, horizontal: gesture.translation.width,
                         vertical: gesture.translation.height)
        })
        .disabled(options.isEmpty || model.isSubmitting)
        .accessibilityLabel("选择\(field.title)")
        .accessibilityValue(selectedName)
        .accessibilityIdentifier(field.controlIdentifier)
    }

    private func turnSelector(_ field: MeterSelectionField, options: [ThirdOption], value: String?,
                              horizontal: CGFloat, vertical: CGFloat) {
        guard !model.isSubmitting,
              abs(horizontal) >= 30,
              abs(horizontal) > abs(vertical) * 1.25,
              let current = options.firstIndex(where: { $0.value == value }) else { return }
        let next = current + (horizontal < 0 ? 1 : -1)
        guard options.indices.contains(next), options[next].value != value else { return }
        select(field, value: options[next].value)
    }

    private func selectionOptions(_ field: MeterSelectionField) -> [ThirdOption] {
        switch field {
        case .campus: return model.campuses
        case .building: return model.buildings
        case .room: return model.rooms
        }
    }

    private func selectedValue(_ field: MeterSelectionField) -> String? {
        switch field {
        case .campus: return model.campus
        case .building: return model.building
        case .room: return model.room
        }
    }

    private func select(_ field: MeterSelectionField, value: String?) {
        switch field {
        case .campus: model.selectCampus(value)
        case .building: model.selectBuilding(value)
        case .room: model.selectRoom(value)
        }
    }

    private func selectionInspectionPanel(_ field: MeterSelectionField) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("选择\(field.title)")
                        .font(.headline.weight(.semibold)).foregroundStyle(Color.white.opacity(0.92))
                    Spacer(minLength: 12)
                    Button("关闭") { activeSelection = nil }
                        .buttonStyle(MeterKeyButtonStyle())
                        .accessibilityIdentifier("meter-selection-close")
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(LinearGradient(colors: bakeliteColors, startPoint: .top, endPoint: .bottom))
                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(Array(selectionOptions(field).enumerated()), id: \.element.value) { item in
                            let option = item.element
                            let selected = option.value == selectedValue(field)
                            Button {
                                if !selected { select(field, value: option.value) }
                                activeSelection = nil
                            } label: {
                                HStack(spacing: 12) {
                                    Text(CampusPrivacy.redact(option.name))
                                        .font(.body.weight(selected ? .semibold : .regular))
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 8)
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.bold)).accessibilityHidden(true)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            }
                            .buttonStyle(MeterKeyButtonStyle())
                            .accessibilityLabel(CampusPrivacy.redact(option.name))
                            .accessibilityValue(selected ? "已选择" : "")
                            .accessibilityIdentifier("meter-option-\(field.rawValue)-\(item.offset)")
                        }
                    }
                    .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("选择\(field.title)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func recoveryCard(_ issue: EcardReceiptRecoveryError) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("待确认订单需要恢复", systemImage: "exclamationmark.shield")
                .font(.title3.weight(.semibold)).foregroundStyle(enamelInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(issue.localizedDescription)
                .foregroundStyle(enamelInk.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
            Text("在找回原订单并核实结果前，暂不能发起新的缴费。")
                .font(.footnote).foregroundStyle(enamelInk.opacity(0.68))
            Button("重试读取") { model.retryRecovery(account: session.studentId) }
                .buttonStyle(MeterKeyButtonStyle())
                .disabled(model.isStarting || model.isSubmitting || model.isChecking)
                .accessibilityIdentifier("payment-recovery-retry")
            Button { showingRecoveryHelp = true } label: {
                Text("核实原订单").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(MeterKeyButtonStyle())
            .accessibilityIdentifier("payment-recovery-help")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recoveryHelp: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("核实原订单").font(.headline.weight(.semibold)).foregroundStyle(Color.white.opacity(0.92))
                    Spacer()
                    Button("关闭") { showingRecoveryHelp = false }
                        .buttonStyle(MeterKeyButtonStyle())
                        .accessibilityIdentifier("payment-recovery-close")
                }
                .padding(16).background(LinearGradient(colors: bakeliteColors, startPoint: .top, endPoint: .bottom))
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("先核实，再处理").font(.title2.weight(.semibold))
                        Text("请通过学校官方缴费记录或联系一卡通服务人员，核实上次电费缴费的扣款与到账情况。可准备缴费时间、金额和房间信息，避免再次缴费。")
                        Text("如果只是暂时无法读取，解锁设备后返回重试；如果提示版本不支持，请更新 App 后重试。请保留此 App 的数据，卸载或清除数据可能丢失原订单线索。")
                        Text("本页只提供处理说明，不会查询服务器或解锁付款。即使已在线下核实，也不能在这里手动确认或清除记录。找回原待确认记录后，App 才能继续查询原订单；记录仍无法恢复时，请保留现状等待进一步处理。")
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18).frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("核实原订单").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func meterNotice<Actions: View>(_ message: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote).foregroundStyle(enamelInk.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            actions()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(engravedPlateFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.24 : 0.12), lineWidth: 1)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
    }

    private func meterDisplay(_ detail: MeterDetail?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("剩余金额")
                    .font(.caption.weight(.bold)).foregroundStyle(enamelInk.opacity(0.72))
                Spacer(minLength: 6)
                if (detail?.remainingAmount ?? 0) < 0 {
                    Text("当前欠费")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Color(red: 0.64, green: 0.20, blue: 0.15))
                }
            }
            if let detail {
                balance(detail)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(CampusPrivacy.redact(detail.roomDescription ?? "—"))
                        Spacer(minLength: 0)
                        Text(CampusPrivacy.redact(detail.meterTypeName ?? "—"))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CampusPrivacy.redact(detail.roomDescription ?? "—"))
                        Text(CampusPrivacy.redact(detail.meterTypeName ?? "—"))
                    }
                }
                .font(.caption2).foregroundStyle(enamelInk.opacity(0.70))
                .lineLimit(1).minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.isStarting ? "正在读取余额…" : "余额暂不可用")
                    .font(.subheadline.weight(.medium)).foregroundStyle(enamelInk.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var counterGlass: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.035, green: 0.043, blue: 0.042), Color(red: 0.12, green: 0.13, blue: 0.12), Color(red: 0.025, green: 0.03, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.8)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 5)
            }
    }

    private func balance(_ detail: MeterDetail) -> some View {
        let rawValue = detail.show["剩余金额"] ?? "—"
        let valueInk = (detail.remainingAmount ?? 0) < 0 ? Color(red: 0.98, green: 0.48, blue: 0.38) : counterInk
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            if MechanicalBalanceCounter.canRender(rawValue) {
                MechanicalBalanceCounter(value: rawValue, ink: valueInk)
                Text("元").font(.caption.weight(.medium)).foregroundStyle(counterInk.opacity(0.78))
            } else {
                Text(rawValue)
                    .font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.45).foregroundStyle(valueInk)
                Text("元").font(.caption.weight(.medium)).foregroundStyle(counterInk.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 43, alignment: .center)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(counterGlass)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余金额")
        .accessibilityValue("\(rawValue) 元")
    }

    private func amountSelection() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("充值金额")
                    .font(.caption.weight(.bold)).foregroundStyle(enamelInk.opacity(0.76))
                Spacer(minLength: 4)
                Text("¥\(amountValue) 元")
                    .font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(enamelInk.opacity(0.70))
            }
            HStack(spacing: 5) {
                amountThumbwheel(place: 100, label: "百位")
                amountThumbwheel(place: 10, label: "十位")
                amountThumbwheel(place: 1, label: "个位")
            }
            .padding(.horizontal, 3)
            Text(amountMaximum >= MeterAmount.minimum
                 ? "可充值 \(MeterAmount.minimum)–\(amountMaximum) 元"
                 : "正在获取可充值金额范围")
                .font(.caption2).foregroundStyle(enamelInk.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .center)
            if let hint = model.amountHint {
                Label(hint, systemImage: "exclamationmark.circle")
                    .font(.caption2).foregroundStyle(Color(red: 0.67, green: 0.18, blue: 0.12))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var amountPresetKeys: some View {
        ForEach([50, 100, 200], id: \.self) { amount in
            Button {
                model.amountText = String(MeterAmount.clamp(amount, maximum: amountMaximum))
            } label: {
                Text("\(amount) 元")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(MeterKeyButtonStyle())
            .disabled(amountMaximum < amount || model.isSubmitting)
            .accessibilityLabel("充值\(amount)元")
            .accessibilityAddTraits(amountValue == amount ? [.isSelected] : [])
            .accessibilityIdentifier("meter-preset-\(amount)")
        }
    }

    private func amountThumbwheel(place: Int, label: String) -> some View {
        let currentDigit = amountValue / place % 10
        return VStack(spacing: 2) {
            MeterRollingGlyph(value: String(currentDigit), foreground: drumInk, height: 42)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(counterRollSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 10).onEnded { gesture in
                    guard !model.isSubmitting,
                          amountMaximum >= MeterAmount.minimum,
                          abs(gesture.translation.height) >= 8 else { return }
                    let direction = gesture.translation.height < 0 ? 1 : -1
                    guard canAdjustDigit(place: place, direction: direction) else { return }
                    let steps = max(1, Int(abs(gesture.translation.height) / 24))
                    adjustDigit(place: place, direction: direction, steps: steps)
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("金额\(label)")
                .accessibilityValue("\(currentDigit)")
                .accessibilityAdjustableAction { direction in
                    guard !model.isSubmitting, amountMaximum >= MeterAmount.minimum else { return }
                    switch direction {
                    case .increment:
                        guard canAdjustDigit(place: place, direction: 1) else { return }
                        adjustDigit(place: place, direction: 1)
                    case .decrement:
                        guard canAdjustDigit(place: place, direction: -1) else { return }
                        adjustDigit(place: place, direction: -1)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("meter-digit-\(place)")

            HStack(spacing: 3) {
                amountArrowButton(place: place, label: label, direction: -1)
                amountArrowButton(place: place, label: label, direction: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var counterRollSurface: LinearGradient {
        LinearGradient(colors: [Color(red: 0.035, green: 0.043, blue: 0.042), Color(red: 0.13, green: 0.14, blue: 0.13)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var drumInk: Color { Color(red: 0.94, green: 0.93, blue: 0.86) }

    private func amountArrowButton(place: Int, label: String, direction: Int) -> some View {
        let increasing = direction > 0
        return Button {
            adjustDigit(place: place, direction: direction)
        } label: {
            Image(systemName: increasing ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.white.opacity(0.84))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    LinearGradient(colors: [Color(red: 0.27, green: 0.28, blue: 0.28), Color(red: 0.10, green: 0.11, blue: 0.11)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay { Rectangle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7) }
                .contentShape(Rectangle())
        }
        .buttonStyle(MeterActuatorButtonStyle())
        .disabled(!canAdjustDigit(place: place, direction: direction) || model.isSubmitting)
        .accessibilityLabel("\(increasing ? "增加" : "减少")金额\(label)")
        .accessibilityIdentifier("meter-digit-\(place)-\(increasing ? "increase" : "decrease")")
    }

    private func canAdjustDigit(place: Int, direction: Int) -> Bool {
        let allowed = MeterAmount.digits(amount: amountValue, place: place, maximum: amountMaximum)
        guard let index = allowed.firstIndex(of: amountValue / place % 10) else { return false }
        return direction > 0 ? index < allowed.count - 1 : index > 0
    }

    private func adjustDigit(place: Int, direction: Int, steps: Int = 1) {
        guard amountMaximum >= MeterAmount.minimum, !model.isSubmitting else { return }
        var amount = MeterAmount.clamp(amountValue, maximum: amountMaximum)
        for _ in 0..<max(1, steps) {
            let allowed = MeterAmount.digits(amount: amount, place: place, maximum: amountMaximum)
            let current = amount / place % 10
            guard let index = allowed.firstIndex(of: current) else { break }
            let nextIndex = index + (direction > 0 ? 1 : -1)
            guard allowed.indices.contains(nextIndex) else { break }
            amount = MeterAmount.replacing(amount: amount, place: place, digit: allowed[nextIndex], maximum: amountMaximum)
            amount = MeterAmount.clamp(amount, maximum: amountMaximum)
        }
        guard amount != amountValue else { return }
        model.amountText = String(amount)
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

    private func paymentTerminal(width: CGFloat) -> some View {
        terminalHousing(width: max(250, width * 0.88)) {
            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    meterFastener()
                    Text("充值预置")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Color.white.opacity(0.74))
                    Spacer(minLength: 2)
                    Text("¥\(amountValue)")
                        .font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(Color.white.opacity(0.88))
                    meterFastener()
                }
                HStack(spacing: 3) { amountPresetKeys }

                Button {
                    guard canPayDisplayedAmount else { return }
                    model.prepareConfirmation()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "bolt.fill").accessibilityHidden(true)
                        Text("立即缴费").font(.headline.weight(.bold))
                        Spacer(minLength: 4)
                        Text("确认").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Color(red: 0.99, green: 0.94, blue: 0.87))
                    .padding(.horizontal, 13)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(actuatorSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.58), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.38), radius: 1.5, x: 0, y: 2)
                }
                .buttonStyle(MeterActuatorButtonStyle())
                .disabled(!canPayDisplayedAmount)
                .accessibilityLabel("立即缴费")
                Text("从一卡通余额扣款，确认后即支付")
                    .font(.caption2).foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                meterSealWire
            }
        }
        .padding(.top, 1)
    }

    private var actuatorSurface: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.54, green: 0.24, blue: 0.19), Color(red: 0.32, green: 0.12, blue: 0.11)]
                    : [Color(red: 0.68, green: 0.31, blue: 0.24), Color(red: 0.47, green: 0.17, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 18).allowsHitTesting(false)
            }
    }

    private func confirmation(_ confirmed: EcardPaymentModel.Confirmation) -> some View {
        GeometryReader { geometry in
            let width = max(280, min(390, geometry.size.width - 32))
            ScrollView {
                VStack(spacing: -9) {
                    meterHanger(width: min(88, width * 0.24))
                        .frame(height: 34).zIndex(1)
                    meterHousing(width: width) {
                        VStack(alignment: .leading, spacing: 9) {
                            engravedPlate
                            HStack(alignment: .center) {
                                Text("确认缴费")
                                    .font(.subheadline.weight(.bold)).foregroundStyle(enamelInk)
                                Spacer(minLength: 4)
                                if !model.isSubmitting {
                                    Button("关闭确认缴费") { model.confirmation = nil }
                                        .buttonStyle(MeterKeyButtonStyle())
                                }
                            }
                            Text("支付明细")
                                .font(.caption.weight(.bold)).foregroundStyle(enamelInk.opacity(0.72))
                            Text("¥\(confirmed.amount.ecardAmountText) 元")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                                .foregroundStyle(enamelInk).fixedSize(horizontal: false, vertical: true)
                            meterSeam
                            info("缴费房间", confirmed.room)
                            info("支付方式", "一卡通余额")
                            Text("这是免密支付。请确认房间与金额，点击下方按钮后将直接扣款。")
                                .font(.footnote).foregroundStyle(enamelInk.opacity(0.76))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    terminalHousing(width: width * 0.88) {
                        if model.isSubmitting {
                            HStack(spacing: 10) {
                                ProgressView().tint(Color.white)
                                Text("正在提交，请勿重复缴费")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.white.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        } else {
                            Button { Task { await model.submit(confirmed) } } label: {
                                Text("确认支付 \(confirmed.amount.ecardAmountText) 元")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(Color(red: 0.99, green: 0.94, blue: 0.87))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(actuatorSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(MeterActuatorButtonStyle())
                        }
                        meterSealWire
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func result(_ receipt: EcardPaymentModel.Receipt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: receipt.status == .completed ? "checkmark.circle.fill" : receipt.status == .pending ? "clock.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(receipt.status == .completed ? Color(red: 0.27, green: 0.43, blue: 0.32) : receipt.status == .pending ? .orange : .red)
                .frame(maxWidth: .infinity, alignment: .center).accessibilityHidden(true)
            Text(receipt.status == .completed ? "缴费成功" : receipt.status == .pending ? "结果待确认" : "缴费未完成")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(enamelInk)
            Text("¥\(CampusPrivacy.redact(receipt.amount))")
                .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(enamelInk).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
            info("缴费房间", receipt.room)
            meterSeam
            if let message = receipt.message {
                Text(CampusPrivacy.redact(message)).font(.footnote).foregroundStyle(enamelInk.opacity(0.76))
            }
            Text(receipt.status == .pending ? "支付结果尚未确认，请查询原订单，勿重复缴费。" : receipt.status == .completed ? "电表到账约 1–5 分钟" : "缴费成功后，电表到账约 1–5 分钟")
                .font(.subheadline).foregroundStyle(enamelInk.opacity(0.76)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let orderID = receipt.orderID {
                Text("订单号 \(CampusPrivacy.redact(orderID))").font(.caption).foregroundStyle(enamelInk.opacity(0.65)).textSelection(.enabled)
            }
            if receipt.status == .pending {
                Button { Task { await model.checkOrder() } } label: {
                    HStack(spacing: 8) {
                        if model.isChecking { ProgressView().tint(enamelInk) }
                        Text("查询支付结果")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(MeterKeyButtonStyle())
                .disabled(model.isChecking || model.isStarting)
            } else {
                Button(receipt.status == .completed ? "返回缴费页面" : "返回修改") { model.returnToForm() }
                    .buttonStyle(MeterKeyButtonStyle())
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(enamelInk.opacity(0.68))
            Spacer(minLength: 4)
            Text(CampusPrivacy.redact(value)).font(.subheadline.weight(.semibold))
                .foregroundStyle(enamelInk).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true).privacySensitive()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(engravedPlateFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum MeterSelectionField: String, Identifiable {
    case campus, building, room

    var id: Self { self }
    var title: String {
        switch self {
        case .campus: return "校区"
        case .building: return "楼栋"
        case .room: return "房间"
        }
    }
    var controlIdentifier: String { "meter-\(rawValue)-selector" }
}

private struct MeterKeyButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: 44)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.36, green: 0.37, blue: 0.37), Color(red: 0.17, green: 0.18, blue: 0.18)]
                            : [Color(red: 0.90, green: 0.90, blue: 0.86), Color(red: 0.60, green: 0.62, blue: 0.60)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.38 : 0.18), lineWidth: 0.8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.72), lineWidth: 0.7)
                            .padding(2)
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: configuration.isPressed ? 0.5 : 2,
                            x: 0, y: configuration.isPressed ? 0.5 : 1.5)
            }
            .offset(y: configuration.isPressed && !reduceMotion ? 1.5 : 0)
            .opacity(isEnabled ? 1 : 0.46)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct MeterActuatorButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed && !reduceMotion ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.46)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct MeterBakeliteShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cut = min(18, min(bounds.width, bounds.height) * 0.075)
        var path = Path()
        path.move(to: CGPoint(x: bounds.minX + cut, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX - cut, y: bounds.minY))
        path.addQuadCurve(to: CGPoint(x: bounds.maxX, y: bounds.minY + cut),
                          control: CGPoint(x: bounds.maxX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - cut))
        path.addQuadCurve(to: CGPoint(x: bounds.maxX - cut, y: bounds.maxY),
                          control: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX + cut, y: bounds.maxY))
        path.addQuadCurve(to: CGPoint(x: bounds.minX, y: bounds.maxY - cut),
                          control: CGPoint(x: bounds.minX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + cut))
        path.addQuadCurve(to: CGPoint(x: bounds.minX + cut, y: bounds.minY),
                          control: CGPoint(x: bounds.minX, y: bounds.minY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct MeterHangerShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let shoulderY = bounds.minY + bounds.height * 0.58
        var path = Path()
        path.move(to: CGPoint(x: bounds.minX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX + bounds.width * 0.14, y: shoulderY))
        path.addLine(to: CGPoint(x: bounds.minX + bounds.width * 0.34, y: bounds.minY + 2))
        path.addQuadCurve(to: CGPoint(x: bounds.minX + bounds.width * 0.66, y: bounds.minY + 2),
                          control: CGPoint(x: bounds.midX, y: bounds.minY - bounds.height * 0.04))
        path.addLine(to: CGPoint(x: bounds.maxX - bounds.width * 0.14, y: shoulderY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct MeterRollingGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: String
    let foreground: Color
    let height: CGFloat

    var body: some View {
        ZStack {
            Text(value)
                .font(.system(size: max(18, height * 0.70), weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(foreground)
                .id(value)
                .transition(reduceMotion
                    ? AnyTransition.identity
                    : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                  removal: .move(edge: .bottom).combined(with: .opacity)))
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: value)
    }
}

private struct MechanicalBalanceCounter: View {
    let value: String
    let ink: Color
    @ScaledMetric(relativeTo: .largeTitle) private var glyphHeight: CGFloat = 34

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
        HStack(spacing: 1) {
            ForEach(Array(value.enumerated()), id: \.offset) { item in
                if item.offset > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 0.8, height: glyphHeight * 0.78)
                        .accessibilityHidden(true)
                }
                MeterRollingGlyph(value: String(item.element), foreground: ink, height: glyphHeight)
                    .frame(width: glyphHeight * (item.element == "." ? 0.30 : 0.55), height: glyphHeight)
                    .background(LinearGradient(colors: [Color(red: 0.12, green: 0.13, blue: 0.12), Color.black],
                                               startPoint: .top, endPoint: .bottom))
                    .overlay { Rectangle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.35) }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
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
