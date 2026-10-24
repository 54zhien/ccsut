import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

@MainActor struct CampusFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var model: CampusFormModel
    @State private var location = CampusLocation()
    @State private var photo: PhotosPickerItem?
    @State private var importingFile = false
    @State private var isImporting = false
    @State private var isLocating = false
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
            VStack(spacing: 0) {
                SheetHeader(title: model.kind.title) { dismiss() }
                    .disabled(model.state == .submitting)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .padding(.horizontal, 16).padding(.vertical, 24)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .disabled(model.state == .submitting || model.state == .unknown)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { endEditing() } }
            }
        }
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.state == .submitting)
        .sheet(item: $model.confirmation) { confirmation($0) }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item]) { importFile($0) }
        .onChange(of: photo) { _, item in if let item { importPhoto(item) } }
        .task { await model.load() }
        .task(id: model.candidateKey) { await model.refreshApprovers() }
        .onDisappear { location.cancel(); model.stop() }
    }

    @ViewBuilder private var content: some View {
        if model.state == .loading {
            ProgressView("正在加载学校表单…").frame(maxWidth: .infinity).padding(.vertical, 60)
        } else if model.state == .submitted {
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
            Button("重新加载") { Task { await model.load() } }.buttonStyle(.glass)
        }
    }

    private func dates(_ c: CampusFormConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DatePicker("开始时间", selection: binding(\.begin), displayedComponents: [.date, .hourAndMinute])
            DatePicker("结束时间", selection: binding(\.end), displayedComponents: [.date, .hourAndMinute])
            fieldError("时间")
            if model.kind == .leave {
                LabeledContent("请假天数", value: model.draft.duration.formatted() + " 天")
                    .foregroundStyle(.secondary)
                if c.needsLeaveTime && model.draft.leaving == true {
                    DatePicker("离校时间", selection: Binding(get: { model.draft.actualLeaveTime ?? model.draft.begin }, set: { date in model.update { $0.actualLeaveTime = date } }), displayedComponents: [.date,.hourAndMinute])
                }
            }
        }
    }

    @ViewBuilder private func leaveFields(_ c: CampusFormConfiguration) -> some View {
        section("请假事由") { editor("请假事由", key: \.reason, identifier: "campus-form-reason"); fieldError("事由") }
        section("联系与审批") {
            phone("紧急联系人电话", key: \.contactPhone, identifier: "campus-form-contact")
            if !c.contacts.isEmpty { choice("常用联系人", options: c.contacts, selection: binding(\.contactPhone)) }
            if model.isLoadingApprovers { ProgressView("正在匹配审批人…").font(.footnote) }
            choice(model.approvers?.roleName ?? "审批人", options: model.approvers?.users ?? [], selection: binding(\.approverID))
            fieldError("审批")
            if !model.isLoadingApprovers && model.approvers == nil {
                Button("重新匹配审批人") { Task { await model.refreshApprovers() } }
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

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("campus-form-error")
                if error == CampusError.authentication.localizedDescription {
                    Button("重新认证") { Task { await session.refresh(); await model.load() } }
                }
            }
            if model.state == .unknown {
                Button { Task { await model.checkResult() } } label: {
                    HStack { if model.isChecking { ProgressView() }; Text("查询提交结果") }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.glassProminent).disabled(model.isChecking)
            } else if model.state == .submitted {
                Button("完成") { onSubmitted(); dismiss() }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.glassProminent)
            } else if model.configuration != nil {
                Button { endEditing(); model.prepareConfirmation() } label: {
                    Text("核对并提交").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.glassProminent).disabled(!model.canReview || isImporting || isLocating)
                    .accessibilityIdentifier("campus-form-review")
            }
        }
        .padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func confirmation(_ snapshot: CampusSubmission) -> some View {
        VStack(spacing: 0) {
            SheetHeader(title: "核对申请") { model.confirmation = nil }.disabled(model.state == .submitting)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    safeText(snapshot.configuration.displayName).font(.headline)
                    safeText(snapshot.configuration.choices.first { $0.id == snapshot.draft.typeID }?.name ?? "")
                        .font(.title3.weight(.semibold))
                    LabeledContent("是否离校", value: snapshot.draft.leaving == true ? "离校" : (snapshot.kind == .leave ? "不离校" : "留校"))
                    if snapshot.kind == .leave || snapshot.draft.leaving == true {
                        LabeledContent("开始", value: dateText(snapshot.draft.begin))
                        LabeledContent("结束", value: dateText(snapshot.draft.end))
                    }
                    if snapshot.kind == .leave {
                        LabeledContent("天数", value: snapshot.draft.duration.formatted())
                        if snapshot.draft.leaving == true, snapshot.configuration.needsLeaveTime, let time = snapshot.draft.actualLeaveTime {
                            LabeledContent("离校时间", value: dateText(time))
                        }
                        safeText("审批人：" + (snapshot.approvers?.users.first { $0.id == snapshot.draft.approverID }?.name ?? ""))
                        safeText("紧急联系人电话：" + snapshot.draft.contactPhone)
                    } else {
                        safeText("本人联系电话：" + snapshot.draft.phone)
                        safeText("家长联系电话：" + snapshot.draft.parentPhone)
                        if snapshot.draft.leaving == true { safeText("目的地：" + snapshot.draft.area.joined(separator: " / ")) }
                        if snapshot.draft.leaving == true {
                            safeText(snapshot.draft.detailAddress)
                            safeText("交通方式：" + snapshot.draft.travelMethod)
                            safeText("车次 / 航班：" + snapshot.draft.tripNumber)
                        }
                    }
                    if !snapshot.draft.reason.isEmpty { safeText(snapshot.draft.reason) }
                    if !snapshot.draft.destinationDetails.isEmpty { safeText("去向：" + snapshot.draft.destinationDetails) }
                    if snapshot.configuration.needsDestination {
                        safeText("去向类型：" + (snapshot.configuration.destinationTypes.first { $0.id == snapshot.draft.destinationTypeID }?.name ?? ""))
                    }
                    if let address = snapshot.draft.locationAddress { safeText("当前位置：" + address) }
                    if !snapshot.draft.attachments.isEmpty {
                        Text("证明材料：\(snapshot.draft.attachments.count) 项")
                        ForEach(snapshot.draft.attachments) { safeText($0.name).font(.footnote) }
                    }
                    Text("确认后将提交学校审核。").font(.footnote).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { Task { await model.submit(snapshot) } } label: {
                HStack { if model.state == .submitting { ProgressView() }; Text(model.state == .submitting ? "正在提交…" : "确认提交") }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.glassProminent).padding(16).disabled(model.state == .submitting)
                .accessibilityIdentifier("campus-form-confirm")
        }
        .presentationDetents([.large]).interactiveDismissDisabled(model.state == .submitting)
    }

    private var selectedType: CampusFormChoice? { model.configuration?.choices.first { $0.id == model.draft.typeID } }
    private func binding<T>(_ path: WritableKeyPath<CampusFormDraft,T>) -> Binding<T> {
        Binding(get: { model.draft[keyPath: path] }, set: { value in model.update { $0[keyPath:path] = value } })
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { Text(title).font(.headline); content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }
    private func safeText(_ value: String) -> some View { Text(CampusPrivacy.redact(value)).fixedSize(horizontal: false, vertical: true).privacySensitive() }
    private func choice(_ title: String, options: [CampusFormChoice], selection: Binding<String>) -> some View {
        Picker(selection: selection) {
            Text("请选择").tag("")
            ForEach(options) { value in safeText(value.name).tag(value.id) }
        } label: { safeText(title) }
        .pickerStyle(.menu).disabled(options.isEmpty).frame(minHeight: 44)
    }
    private func phone(_ title: String, key: WritableKeyPath<CampusFormDraft,String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            SecureField("请输入联系电话", text: binding(key)).keyboardType(.phonePad)
                .textContentType(nil).autocorrectionDisabled().privacySensitive().accessibilityLabel(title)
                .accessibilityIdentifier(identifier).frame(minHeight: 44)
            fieldError("电话")
        }
    }
    private func editor(_ title: String, key: WritableKeyPath<CampusFormDraft,String>, identifier: String, short: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            CampusMaskedEditor(text: binding(key), label: title, identifier: identifier)
                .frame(height: short ? shortEditorHeight : editorHeight)
        }
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
        var c = CampusFormConfiguration(kind:kind,account:account,userId:"preview-user",generation:generation)
        c.choices = [.init(id:"preview-type",name:kind == .leave ? "病假" : "示例假期")]
        c.phone = "18000000000"; c.parentPhone = "18000000001"; c.displayName = "示例学生"
        return c
    }
    func approvers(type: String, days: Double) async throws -> CampusApprovers { .init(roleID:"preview-role",roleName:"辅导员",users:[.init(id:"preview-reviewer",name:"示例审批人")]) }
    func roleUsers(_ role: CampusApprovers) async throws -> CampusApprovers { role }
    func locate(latitude: Double, longitude: Double) async throws -> String { "示例地址" }
    func submit(_ submission: CampusSubmission) async throws { try await Task.sleep(for:.milliseconds(300)) }
    func reconcile(_ submission: CampusSubmission) async throws -> Bool { false }
}
#endif
