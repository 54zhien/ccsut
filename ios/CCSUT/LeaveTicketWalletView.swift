import SwiftUI

struct LeaveWalletBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.17, green: 0.14, blue: 0.12), Color(red: 0.08, green: 0.075, blue: 0.07)]
                       : [Color(red: 0.94, green: 0.89, blue: 0.81), Color(red: 0.84, green: 0.80, blue: 0.73)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .top) {
                Ellipse().fill(.white.opacity(scheme == .dark ? 0.025 : 0.22))
                    .frame(height: 300).blur(radius: 65).offset(y: -120)
            }
            .ignoresSafeArea().accessibilityHidden(true)
    }
}

struct LeaveTicketWalletView: View {
    let model: CampusRecordsModel
    let account: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var form = false
    @State private var receipt: LeaveTicketReceipt?
    @State private var printing: CampusLeaveRecord?
    @State private var refreshRevision = 0
    @State private var submittingBaseline: Set<String> = []
    #if DEBUG
    @State private var previewPrints = 0
    #endif

    var body: some View {
        PageScrollSurface(refresh: { await refresh() }, backgroundColor: .clear) { _, proxy in
            VStack(spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("把每次安排，妥帖收好").font(.title3.weight(.medium))
                        Text(expanded ? "请假条已展开" : "轻触票夹，翻看请假条")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.top, 12)
                .id("leave-wallet-heading")

                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.65, bounce: 0.08)) {
                        expanded.toggle()
                    }
                } label: {
                    LeatherLeaveWallet(expanded: expanded, count: model.leave.items.count,
                                       hasMore: model.leave.hasMore)
                }
                .buttonStyle(.plain)
                .disabled(printing != nil)
                .accessibilityLabel(expanded ? "收起票夹" : "打开票夹")
                .accessibilityValue(model.leave.hasMore ? "已载入 \(model.leave.items.count) 张" : "\(model.leave.items.count) 张请假条")
                .accessibilityIdentifier("leave-wallet-toggle")
                .background(alignment: .top) {
                    if let printing {
                        LeaveTicketPrinter(record: printing) {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.04)) {
                                self.printing = nil
                                #if DEBUG
                                previewPrints += 1
                                #endif
                            }
                        }
                        .frame(height: 188).offset(y: -85)
                        .accessibilityLabel("正在收好新请假条")
                        .accessibilityIdentifier("leave-wallet-printing")
                    }
                }
                .padding(.top, 70)
                #if DEBUG
                if InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-wallet-print") {
                    Button("模拟已确认的申请") {
                        guard let record = model.leave.items.first else { return }
                        receipt = LeaveTicketReceipt(baseline: [], reason: record.reason ?? "",
                                                     begin: record.beginTime ?? "", end: record.endTime ?? "")
                        refreshRevision += 1
                    }.accessibilityIdentifier("wallet-fixture-submit")
                    Text("完成 \(previewPrints)").accessibilityIdentifier("wallet-fixture-completions")
                    Button("刷新记录") { refreshRevision += 1 }.accessibilityIdentifier("wallet-fixture-refresh")
                }
                #endif
                if receipt != nil {
                    Label("申请已提交，正在同步请假条；可下拉刷新", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("leave-wallet-syncing")
                }
                if let error = model.leaveError {
                    PageStatusNotice(message: error.localizedDescription) {
                        refreshRevision += 1
                    }
                }
                if model.isLoadingLeave && model.leave.items.isEmpty {
                    ProgressView("正在读取请假条…").padding()
                } else if model.leave.items.isEmpty && model.leaveError == nil {
                    Text("票夹还是空的\n添加第一张请假条，收好你的安排")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(6)
                        .accessibilityIdentifier("campus-leave-empty")
                }
                if expanded {
                    LazyVStack(spacing: 18) {
                        ForEach(Array(model.leave.items.filter { $0.id != printing?.id }.enumerated()), id: \.element.id) { index, record in
                            LeavePaperTicket(record: record)
                                .transition(.asymmetric(
                                    insertion: .offset(y: reduceMotion ? 0 : -35).combined(with: .opacity)
                                        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.04).delay(Double(min(index, 5)) * 0.045)),
                                    removal: .offset(y: reduceMotion ? 0 : -80).combined(with: .opacity)))
                        }
                        if model.leave.hasMore {
                            Button(model.isLoadingLeave ? "正在加载…" : "加载更多请假条") {
                                Task { await model.loadLeave(reset: false) }
                            }
                            .frame(minHeight: 44).disabled(model.isLoadingLeave)
                        }
                    }
                    .accessibilityIdentifier("leave-wallet-tickets")
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .onChange(of: printing?.id) { _, id in
                if id != nil { proxy.scrollTo("leave-wallet-heading", anchor: .top) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                receipt = nil
                submittingBaseline = Set(model.leave.items.map(\.id))
                form = true
            } label: {
                Label("添加请假条", systemImage: "plus")
                    .font(.headline).padding(.horizontal, 24).frame(minHeight: 52)
            }
            .buttonStyle(.glassProminent).tint(Color(red: 0.39, green: 0.23, blue: 0.14))
            .disabled(printing != nil)
            .accessibilityIdentifier("campus-record-add")
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $form, onDismiss: { refreshRevision += 1 }) {
            CampusFormView(kind: .leave, account: account, onLeaveSubmitted: { submitted in
                receipt = LeaveTicketReceipt(baseline: submitted.baseline.union(submittingBaseline),
                                             reason: submitted.reason, begin: submitted.begin, end: submitted.end)
            })
        }
        .task(id: refreshRevision) { await refresh() }
        .onDisappear { printing = nil; receipt = nil }
        .onChange(of: reduceMotion) { _, reduced in if reduced { printing = nil } }
    }

    private func refresh() async {
        await model.loadLeave(reset: true)
        guard !Task.isCancelled, model.leaveError == nil, !form, var pending = receipt else { return }
        let candidates = model.leave.items.map {
            LeaveTicketCandidate(id: $0.id, reason: $0.reason ?? "", begin: $0.beginTime ?? "", end: $0.endTime ?? "")
        }
        if let id = pending.consume(candidates) {
            receipt = nil
            if !reduceMotion {
                printing = model.leave.items.first { $0.id == id }
            } else {
                #if DEBUG
                previewPrints += 1
                #endif
            }
        }
    }
}

private struct LeatherLeaveWallet: View {
    let expanded: Bool
    let count: Int
    let hasMore: Bool
    private let leather = Color(red: 0.39, green: 0.22, blue: 0.13)
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22).fill(leather.gradient)
                .padding(.top, 22)
            ForEach(0..<min(count, 3), id: \.self) { index in
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(red: 0.97 - Double(index) * 0.035, green: 0.94 - Double(index) * 0.035, blue: 0.87 - Double(index) * 0.035))
                    .frame(height: 112).padding(.horizontal, CGFloat(24 + index * 6))
                    .rotationEffect(.degrees(Double(index - 1) * 2))
                    .offset(y: CGFloat(17 - index * 6))
            }
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.34, blue: 0.22), leather], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { LeatherGrain().opacity(0.15).clipShape(RoundedRectangle(cornerRadius: 22)) }
                .overlay {
                    RoundedRectangle(cornerRadius: 17).inset(by: 9)
                        .strokeBorder(Color(red: 0.85, green: 0.65, blue: 0.43).opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("请假条").font(.title2.weight(.semibold))
                        Text(count == 0 ? "等待第一张收藏" : (hasMore ? "已收纳 \(count) 张 · 还有更多" : "已收纳 \(count) 张"))
                            .font(.caption)
                    }
                    .foregroundStyle(Color(red: 0.98, green: 0.88, blue: 0.72))
                    .padding(26)
                }
                .padding(.top, 65)
            RoundedRectangle(cornerRadius: 19)
                .fill(LinearGradient(colors: [Color(red: 0.58, green: 0.37, blue: 0.25), leather], startPoint: .top, endPoint: .bottom))
                .overlay { LeatherGrain().opacity(0.12).clipShape(RoundedRectangle(cornerRadius: 19)) }
                .overlay {
                    RoundedRectangle(cornerRadius: 14).inset(by: 8)
                        .strokeBorder(.white.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .overlay(alignment: .bottom) {
                    Circle().fill(Color(red: 0.76, green: 0.61, blue: 0.39).gradient)
                        .frame(width: 17, height: 17).shadow(color: .black.opacity(0.3), radius: 2, y: 2).padding(.bottom, 13)
                }
                .frame(height: 102)
                .shadow(color: .black.opacity(0.22), radius: 6, y: 5)
                .rotation3DEffect(.degrees(expanded ? -155 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.3)
                .offset(y: 23)
        }
        .frame(height: 230)
        .padding(.top, expanded ? 72 : 16)
        .shadow(color: .black.opacity(0.19), radius: 18, x: 0, y: 14)
        .accessibilityHidden(true)
    }
}

private struct LeatherGrain: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<900 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 137) % 991) / 991 * size.height
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 0.65)), with: .color(.black))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct LeavePaperTicket: View {
    let record: CampusLeaveRecord
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(); status }
                VStack(alignment: .leading, spacing: 10) { title; status }
            }
            Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
            VStack(alignment: .leading, spacing: 9) {
                Text("开始  \(record.beginTime ?? "未提供")")
                Text("结束  \(record.endTime ?? "未提供")")
            }.font(.subheadline.monospacedDigit())
            if let days = record.days {
                Label("\(NSDecimalNumber(decimal: days).stringValue) 天", systemImage: "clock").font(.subheadline)
            }
            if let reason = record.reason, !reason.isEmpty {
                Text(reason).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            if let time = record.applyTime {
                Text("申请于 \(time)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(scheme == .dark ? Color(red: 0.94, green: 0.89, blue: 0.80) : Color(red: 0.24, green: 0.19, blue: 0.15))
        .background(scheme == .dark ? Color(red: 0.23, green: 0.21, blue: 0.18) : Color(red: 0.99, green: 0.97, blue: 0.91), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .privacySensitive().accessibilityElement(children: .combine)
        .accessibilityIdentifier("leave-ticket-\(record.id)")
    }
    private var title: some View { Text(record.typeName ?? "请假条").font(.title3.weight(.semibold)) }
    private var status: some View {
        Text(record.statusText).font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.primary.opacity(0.07), in: Capsule())
    }
}
