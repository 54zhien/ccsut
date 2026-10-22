//
//  CCSUTApp.swift
//  CCSUT
//
//  入口 · TabView 使用 iOS 18 的 Tab 值绑定语法
//

import SwiftUI
import WebKit

@main
struct CCSUTApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.bootstrap() }
        }
    }
}

// MARK: - 根视图

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .checking:
                LaunchView()
            case .loggedOut:
                LoginView()
            case .loggedIn, .refreshing:
                MainTabs()
            }
        }
        .animation(.smooth(duration: 0.35), value: session.phase)
    }
}

// MARK: - 启动页

struct LaunchView: View {
    @State private var spin = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.20, blue: 0.62),
                    Color(red: 0.22, green: 0.47, blue: 0.95),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(spin ? 1.06 : 0.94)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: spin)

                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)

                Text("正在恢复会话…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .onAppear { spin = true }
    }
}

// MARK: - 主 Tab

struct MainTabs: View {
    @Environment(SessionStore.self) private var session

    enum AppTab: Hashable {
        case schedule, elective, me
    }

    @State private var selection: AppTab = .schedule

    var body: some View {
        TabView(selection: $selection) {
            Tab("课表", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }

            Tab("选课", systemImage: "list.bullet.rectangle.portrait", value: AppTab.elective) {
                ElectiveView()
            }

            Tab("我的", systemImage: "person.crop.circle", value: AppTab.me) {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)   // iOS 26
    }
}

// MARK: - 我的

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    @State private var showScore = false
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(.tint.opacity(0.15))
                                .frame(width: 54, height: 54)
                            Text(initials)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tint)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.studentName ?? "已登录")
                                .font(.headline)
                            Text(session.studentId ?? "—")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("会话") {
                    LabeledContent("状态") {
                        Text(statusText)
                            .foregroundStyle(session.phase == .loggedIn ? .green : .secondary)
                    }
                    LabeledContent("凭证") {
                        Text(session.cookieSummary)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    if let days = session.tgcRemainingDays {
                        LabeledContent("TGC 剩余") {
                            Text("\(days, format: .number.precision(.fractionLength(1))) 天")
                                .monospacedDigit()
                        }
                    }

                    Button("立即续期") {
                        Task { await session.refresh() }
                    }
                    .disabled(session.phase == .refreshing)
                }

                Section("教务") {
                    Button {
                        showScore = true
                    } label: {
                        Label("成绩查询", systemImage: "chart.bar.doc.horizontal")
                    }
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        showLogoutAlert = true
                    }
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showScore) {
                ScoreWebView()
            }
            .alert("退出登录", isPresented: $showLogoutAlert) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) {
                    Task { await session.logout() }
                }
            } message: {
                Text("会清除本地保存的凭证，下次需要重新输入账号密码。")
            }
        }
    }

    private var initials: String {
        guard let name = session.studentName, let first = name.first else { return "?" }
        return String(first)
    }

    private var statusText: String {
        switch session.phase {
        case .checking: return "检查中"
        case .loggedOut: return "未登录"
        case .loggedIn: return "正常"
        case .refreshing: return "续期中"
        }
    }
}

// MARK: - 成绩（JSP 报表，学校端缺文件）

extension ScoreWebView {
    /// 学校那台服务器的 /WEB-INF/reportFiles/csgyxy/xsd/cjgl/dgxsyxcj.rpx 不存在，
    /// 报表引擎会吐一张纯文本错误页。检测到就直接盖一层说明，别让用户对着报错发呆。
    func checkIfBroken() async {
        let js = "document.body ? document.body.innerText : ''"
        guard let raw = try? await webView.evaluateJavaScript(js),
              let text = raw as? String
        else { return }

        if text.contains("读报表文件失败")
            || (text.contains("报表文件") && text.contains("不存在")) {
            serverBroken = true
        }
    }
}

// MARK: - 成绩（JSP 报表，只能走 WebView）

private struct BrokenScorePanel: View {
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)

                Text("学校服务器缺少成绩报表")
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 10) {
                    Label("错误信息", systemImage: "exclamationmark.triangle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("读报表文件失败：csgyxy/xsd/cjgl/dgxsyxcj.rpx\n报表文件 /WEB-INF/reportFiles/... 不存在")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Text("教务系统的成绩查询依赖 JSP 报表引擎，学校没把 .rpx 模板文件部署上去，所以任何客户端打开都是这个结果——包括电脑浏览器。")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("这不是 App 的问题，只能等学校运维修复。")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                VStack(spacing: 8) {
                    Text("临时替代")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("学习通里的成绩查询走的是超星自己的通道，不受这个报表影响，可以先在那里看。")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)

                Button {
                    onClose()
                } label: {
                    Text("知道了")
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .padding(24)
        }
    }
}

struct ScoreWebView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var webView: WKWebView
    @State private var nav = WebNavigator()
    @State private var serverBroken = false

    init() {
        _webView = State(initialValue: WebFactory.make())
    }

    var body: some View {
        NavigationStack {
            WebPanel(webView: webView)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("成绩查询")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            webView.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .overlay {
                    if webView.isLoading {
                        ProgressView().controlSize(.large)
                    }
                }
                .overlay {
                    if serverBroken {
                        BrokenScorePanel { serverBroken = false }
                            .background(.background)
                    }
                }
                .onAppear {
                    webView.navigationDelegate = nav
                    webView.load(URLRequest(
                        url: URL(string: "https://tls.ccsut.cn/admin/xsd/xsdzgcjcx/xscjdy")!
                    ))
                }
                .onChange(of: nav.currentURL) { _, url in
                    guard url != nil else { return }
                    Task { await checkIfBroken() }
                }
        }
    }
}
