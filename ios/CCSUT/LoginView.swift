//
//  LoginView.swift
//  CCSUT
//
//  登录页 · 短信验证码，全程留在 App 内
//
//  结构：
//    底层常驻一个全屏 WKWebView（不可交互），上层用不透明的原生界面盖住。
//    WebView 依然在视图层级里、依然全屏渲染，所以 CAS 的 Angular 能正常跑；
//    而用户看到和操作的完全是原生控件。
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
    @State private var showWeb = false          // 露出网页给用户看
    @State private var prepared = false         // 页签是否已经切过

    @State private var cooldown = 0             // 重发倒计时
    @State private var timer: Task<Void, Never>?

    @FocusState private var focused: Field?
    private enum Field { case account, code }

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
            // 底层：全屏 WebView。必须真的全屏且不透明地渲染，
            // 只是被上面的原生层挡住而已。
            WebPanel(webView: webView)
                .ignoresSafeArea()
                .allowsHitTesting(showWeb)

            if showWeb {
                webOverlay
            } else {
                nativeLayer
            }
        }
        .animation(.smooth(duration: 0.25), value: showWeb)
        .onAppear(perform: start)
        .onDisappear { timer?.cancel() }
        .onChange(of: nav.currentURL) { _, url in
            guard let url else { return }
            handle(url)
        }
        .onChange(of: nav.lastError) { _, err in
            if let err, busy != .done {
                hint = err
                busy = .idle
            }
        }
    }

    // MARK: 网页层（用户主动查看时）

    private var webOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    showWeb = false
                } label: {
                    Label("返回", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Text("统一身份认证")
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

    // MARK: 原生层

    private var nativeLayer: some View {
        ZStack {
            backdrop

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 56)
                    brand
                    formCard
                    qrHint
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var brand: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 90, height: 90)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 42, weight: .medium))
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
            inputRow(symbol: "person.text.rectangle",
                     placeholder: "手机号 / 学号",
                     text: $account,
                     keyboard: .default)
                .textContentType(.telephoneNumber)
                .focused($focused, equals: .account)
                .submitLabel(.next)
                .onSubmit { focused = .code }

            Divider().overlay(.white.opacity(0.18))

            HStack(spacing: 10) {
                inputRow(symbol: "number.square",
                         placeholder: "短信验证码",
                         text: $code,
                         keyboard: .numberPad)
                    .focused($focused, equals: .code)
                    .submitLabel(.go)
                    .onSubmit { submit() }

                Button(action: sendCode) {
                    Group {
                        if busy == .sending {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Text(cooldown > 0 ? "\(cooldown)s" : "获取验证码")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    .frame(width: 78)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.22), in: .capsule)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }

            Button(action: submit) {
                HStack(spacing: 10) {
                    if busy == .logging {
                        ProgressView().controlSize(.small)
                            .tint(Color(red: 0.10, green: 0.31, blue: 0.82))
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    Text("登录").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canLogin ? Color.white : Color.white.opacity(0.45))
                .foregroundStyle(Color(red: 0.10, green: 0.31, blue: 0.82))
                .clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canLogin)

            if !hint.isEmpty {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .glassCard(radius: 26)
    }

    private func inputRow(symbol: String,
                          placeholder: String,
                          text: Binding<String>,
                          keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22)

            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .foregroundStyle(.white)
        }
        .padding(.vertical, 6)
    }

    private var qrHint: some View {
        Button {
            showWeb = true
        } label: {
            Label("扫码登录", systemImage: "qrcode")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(.white.opacity(0.18), in: .rect(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(.white.opacity(0.26), lineWidth: 1)
                }
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
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

    // MARK: 状态

    private var trimmed: String { account.trimmingCharacters(in: .whitespaces) }
    private var canSend: Bool { !trimmed.isEmpty && busy != .sending && cooldown == 0 }
    private var canLogin: Bool { !trimmed.isEmpty && code.count >= 4 && busy != .logging && busy != .done }

    // MARK: 流程

    private func start() {
        webView.navigationDelegate = nav
        nav.onNavigate = { url in handle(url) }
        if account.isEmpty,
           let saved = UserDefaults.standard.string(forKey: "ccsut.lastAccount") {
            account = saved
        }
        webView.load(URLRequest(url: SessionStore.casLoginURL))
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
        focused = nil
        guard canSend else { return }
        UserDefaults.standard.set(trimmed, forKey: "ccsut.lastAccount")

        busy = .sending
        hint = ""

        Task {
            let r = try? await webView.callAsync(Self.script, arguments: [
                "account": trimmed,
                "code": "",
                "action": "send",
            ])
            let outcome = (r as? String) ?? "?"

            await MainActor.run {
                busy = .idle
                switch outcome {
                case "sent":
                    hint = ""
                    startCooldown(60)
                    focused = .code
                case "no-tab", "no-form":
                    hint = "认证页还没准备好，点右上角网页看看"
                case "no-account":
                    hint = "账号框没填上，先检查账号"
                default:
                    hint = "发送失败（\(outcome)），试试网页登录"
                }
            }
        }
    }

    private func submit() {
        focused = nil
        guard canLogin else { return }
        UserDefaults.standard.set(trimmed, forKey: "ccsut.lastAccount")

        busy = .logging
        hint = ""

        Task {
            let r = try? await webView.callAsync(Self.script, arguments: [
                "account": trimmed,
                "code": code.trimmingCharacters(in: .whitespaces),
                "action": "submit",
            ])
            let outcome = (r as? String) ?? "?"

            if outcome != "submitted" {
                await MainActor.run {
                    busy = .idle
                    hint = outcome == "no-code" ? "页面还没准备好，稍等再点一次" : "提交失败（\(outcome)）"
                }
            }
            // 成功时会由导航回调触发 finish()
        }
    }

    private func finish() async {
        // 跳转瞬间 Cookie 可能还在写，重试几次
        for attempt in 0..<3 {
            if await session.adoptCookies() {
                busy = .done
                return
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
        busy = .idle
        hint = "登录没有完成，请再试一次"
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
          sendBtn.click();
          await sleep(800);
          return 'sent';
        }

        if (action === 'submit') {
          if (!code) return 'no-code';
          setVal(codeBox, code);
          await sleep(400);
          const loginBtn = [...document.querySelectorAll('button')]
            .find(b => (b.textContent || '').trim() === '登录');
          if (!loginBtn) return 'no-button';
          loginBtn.click();
          return 'submitted';
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
