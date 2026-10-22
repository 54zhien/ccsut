//
//  LoginView.swift
//  CCSUT
//
//  登录页 · 原生 UI + 后台 WKWebView 代理
//
//  架构（踩过坑之后的最终版）：
//    · WebView 永远只有一个实例，铺满全屏
//    · 非手动模式时被 nativeLayer 完全遮住（不是靠 alpha=0 / 1×1，那会让 WebKit 停加载）
//    · 登录靠 callAsyncJavaScript 注入填表，参数自动转义
//    · 八秒没反应就自动切手动模式，不至于卡死
//

import SwiftUI
import WebKit
import Observation

// MARK: - 阶段

enum LoginStage: Equatable {
    case idle
    case loading
    case injecting
    case submitting
    case done
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .loading, .injecting, .submitting: return true
        default: return false
        }
    }

    var caption: String {
        switch self {
        case .idle: return "登录"
        case .loading: return "加载认证页…"
        case .injecting: return "填写表单…"
        case .submitting: return "登录中…"
        case .done: return "进入中…"
        case .failed: return "重试"
        }
    }
}

// MARK: - 登录页

struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var webView: WKWebView
    @State private var nav = WebNavigator()

    @State private var username = ""
    @State private var password = ""
    @State private var stage: LoginStage = .idle
    @State private var manualMode = false
    @State private var didInject = false
    @State private var logLines: [String] = []
    @State private var watchdog: Task<Void, Never>?

    @FocusState private var focused: Field?
    private enum Field { case user, pass }

    init() {
        _webView = State(initialValue: WebFactory.make())
    }

    var body: some View {
        ZStack {
            // 唯一的 WebView：全屏、始终存在
            // 手动模式显示，自动模式被下面的 nativeLayer 盖住
            WebPanel(webView: webView)
                .ignoresSafeArea()
                .opacity(manualMode ? 1 : 1)   // 保持 1，靠遮挡而不是透明度
                .allowsHitTesting(manualMode)

            if manualMode {
                manualOverlay
            } else {
                nativeLayer
            }
        }
        .animation(.smooth(duration: 0.25), value: manualMode)
        .onAppear(perform: setup)
        .onDisappear { watchdog?.cancel() }
        .onChange(of: nav.currentURL) { _, url in
            guard let url else { return }
            handleNavigation(to: url)
        }
        .onChange(of: nav.lastError) { _, err in
            guard let err else { return }
            logLines.append("⚠️ \(err)")
            if stage.isBusy { stage = .failed(err) }
        }
    }

    // MARK: 初始化

    private func setup() {
        webView.navigationDelegate = nav
        nav.onNavigate = { url in handleNavigation(to: url) }
        nav.onFailure = { msg in
            logLines.append("⚠️ \(msg)")
            if stage.isBusy { stage = .failed(msg) }
        }

        if username.isEmpty,
           let saved = UserDefaults.standard.string(forKey: "ccsut.lastUsername") {
            username = saved
        }
    }

    // MARK: 手动模式覆盖层

    private var manualOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    manualMode = false
                    stage = .idle
                } label: {
                    Label("返回", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                Text("网页登录")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Spacer()
        }
    }

    // MARK: 原生登录层

    private var nativeLayer: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 36)
                brand
                formCard
                if case .failed(let msg) = stage { errorBanner(msg) }
                fallbackRow
                debugStrip
                footer
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 36)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(backdrop)
    }

    private var brand: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 92, height: 92)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("长工教务")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text("长沙工业学院 · 统一身份认证")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private var formCard: some View {
        VStack(spacing: 16) {
            inputRow(symbol: "person.text.rectangle", placeholder: "学号", text: $username, secure: false)
                .textContentType(.username)
                .keyboardType(.asciiCapable)
                .focused($focused, equals: .user)
                .submitLabel(.next)
                .onSubmit { focused = .pass }

            Divider().overlay(.white.opacity(0.18))

            inputRow(symbol: "lock.rotation", placeholder: "密码", text: $password, secure: true)
                .textContentType(.password)
                .focused($focused, equals: .pass)
                .submitLabel(.go)
                .onSubmit(submit)

            Button(action: submit) {
                HStack(spacing: 10) {
                    if stage.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(red: 0.10, green: 0.31, blue: 0.82))
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    Text(stage.caption).font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canSubmit ? Color.white : Color.white.opacity(0.45))
                .foregroundStyle(Color(red: 0.10, green: 0.31, blue: 0.82))
                .clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || stage.isBusy || stage == .done)
            .padding(.top, 4)
        }
        .padding(20)
        .glassCard(radius: 26)
    }

    private func inputRow(symbol: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body)
            .foregroundStyle(.white)
        }
        .padding(.vertical, 6)
    }

    private var fallbackRow: some View {
        Button {
            manualMode = true
            didInject = true
            stage = .loading
            logLines.append("切手动模式")
            webView.load(URLRequest(url: SessionStore.casLoginURL))
        } label: {
            Label("用网页登录（验证码 / 改密码走这里）", systemImage: "safari")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .buttonStyle(.plain)
    }

    /// 实时显示 WebView 状态，出问题一眼看出卡在哪
    private var debugStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(debugLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }

            ForEach(logLines.suffix(6), id: \.self) { line in
                Text(line)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private var debugLine: String {
        let host = webView.url?.host ?? "未加载"
        let path = webView.url?.path ?? ""
        let state = webView.isLoading ? "loading" : "idle"
        return "\(state) · \(host)\(path.isEmpty ? "" : path) · \(phaseLabel)"
    }

    private var statusColor: Color {
        if nav.lastError != nil { return .red }
        if webView.isLoading { return .yellow }
        if webView.url != nil { return .green }
        return .gray
    }

    private var footer: some View {
        Text("登录后状态保持 14 天，到期自动续期")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.7))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.footnote)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.red.opacity(0.35), in: .rect(cornerRadius: 12))
    }

    private var backdrop: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.55, 0.45], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: [
                Color(red: 0.06, green: 0.20, blue: 0.62),
                Color(red: 0.12, green: 0.34, blue: 0.86),
                Color(red: 0.22, green: 0.47, blue: 0.95),
                Color(red: 0.10, green: 0.30, blue: 0.80),
                Color(red: 0.28, green: 0.55, blue: 0.98),
                Color(red: 0.18, green: 0.42, blue: 0.92),
                Color(red: 0.14, green: 0.30, blue: 0.74),
                Color(red: 0.30, green: 0.52, blue: 0.96),
                Color(red: 0.42, green: 0.68, blue: 1.00),
            ]
        )
        .ignoresSafeArea()
    }

    // MARK: 逻辑

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        focused = nil
        guard canSubmit, !stage.isBusy else { return }

        UserDefaults.standard.set(username, forKey: "ccsut.lastUsername")
        didInject = false
        logLines = ["开始加载统一认证"]
        stage = .loading

        webView.load(URLRequest(url: SessionStore.casLoginURL))
        startWatchdog()
    }

    /// 8 秒还没加载出页面，说明 WebKit 没动，直接切手动模式给用户
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if stage == .loading, webView.url == nil {
                    logLines.append("⚠️ 8 秒未加载，转手动模式")
                    manualMode = true
                    stage = .idle
                }
            }
        }
    }

    private func handleNavigation(to url: URL) {
        let absolute = url.absoluteString
        logLines.append("→ \(url.host ?? "")\(url.path)")

        // 落到教务系统 → 尝试接管会话（URL 只是线索，真正判定看 Cookie + 探测）
        if absolute.contains("tls.ccsut.cn"),
           !absolute.contains("/admin/login"),
           !absolute.contains("loginFailPage") {
            watchdog?.cancel()
            Task { await finishLogin() }
            return
        }

        // CAS 登录页 → 注入
        if absolute.contains("auth.ccsut.cn"),
           absolute.contains("/cas/login"),
           !didInject {
            didInject = true
            Task { await inject() }
            scheduleInjectFallback()
        }
    }

    /// CAS 有 TGC 时通常自动跳转，不需要注入；
    /// 但如果 4 秒还停在登录页，说明需要手动填表
    private func scheduleInjectFallback() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard stage == .loading else { return }
            let url = webView.url?.absoluteString ?? ""
            guard url.contains("/cas/login") else { return }
            logLines.append("4 秒未跳转，主动注入")
            await inject()
        }
    }

    // MARK: 接管会话

    /// URL 到了教务系统不代表登录成功，必须真的拿到 Cookie 且能访问 /admin/
    @MainActor
    private func finishLogin() async {
        guard stage != .submitting, stage != .done else { return }
        stage = .submitting
        logLines.append("接管会话…")

        let ok = await session.adoptCookies()
        logLines.append("Cookie \(session.lastCookieCount) 条 · phase=\(phaseLabel)")

        if ok {
            stage = .done
            logLines.append("✓ 会话有效")
        } else {
            let msg = session.lastError ?? "会话建立失败"
            stage = .failed(msg)
            logLines.append("✗ \(msg)")
            logLines.append("现有 Cookie：\(session.cookieNames)")
        }
    }

    private var phaseLabel: String {
        switch session.phase {
        case .checking: return "checking"
        case .loggedOut: return "loggedOut"
        case .loggedIn: return "loggedIn"
        case .refreshing: return "refreshing"
        }
    }

    // MARK: 注入

    @MainActor
    private func inject() async {
        stage = .injecting
        logLines.append("注入填表脚本")

        do {
            let result = try await webView.callAsync(Self.loginScriptBody, arguments: [
                "username": username,
                "password": password,
            ])

            let outcome = (result as? String) ?? "(nil)"
            logLines.append("注入结果：\(outcome)")

            guard outcome == "ok" else {
                stage = .failed(outcome == "no-form"
                    ? "没找到登录表单，点下面「用网页登录」"
                    : "页面结构异常（\(outcome)）")
                return
            }

            stage = .submitting
            logLines.append("已提交，等跳转…")

            try? await Task.sleep(for: .seconds(15))
            if stage == .submitting {
                stage = .failed("没跳转，可能密码错或需要验证码。用「网页登录」")
            }
        } catch {
            stage = .failed("注入失败：\(error.localizedDescription)")
        }
    }

    /// callAsyncJavaScript 传的是函数体，参数以变量名注入
    private static let loginScriptBody = """
        const setVal = (el, v) => {
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(el, v);
          ['input', 'change', 'keyup', 'blur'].forEach(t =>
            el.dispatchEvent(new Event(t, { bubbles: true })));
        };

        const sleep = ms => new Promise(r => setTimeout(r, ms));

        const tabs = [...document.querySelectorAll('.ant-tabs-tab')];
        const pwdTab = tabs.find(t => (t.textContent || '').includes('密码登录'));
        if (pwdTab && !pwdTab.classList.contains('ant-tabs-tab-active')) {
          pwdTab.click();
          await sleep(600);
        }

        let pwd = null;
        for (let i = 0; i < 25 && !pwd; i++) {
          pwd = [...document.querySelectorAll('input')].find(el => el.type === 'password');
          if (!pwd) await sleep(200);
        }
        if (!pwd) return 'no-form';

        const texts = [...document.querySelectorAll('input')].filter(el => el.type === 'text');
        const user = texts.find(el => /用户名|手机号|账号/.test(el.placeholder || '')) || texts[0];
        if (user) setVal(user, username);
        setVal(pwd, password);

        [...document.querySelectorAll('.ant-checkbox-wrapper')].forEach(label => {
          if (/记住/.test(label.textContent || '')) {
            const cb = label.querySelector('input[type=checkbox]');
            if (cb && !cb.checked) label.click();
          }
        });

        await sleep(400);
        const btn = [...document.querySelectorAll('button')]
          .find(b => (b.textContent || '').trim() === '登录');
        if (!btn) return 'no-button';
        btn.click();

        return 'ok';
        """
}

// MARK: - Liquid Glass 卡片

extension View {
    func glassCard(radius: CGFloat = 22) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}
