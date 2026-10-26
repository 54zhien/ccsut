import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

@MainActor struct CampusFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.deviceCornerRadius) private var deviceCornerRadius
    @State private var model: CampusFormModel
    @State private var location = CampusLocation()
    @State private var photo: PhotosPickerItem?
    @State private var importingFile = false
    @State private var isImporting = false
    @State private var isLocating = false
    @State private var activeEditor: String?
    @State private var formCornerRadius: CGFloat = 0
    @State private var reviewControlHeight: CGFloat = 0
    @State private var confirmationCornerRadius: CGFloat = 0
    @State private var confirmationControlHeight: CGFloat = 0
    @FocusState private var focusedPhone: String?
    @ScaledMetric private var editorHeight: CGFloat = 108
    @ScaledMetric private var shortEditorHeight: CGFloat = 44
    private let onSubmitted: () -> Void

    init(kind: CampusFormKind, account: String, onSubmitted: @escaping () -> Void = {}) {
        let api: any CampusFormServing
        let formAccount: String
        #if DEBUG
        formAccount = InterfacePreview.enabled && account.isEmpty ? "preview-account" : account
        if InterfacePreview.enabled { api = CampusFormPreviewAPI(account: formAccount, generation: CookieJar.generation) }
        else { api = CampusClient(account: formAccount, credentials: CampusCookieCredentials()) }
        #else
        formAccount = account
        api = CampusClient(account: account, credentials: CampusCookieCredentials())
        #endif
        _model = State(initialValue: CampusFormModel(kind: kind, account: formAccount, api: api, currentGeneration: { CookieJar.generation }))
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                VStack(spacing: 0) {
                    if model.state == .loading {
                        VStack(spacing: 14) {
                            ProgressView().accessibilityIdentifier("campus-form-loading-indicator")
                            Text("正在加载学校表单…").font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).accessibilityIdentifier("campus-form-loading-message")
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 24) {
                                    content
                                }
                                .padding(.horizontal, 16).padding(.vertical, 24)
                                .frame(maxWidth: 720).frame(maxWidth: .infinity)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .scrollEdgeEffectHidden(true, for: .top)
                            .disabled(model.state == .submitting || model.state == .unknown)
                            .onChange(of: activeEditor) { _, value in
                                if let value { proxy.scrollTo(value, anchor: .center) }
                            }
                            .onChange(of: focusedPhone) { _, value in
                                if let value { activeEditor = nil; proxy.scrollTo(value, anchor: .center) }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                                if let identifier = activeEditor ?? focusedPhone { proxy.scrollTo(identifier, anchor: .center) }
                            }
                        }
                    }
                }
                .background(Color(.systemGroupedBackground))
                .overlay(alignment: .top) { topBarMaterial }
                .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) { if model.state != .loading { footer(in: viewport) } }
                .navigationTitle(model.kind.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { dismiss() }
                        .foregroundStyle(.primary)
                        .tint(nil)
                        .accessibilityLabel("关闭\(model.kind.title)")
                        .accessibilityIdentifier("campus-form-close")
                        .disabled(model.state == .submitting)
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { endEditing() } }
                }
            }
            // Only the container edge is extended; the keyboard still lifts the footer.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background {
            ScreenCornerReader { formCornerRadius = $0 }
                .ignoresSafeArea()
        }
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .presentationDetents([.large])
        .presentationSizing(.page)
        .interactiveDismissDisabled(model.state == .submitting)
        .sheet(item: $model.confirmation) { confirmation($0) }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item]) { importFile($0) }
        .onChange(of: photo) { _, item in if let item { importPhoto(item) } }
        .task { await model.load() }
        .task(id: model.candidateKey) { await model.refreshApprovers() }
        .onDisappear { location.cancel(); model.stop() }
    }

    @ViewBuilder private var content: some View {
        if model.state == .submitted {
            ContentUnavailableView("已提交，等待审核", systemImage: "checkmark.circle", description: Text("可返回记录页查看学校处理结果。"))
                .accessibilityIdentifier("campus-form-submitted")
        } else if let c = model.configuration {
            section("申请内容") {
                choice("类型", options: c.choices, selection: binding(\.typeID))
                fieldError("类型")
                if model.kind == .departure || c.canLeaveSchool {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("是否离校").font(.subheadline).foregroundStyle(.secondary)
                        Picker("是否离校", selection: binding(\.leaving)) {
                            Text("请选择").tag(Optional<Bool>.none)
                            Text("离校").tag(Optional(true))
                            Text(model.kind == .leave ? "不离校" : "留校").tag(Optional(false))
                        }.pickerStyle(.segmented).accessibilityIdentifier("campus-form-leaving")
                    }
                    fieldError("是否离校")
                }
                if model.kind == .leave || model.draft.leaving == true { dates(c) }
            }
            if model.kind == .leave { leaveFields(c) }
            else { departureFields }
        } else {
            ContentUnavailableView("暂时无法加载表单", systemImage: "exclamationmark.icloud")
            Button("重新加载") { Task { await model.load(preservingDraft: true) } }.buttonStyle(.glass)
        }
    }

    private func dates(_ c: CampusFormConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            dateControl("开始时间", selection: binding(\.begin))
            dateControl("结束时间", selection: binding(\.end))
            fieldError("时间")
            if model.kind == .leave {
                LabeledContent("请假天数", value: model.draft.duration.formatted() + " 天")
                    .foregroundStyle(.secondary)
                if c.needsLeaveTime && model.draft.leaving == true {
                    if model.draft.actualLeaveTime == nil {
                        Button("选择离校时间") { model.update { $0.actualLeaveTime = $0.begin } }
                    } else {
                        dateControl("离校时间", selection: Binding(get: { model.draft.actualLeaveTime ?? model.draft.begin }, set: { date in model.update { $0.actualLeaveTime = date } }))
                    }
                }
            }
        }
    }

    @ViewBuilder private func dateControl(_ title: String, selection: Binding<Date>) -> some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                DatePicker(title, selection: selection, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().accessibilityLabel(title)
            }
        } else {
            DatePicker(title, selection: selection, displayedComponents: [.date, .hourAndMinute])
        }
    }

    @ViewBuilder private func leaveFields(_ c: CampusFormConfiguration) -> some View {
        section("请假事由") { editor("请假事由", key: \.reason, identifier: "campus-form-reason", showLabel: false); fieldError("事由") }
        section("联系与审批") {
            phone("紧急联系人电话", key: \.contactPhone, identifier: "campus-form-contact")
            if !c.contacts.isEmpty { choice("常用联系人", options: c.contacts, selection: binding(\.contactPhone)) }
            if !model.canMatchApprovers {
                Text(model.draft.typeID.isEmpty ? "请先选择请假类型，审批人会自动匹配" : "请先设置有效的开始和结束时间，审批人会自动匹配")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("campus-approver-prerequisite")
            } else if model.isLoadingApprovers {
                ProgressView("正在匹配审批人…").font(.footnote)
            } else if let approvers = model.approvers {
                choice(approvers.roleName, options: approvers.users, selection: binding(\.approverID))
                fieldError("审批")
            } else {
                Text(model.error ?? "暂未匹配到审批人，请重试")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("campus-approver-error")
                Button("重新匹配审批人") { Task { await model.refreshApprovers() } }
                    .accessibilityIdentifier("campus-approver-retry")
            }
        }
        if c.needsDestination {
            section("去向") {
                choice("去向类型", options: c.destinationTypes, selection: binding(\.destinationTypeID))
                editor("去向明细", key: \.destinationDetails, identifier: "campus-form-destination", short: true)
                fieldError("去向")
            }
        }
        if c.showLocation || c.needsLocation {
            section("当前位置") {
                if let address = model.draft.locationAddress { safeText(address).font(.subheadline) }
                Button { locate() } label: {
                    HStack { if isLocating { ProgressView() }; Label(isLocating ? "正在定位…" : "获取当前位置", systemImage: "location") }
                }.disabled(isLocating)
                fieldError("定位")
            }
        }
        if selectedType?.requiresImage == true || c.needsFiles { attachments(c) }
    }

    @ViewBuilder private var departureFields: some View {
        if model.draft.leaving == true {
            section("离校去向") {
                areas
                editor("详细地址", key: \.detailAddress, identifier: "campus-form-address", short: true)
                choice("交通方式", options: ["飞机","火车","汽车","步行","骑行"].map { .init(id:$0,name:$0) }, selection: binding(\.travelMethod))
                editor("车次 / 航班（选填）", key: \.tripNumber, identifier: "campus-form-trip", short: true)
                editor("事由（选填）", key: \.reason, identifier: "campus-form-reason")
                fieldError("目的地")
            }
        }
        section("联系方式") {
            phone("本人联系电话", key: \.phone, identifier: "campus-form-phone")
            phone("家长联系电话", key: \.parentPhone, identifier: "campus-form-parent")
        }
    }

    private var areas: some View {
        let provinces = CampusAreaCatalog.regions
        let province = model.draft.area.first ?? ""
        let cities = provinces.first { $0.name == province }?.children ?? []
        let city = model.draft.area.count > 1 ? model.draft.area[1] : ""
        let districts = cities.first { $0.name == city }?.children ?? []
        let district = model.draft.area.count > 2 ? model.draft.area[2] : ""
        return VStack(spacing: 14) {
            choice("目的地省份", options: provinces.map { .init(id:$0.name,name:$0.name) }, selection: Binding(get: { province }, set: { name in model.update { $0.area = [name] } }))
            choice("城市", options: cities.map { .init(id:$0.name,name:$0.name) }, selection: Binding(get: { city }, set: { name in model.update { $0.area = [province,name] } }))
            choice("区县", options: districts.map { .init(id:$0.name,name:$0.name) }, selection: Binding(get: { district }, set: { name in model.update { $0.area = [province,city,name] } }))
        }
    }

    private func attachments(_ c: CampusFormConfiguration) -> some View {
        section("证明材料") {
            ForEach(model.draft.attachments) { file in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        safeText(file.name).font(.subheadline)
                        Text(Int64(file.data.count), format: .byteCount(style: .file)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("移除", systemImage: "minus.circle") { model.update { $0.attachments.removeAll { $0.id == file.id } } }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
            }
            if selectedType?.requiresImage == true {
                PhotosPicker(selection: $photo, matching: .images) { Label("添加证明图片", systemImage: "photo.badge.plus") }
                    .disabled(isImporting || model.draft.attachments.filter(\.isImage).count >= c.photoLimit)
                Text("最多 \(c.photoLimit) 张证明图片").font(.footnote).foregroundStyle(.secondary)
            }
            if c.needsFiles { Button("添加附件", systemImage: "paperclip") { importingFile = true }.disabled(isImporting) }
            if isImporting { ProgressView("正在读取材料…").font(.footnote) }
            fieldError("附件"); fieldError("图片")
        }
    }

    private func footer(in viewport: GeometryProxy) -> some View {
        let radius = formCornerRadius > 0 ? formCornerRadius : deviceCornerRadius
        let inset = SheetLayout.controlInset(radius, diameter: reviewControlHeight)
        return VStack(alignment: .leading, spacing: 10) {
            if model.error != nil || (model.needsReload && model.state == .editing) {
                footerMessages
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footerAction
                .frame(width: footerControlWidth(in: viewport, inset: inset))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { reviewControlHeight = $0 }
                .padding(.leading, inset - viewport.safeAreaInsets.leading)
                .padding(.trailing, inset - viewport.safeAreaInsets.trailing)
        }
        .frame(width: viewport.size.width, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, inset)
    }

    // Constrain the native capsule independently of oversized form content.
    // https://developer.apple.com/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:)
    private func footerControlWidth(in viewport: GeometryProxy, inset: CGFloat) -> CGFloat {
        max(0, viewport.size.width + viewport.safeAreaInsets.leading + viewport.safeAreaInsets.trailing - 2 * inset)
    }

    private var footerMessages: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("campus-form-error")
                if error == CampusError.authentication.localizedDescription {
                    Button("重新认证") { Task { await session.refresh(); await model.load() } }
                }
            }
            if model.needsReload && model.state == .editing {
                Button("刷新配置并保留填写内容") { Task { await model.load(preservingDraft: true) } }
                    .accessibilityIdentifier("campus-form-reload")
            }
        }
    }

    @ViewBuilder private var footerAction: some View {
        // Fit only action labels; retain Dynamic Type throughout the form.
        // https://developer.apple.com/documentation/swiftui/view/minimumscalefactor(_:)
        if model.state == .unknown {
            Button { Task { await model.checkResult() } } label: {
                HStack {
                    if model.isChecking { ProgressView() }
                    Text("查询提交结果").lineLimit(1).minimumScaleFactor(0.5)
                }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.glassProminent).campusActionControl().disabled(model.isChecking)
        } else if model.state == .submitted {
            Button { onSubmitted(); dismiss() } label: {
                Text("完成").lineLimit(1).minimumScaleFactor(0.5)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.glassProminent).campusActionControl()
        } else if model.configuration != nil {
            Button { endEditing(); model.prepareConfirmation() } label: {
                Text("核对并提交").lineLimit(1).minimumScaleFactor(0.5)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.glassProminent).campusActionControl().disabled(!model.canReview || isImporting || isLocating)
                .accessibilityIdentifier("campus-form-review")
        }
    }

    private func confirmation(_ snapshot: CampusSubmission) -> some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        CampusSection("申请内容") {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    safeText(snapshot.configuration.choices.first { $0.id == snapshot.draft.typeID }?.name ?? "")
                                        .font(.title3.weight(.semibold))
                                    safeText(snapshot.configuration.displayName).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                CampusStatusBadge(text: snapshot.draft.leaving == true ? "离校" : (snapshot.kind == .leave ? "不离校" : "留校"))
                            }
                            if snapshot.kind == .leave || snapshot.draft.leaving == true {
                                Divider()
                                CampusDateRange(start: dateText(snapshot.draft.begin), end: dateText(snapshot.draft.end), chineseDates: true)
                            }
                            if snapshot.kind == .leave {
                                CampusInfoRow("请假天数", value: snapshot.draft.duration.formatted() + " 天")
                                if snapshot.draft.leaving == true, snapshot.configuration.needsLeaveTime, let time = snapshot.draft.actualLeaveTime {
                                    CampusInfoRow("离校时间", value: CampusDisplayDate.timestamp(dateText(time), chinese: true))
                                }
                            }
                        }
                        CampusSection(snapshot.kind == .leave ? "联系与审批" : "联系方式") {
                            if snapshot.kind == .leave {
                                CampusInfoRow("审批人", value: snapshot.approvers?.users.first { $0.id == snapshot.draft.approverID }?.name ?? "")
                                CampusInfoRow("紧急联系人电话", value: snapshot.draft.contactPhone)
                            } else {
                                CampusInfoRow("本人联系电话", value: snapshot.draft.phone)
                                CampusInfoRow("家长联系电话", value: snapshot.draft.parentPhone)
                            }
                        }
                        if snapshot.kind == .departure && snapshot.draft.leaving == true {
                            CampusSection("离校去向") {
                                CampusInfoRow("目的地", value: snapshot.draft.area.joined(separator: " / "))
                                safeText(snapshot.draft.detailAddress)
                                CampusInfoRow("交通方式", value: snapshot.draft.travelMethod)
                                CampusInfoRow("车次 / 航班", value: snapshot.draft.tripNumber)
                            }
                        }
                        if !snapshot.draft.reason.isEmpty {
                            CampusSection("事由") { safeText(snapshot.draft.reason) }
                        }
                        if snapshot.configuration.needsDestination {
                            CampusSection("去向") {
                                CampusInfoRow("去向类型", value: snapshot.configuration.destinationTypes.first { $0.id == snapshot.draft.destinationTypeID }?.name ?? "")
                                if !snapshot.draft.destinationDetails.isEmpty { safeText(snapshot.draft.destinationDetails) }
                            }
                        } else if !snapshot.draft.destinationDetails.isEmpty {
                            CampusSection("去向") { safeText(snapshot.draft.destinationDetails) }
                        }
                        if snapshot.configuration.showLocation || snapshot.configuration.needsLocation,
                           let address = snapshot.draft.locationAddress {
                            CampusSection("当前位置") { safeText(address) }
                        }
                        if !snapshot.draft.attachments.isEmpty {
                            CampusSection("证明材料 · \(snapshot.draft.attachments.count) 项") {
                                ForEach(snapshot.draft.attachments) { safeText($0.name).font(.subheadline) }
                            }
                        }
                        Text("确认后将提交学校审核。").font(.footnote).foregroundStyle(.secondary)
                    }.padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollEdgeEffectHidden(true, for: .top)
                .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
                    Button { Task { await model.submit(snapshot) } } label: {
                        HStack {
                            if model.state == .submitting { ProgressView() }
                            Text(model.state == .submitting ? "正在提交…" : "确认提交")
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.glassProminent).campusActionControl()
                        .frame(width: footerControlWidth(in: viewport, inset: confirmationControlInset))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { confirmationControlHeight = $0 }
                        .padding(.leading, confirmationControlInset - viewport.safeAreaInsets.leading)
                        .padding(.trailing, confirmationControlInset - viewport.safeAreaInsets.trailing)
                        .frame(width: viewport.size.width, alignment: .leading)
                        .padding(.top, 16)
                        .padding(.bottom, confirmationControlInset)
                        .disabled(model.state == .submitting)
                        .accessibilityIdentifier("campus-form-confirm")
                }
                .background(Color(.systemGroupedBackground))
                .overlay(alignment: .top) { topBarMaterial }
                .navigationTitle("核对申请")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { model.confirmation = nil }
                        .foregroundStyle(.primary)
                        .tint(nil)
                        .accessibilityLabel("关闭核对申请")
                        .accessibilityIdentifier("campus-form-confirm-close")
                        .disabled(model.state == .submitting)
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(Color(.systemGroupedBackground))
        .background {
            ScreenCornerReader { confirmationCornerRadius = $0 }
                .ignoresSafeArea()
        }
        .presentationDetents([.large]).presentationSizing(.page)
        .interactiveDismissDisabled(model.state == .submitting)
    }

    private var confirmationControlInset: CGFloat {
        let radius = confirmationCornerRadius > 0 ? confirmationCornerRadius : deviceCornerRadius
        return SheetLayout.controlInset(radius, diameter: confirmationControlHeight)
    }

    private var topBarMaterial: some View {
        TopBarMaterialBackground()
            .frame(height: 44)
            .offset(y: -44)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var selectedType: CampusFormChoice? { model.configuration?.choices.first { $0.id == model.draft.typeID } }
    private func binding<T>(_ path: WritableKeyPath<CampusFormDraft,T>) -> Binding<T> {
        Binding(get: { model.draft[keyPath: path] }, set: { value in model.update { $0[keyPath:path] = value } })
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        CampusSection(title, content: content)
    }
    private func safeText(_ value: String) -> some View { Text(CampusPrivacy.redact(value)).fixedSize(horizontal: false, vertical: true).privacySensitive() }
    private func choice(_ title: String, options: [CampusFormChoice], selection: Binding<String>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                safeText(title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                choicePicker(title, options: options, selection: selection).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                safeText(title).foregroundStyle(.secondary)
                choicePicker(title, options: options, selection: selection)
            }
        }.frame(minHeight: 44)
    }
    private func choicePicker(_ title: String, options: [CampusFormChoice], selection: Binding<String>) -> some View {
        Picker(selection: selection) {
            Text("请选择").tag("")
            ForEach(options) { value in safeText(value.name).tag(value.id) }
        } label: { safeText(title) }
        .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("campus-form-choice-" + title).disabled(options.isEmpty)
    }
    private func phone(_ title: String, key: WritableKeyPath<CampusFormDraft,String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            SecureField("请输入联系电话", text: binding(key)).keyboardType(.phonePad)
                .textContentType(nil).autocorrectionDisabled().privacySensitive().accessibilityLabel(title)
                .accessibilityIdentifier(identifier).frame(minHeight: 44)
                .focused($focusedPhone, equals: identifier)
            fieldError("电话")
        }.id(identifier)
    }
    private func editor(_ title: String, key: WritableKeyPath<CampusFormDraft,String>, identifier: String, short: Bool = false, showLabel: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showLabel { Text(title).font(.subheadline).foregroundStyle(.secondary) }
            CampusMaskedEditor(text: binding(key), label: title, identifier: identifier, onFocus: { focused in
                if focused { activeEditor = identifier }
                else if activeEditor == identifier { activeEditor = nil }
            })
                .frame(height: short ? shortEditorHeight : editorHeight)
                .overlay(alignment: .topLeading) {
                    if model.draft[keyPath: key].isEmpty {
                        Text(short ? "请填写" : "请填写具体事由")
                            .foregroundStyle(.tertiary).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
        }.id(identifier)
    }
    @ViewBuilder private func fieldError(_ contains: String) -> some View {
        if let error = model.error, error.contains(contains) { Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
    }
    private func endEditing() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"; return formatter.string(from: date)
    }
    private func locate() {
        isLocating = true
        Task {
            defer { isLocating = false }
            do { let point = try await location.coordinate(); await model.locate(latitude: point.latitude, longitude: point.longitude) }
            catch is CancellationError {} catch { model.report(error) }
        }
    }
    private func importPhoto(_ item: PhotosPickerItem) {
        isImporting = true; let typeID = model.draft.typeID
        Task {
            defer { isImporting = false; photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self), data.count <= 20*1024*1024 else {
                    throw CampusFormError.validation("无法读取图片，原图请勿超过 20 MiB")
                }
                let bytes = try await Task.detached {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true,
                            kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceThumbnailMaxPixelSize:2400] as CFDictionary),
                          let bytes = UIImage(cgImage:image).jpegData(compressionQuality:0.85) else {
                        throw CampusFormError.validation("无法读取证明图片，请重新选择")
                    }
                    return bytes
                }.value
                guard model.draft.typeID == typeID else { return }
                guard model.draft.attachments.reduce(0, { $0 + $1.data.count }) + bytes.count <= 50*1024*1024 else {
                    throw CampusFormError.validation("证明材料合计最多 50 MiB")
                }
                model.update { $0.attachments.append(.init(name:"证明.jpg",mime:"image/jpeg",data:bytes,isImage:true)) }
            } catch { model.report(error) }
        }
    }
    private func importFile(_ result: Result<URL,Error>) {
        guard case .success(let url) = result else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let attachment = try await Task.detached {
                    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let info = try url.resourceValues(forKeys: [.fileSizeKey,.isRegularFileKey])
                    guard info.isRegularFile == true, let count = info.fileSize, count > 0, count <= 20*1024*1024 else {
                        throw CampusFormError.validation("请选择不超过 20 MiB 的文件")
                    }
                    let data = try Data(contentsOf:url,options:.uncached)
                    return CampusAttachment(name:url.lastPathComponent, mime:UTType(filenameExtension:url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", data:data,isImage:false)
                }.value
                guard model.draft.attachments.reduce(0, { $0 + $1.data.count }) + attachment.data.count <= 50*1024*1024 else {
                    throw CampusFormError.validation("证明材料合计最多 50 MiB")
                }
                model.update { $0.attachments.append(attachment) }
            } catch { model.report(error) }
        }
    }
}

#if DEBUG
/// Synthetic form data only; preview confirmation never reaches a school endpoint.
private actor CampusFormPreviewAPI: CampusFormServing {
    let account: String; let generation: UInt64
    init(account: String, generation: UInt64) { self.account = account; self.generation = generation }
    func loadForm(_ kind: CampusFormKind) async throws -> CampusFormConfiguration {
        if ProcessInfo.processInfo.arguments.contains("--preview-form-loading") {
            try await Task.sleep(for: .seconds(30))
        }
        var c = CampusFormConfiguration(kind:kind,account:account,userId:"preview-user",generation:generation)
        c.choices = [.init(id:"preview-type",name:kind == .leave ? "病假" : "示例假期")]
        if kind == .leave && ProcessInfo.processInfo.arguments.contains("--preview-form-choices") {
            c.choices.append(.init(id: "preview-second-type", name: "事假"))
        }
        c.phone = "18000000000"; c.parentPhone = "18000000001"; c.displayName = "示例学生"
        c.needsLeaveTime = kind == .leave
        return c
    }
    func approvers(type: String, days: Double) async throws -> CampusApprovers { .init(roleID:"preview-role",roleName:"辅导员",users:[.init(id:"preview-reviewer",name:"示例审批人")]) }
    func roleUsers(_ role: CampusApprovers) async throws -> CampusApprovers { role }
    func locate(latitude: Double, longitude: Double) async throws -> String { "示例地址" }
    func submit(_ submission: CampusSubmission) async throws { try await Task.sleep(for:.milliseconds(300)) }
    func reconcile(_ submission: CampusSubmission) async throws -> Bool { false }
}
#endif
