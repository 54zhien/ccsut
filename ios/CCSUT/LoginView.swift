//
//  LoginView.swift
//  CCSUT
//
//  登录页 · 短信验证码，全程留在 App 内
//
//  结构：
//    登录页底层使用全屏 WKWebView（不可交互），上层用原生界面盖住；
//    打开网页登录时，先从登录页树中卸载，再把同一个实例挂到 large sheet。
//    WebView 始终保持正常尺寸和透明度，让 CAS 的 Angular 正常运行。
//
//    为什么不能把 WebView 缩成 1×1 或 opacity(0.01)：
//    WebKit 会判定它不可见并停止导航，表现为永远卡在「加载认证页」。
//
//  流程：
//    输账号 → 点「获取验证码」（后台切页签、填账号、点发送）
//    → 收短信 → 输验证码 → 点「登录」（后台填码并提交）
//    → 落到教务系统 → 接管 Cookie → 进主界面
//

import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var webView: WKWebView
    @State private var nav = WebNavigator()

    @State private var account = ""
    @State private var code = ""
    @State private var busy: Busy = .idle
    @State private var hint = ""
    @State private var isPreparingWebSheet = false
    @State private var webViewIsInSheet = false
    @State private var showWebSheet = false
    @State private var prepared = false         // 页签是否已经切过

    @State private var cooldown = 0             // 重发倒计时
    @State private var timer: Task<Void, Never>?
    @State private var loginTimeout: Task<Void, Never>?
    @State private var operationID = UUID()
    @State private var isFinishing = false
    @State private var pendingFinish = false
    @State private var hasStarted = false

    @FocusState private var focused: Field?
    private enum Field { case account, code }
    private let fieldInset: CGFloat = 20

    private enum Busy: Equatable {
        case idle
        case sending
        case logging
        case done
    }

    init() {
        _webView = State(initialValue: WebFactory.make())
    }

    var body: some View {
        ZStack {
            if !webViewIsInSheet && !isPreparingWebSheet {
                // 必须全屏渲染，不能缩小或隐藏；原生界面只负责盖住它。
                // 弹 sheet 前先从这棵树移除，避免同一 WKWebView 同时出现在两棵树里。
                WebPanel(webView: webView)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .onDisappear {
                        guard isPreparingWebSheet else { return }
                        webViewIsInSheet = true
                        isPreparingWebSheet = false
                        showWebSheet = true
                    }
            }

            nativeLayer
        }
        .sheet(isPresented: $showWebSheet, onDismiss: restoreWebViewToLogin) {
            WebLoginSheet(webView: webView, navigator: nav)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: start)
        .onDisappear {
            let sheetTemporarilyCoversLogin = session.phase == .loggedOut &&
                (isPreparingWebSheet || webViewIsInSheet || showWebSheet)
            guard !sheetTemporarilyCoversLogin else { return }
            timer?.cancel()
            loginTimeout?.cancel()
            pendingFinish = false
            operationID = UUID()
        }
        .onChange(of: nav.currentURL) { _, url in
            guard let url else { return }
            handle(url)
        }
        .onChange(of: nav.lastError) { _, err in
            if let err, busy != .done, !webViewIsInSheet, !showWebSheet {
                session.cancelLogin()
                loginTimeout?.cancel()
                pendingFinish = false
                operationID = UUID()
                hint = err
                busy = .idle
            }
        }
    }

    // MARK: 原生层

    private var nativeLayer: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 30) {
                        brand
                            .padding(.bottom, 18)
                        credentialsForm
                        actions
                        if !hint.isEmpty {
                            Text(AppMessages.readable(hint))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private var brand: some View {
        VStack(spacing: 18) {
            SchoolEmblemView(size: 92, monochrome: true)
            SchoolWordmarkView()
                .frame(maxWidth: 270)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var credentialsForm: some View {
        VStack(spacing: 0) {
            TextField("手机号 / 学号", text: $account)
                .keyboardType(.default)
                .textContentType(.telephoneNumber)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .foregroundStyle(.primary)
                .focused($focused, equals: .account)
                .submitLabel(.next)
                .onSubmit { focused = .code }
                .padding(.horizontal, fieldInset)
                .frame(height: 56)

            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
                .padding(.horizontal, fieldInset)

            HStack(spacing: 12) {
                TextField("短信验证码", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .focused($focused, equals: .code)
                    .submitLabel(.done)
                    .onSubmit { submit() }

                Button(action: sendCode) {
                    Group {
                        if busy == .sending {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(cooldown > 0 ? "\(cooldown)s" : "获取验证码")
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                        }
                    }
                    .frame(minWidth: 84, minHeight: 44, alignment: .trailing)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, fieldInset)
            .frame(height: 56)
        }
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.5)
        }
        .clipShape(.rect(cornerRadius: 28))
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: submit) {
                HStack(spacing: 10) {
                    if busy == .logging {
                        ProgressView().controlSize(.small).tint(Color("AccentForeground"))
                    }
                    Text("登录").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canLogin || busy == .logging ? Color.accentColor : Color(.tertiarySystemFill),
                            in: .capsule)
                .foregroundStyle(canLogin || busy == .logging ? Color("AccentForeground") : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canLogin)

            Button(action: showWebLogin) {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                        .font(.subheadline.weight(.medium))
                    Text("网页登录")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(Color.accentColor)
                .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 状态

    private var trimmed: String { account.trimmingCharacters(in: .whitespaces) }
    private var canSend: Bool { !trimmed.isEmpty && busy == .idle && cooldown == 0 }
    private var canLogin: Bool { !trimmed.isEmpty && code.count >= 4 && busy == .idle }

    // MARK: 流程

    private func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard !InterfacePreview.enabled else { return }
        hint = session.lastError ?? ""
        webView.navigationDelegate = nav
        nav.onNavigate = { url in handle(url) }
        if account.isEmpty,
           let saved = UserDefaults.standard.string(forKey: "ccsut.lastAccount") {
            account = saved
        }
        nav.loadLoginPage(in: webView)
    }

    private func handle(_ url: URL) {
        let absolute = url.absoluteString

        // 到教务系统 → 接管
        if url.host == "tls.ccsut.cn",
           !absolute.contains("/admin/login"),
           !absolute.contains("loginFailPage") {
            Task { await finish() }
            return
        }

        // CAS 页首次到达 → 预先切到「验证码登录」页签
        if url.host == "auth.ccsut.cn",
           absolute.contains("/cas/login"),
           !isPreparingWebSheet, !webViewIsInSheet, !showWebSheet,
           !prepared {
            prepared = true
            Task { await prepare() }
        }
    }

    /// 切页签 + 填账号，不动验证码
    private func prepare() async {
        _ = try? await webView.callAsync(Self.script, arguments: [
            "account": trimmed,
            "code": "",
            "action": "prepare",
        ])
    }

    private func sendCode() {
        guard canSend else { return }
        guard !InterfacePreview.enabled else { return }
        UserDefaults.standard.set(trimmed, forKey: "ccsut.lastAccount")

        busy = .sending
        hint = ""
        let id = beginTimeout()

        Task {
            let outcome: String
            do {
                let r = try await webView.callAsync(Self.script, arguments: [
                    "account": trimmed, "code": "", "action": "send",
                ])
                outcome = (r as? String) ?? "?"
            } catch {
                guard operationID == id, busy != .done, !isFinishing else { return }
                loginTimeout?.cancel()
                busy = .idle
                hint = "认证页连接失败，请重试或使用网页登录"
                return
            }
            guard operationID == id, busy != .done, !isFinishing else { return }
            loginTimeout?.cancel()

            await MainActor.run {
                busy = .idle
                switch outcome {
                case "sent":
                    hint = ""
                    startCooldown(60)
                    focused = .code
                case "no-tab", "no-form":
                    hint = "认证页还没准备好，点“网页登录”继续"
                case "no-account":
                    hint = "账号框没填上，先检查账号"
                case "timeout":
                    hint = "未确认验证码发送成功，请稍后重试或使用网页登录"
                default:
                    hint = outcome.hasPrefix("error:") ? String(outcome.dropFirst(6))
                        : "发送失败（\(outcome)），试试网页登录"
                }
            }
        }
    }

    private func submit() {
        guard canLogin else { return }
        guard !InterfacePreview.enabled else { return }
        focused = nil
        UserDefaults.standard.set(trimmed, forKey: "ccsut.lastAccount")

        busy = .logging
        hint = ""
        let id = beginTimeout()

        Task {
            do {
                let r = try await webView.callAsync(Self.script, arguments: [
                    "account": trimmed,
                    "code": code.trimmingCharacters(in: .whitespaces),
                    "action": "submit",
                ])
                guard operationID == id, busy != .done, !isFinishing else { return }
                let outcome = (r as? String) ?? "?"
                loginTimeout?.cancel()
                busy = .idle
                if outcome.hasPrefix("error:") {
                    hint = String(outcome.dropFirst(6))
                } else if outcome == "timeout" {
                    hint = "登录未完成，请检查验证码后重试，或使用网页登录"
                } else {
                    hint = outcome == "no-code" ? "页面还没准备好，稍等再点一次" : "提交失败（\(outcome)）"
                }
            } catch {
                // 页面跳转也会终止 JS；给导航回调接管 Cookie 的时间，
                // 若没有完成跳转，beginTimeout 保证按钮最终恢复。
                guard operationID == id, busy != .done else { return }
                hint = "正在确认登录结果…"
            }
        }
    }

    private func finish() async {
        guard busy != .done else { return }
        if isFinishing { pendingFinish = true; return }
        isFinishing = true
        defer {
            isFinishing = false
            if pendingFinish, busy != .done, session.phase == .loggedOut {
                pendingFinish = false
                Task { await finish() }
            }
        }
        let id = operationID
        // 会话层已等待 Cookie 落地并验证一次，网络失败不在这里重复整条链。
        let adopted = await session.adoptCookies()
        guard operationID == id, !Task.isCancelled else { return }
        if adopted {
            loginTimeout?.cancel()
            busy = .done
            return
        }
        loginTimeout?.cancel()
        busy = .idle
        hint = session.lastError ?? "登录没有完成，请再试一次"
    }

    /// JS 卡住、页面未跳转、或回调丢失时也必须让用户能再次操作。
    private func beginTimeout() -> UUID {
        loginTimeout?.cancel()
        let id = UUID()
        operationID = id
        loginTimeout = Task {
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard operationID == id, busy != .done else { return }
            session.cancelLogin()
            pendingFinish = false
            operationID = UUID()
            busy = .idle
            hint = "认证请求超时，请重试或使用网页登录"
        }
        return id
    }

    private func startCooldown(_ seconds: Int) {
        timer?.cancel()
        cooldown = seconds
        timer = Task {
            while cooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                await MainActor.run { cooldown -= 1 }
            }
        }
    }

    private func showWebLogin() {
        guard !isPreparingWebSheet, !webViewIsInSheet, !showWebSheet else { return }
        focused = nil
        // Manual web authentication has its own lifetime. A native SMS request
        // must not time out and cancel Cookie adoption while this sheet is open.
        loginTimeout?.cancel()
        operationID = UUID()
        pendingFinish = false
        busy = .idle
        hint = ""
        isPreparingWebSheet = true
    }

    private func restoreWebViewToLogin() {
        webViewIsInSheet = false
    }

    // MARK: 注入脚本

    /// action = prepare | send | submit
    private static let script = """
        const setVal = (el, v) => {
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(el, v);
          ['input', 'change', 'keyup', 'blur'].forEach(t =>
            el.dispatchEvent(new Event(t, { bubbles: true })));
        };
        const sleep = ms => new Promise(r => setTimeout(r, ms));
        const messages = () => [...document.querySelectorAll(
          '.ant-message-notice-content, .ant-alert-message, .ant-form-explain, .ant-form-item-explain-error, [role="alert"], .ant-notification-notice-message'
        )].filter(el => el.offsetWidth > 0 && (el.textContent || '').trim());
        const snapshot = () => new Map(messages().map(el => [el, (el.textContent || '').trim()]));
        const freshMessages = previous => messages()
          .filter(el => previous.get(el) !== (el.textContent || '').trim())
          .map(el => (el.textContent || '').trim());

        // 1. 等页签
        let tabs = [];
        for (let i = 0; i < 50; i++) {
          tabs = [...document.querySelectorAll('.ant-tabs-tab')];
          if (tabs.length) break;
          await sleep(200);
        }
        if (!tabs.length) return 'no-tab';

        // 2. 切到「验证码登录」
        const target = tabs.find(t => (t.textContent || '').includes('验证码登录'));
        if (!target) return 'no-tab';
        if (!target.classList.contains('ant-tabs-tab-active')) {
          target.click();
          await sleep(1000);
        }

        // 3. 等表单
        let accountBox = null, codeBox = null;
        for (let i = 0; i < 40; i++) {
          const inputs = [...document.querySelectorAll('input')]
            .filter(el => el.offsetWidth > 0 && el.type === 'text');
          accountBox = inputs.find(el => /工号|学号|手机号/.test(el.placeholder || ''));
          codeBox = inputs.find(el => /验证码/.test(el.placeholder || ''));
          if (accountBox && codeBox) break;
          await sleep(200);
        }
        if (!codeBox) return 'no-form';
        if (!accountBox) return 'no-account';

        // 4. 填账号
        if (account) setVal(accountBox, account);
        await sleep(300);

        // 5. 勾「记住账号」
        [...document.querySelectorAll('label.ant-checkbox-wrapper')].forEach(label => {
          if (/记住/.test(label.textContent || '')) {
            const cb = label.querySelector('input[type=checkbox]');
            if (cb && !cb.checked) label.click();
          }
        });

        // 6. 按动作执行
        if (action === 'prepare') return 'ready';

        if (action === 'send') {
          const sendBtn = [...document.querySelectorAll('button')]
            .find(b => (b.textContent || '').includes('获取验证码'));
          if (!sendBtn) return 'no-button';
          const previous = snapshot();
          sendBtn.click();
          for (let i = 0; i < 60; i++) {
            await sleep(200);
            const fresh = freshMessages(previous);
            const error = fresh.find(m => /失败|错误|无效|频繁|不存在|未绑定|限制|稍后|不正确|过期/.test(m));
            if (error) return 'error:' + error;
            if (/\\d+\\s*(秒|s)|重新获取|重新发送/.test(sendBtn.textContent || '') ||
                fresh.some(m => /发送成功|已发送/.test(m))) return 'sent';
          }
          return 'timeout';
        }

        if (action === 'submit') {
          if (!code) return 'no-code';
          setVal(codeBox, code);
          await sleep(400);
          const loginBtn = [...document.querySelectorAll('button')]
            .find(b => (b.textContent || '').trim() === '登录');
          if (!loginBtn) return 'no-button';
          const previous = snapshot();
          loginBtn.click();
          for (let i = 0; i < 60; i++) {
            await sleep(200);
            const error = freshMessages(previous)[0];
            if (error) return 'error:' + error;
          }
          return 'timeout';
        }

        return 'unknown';
        """
}

// MARK: - Liquid Glass 卡片

extension View {
    func glassCard(radius: CGFloat = 22) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}
