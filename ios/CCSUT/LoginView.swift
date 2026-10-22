//
//  LoginView.swift
//  CCSUT
//
//  登录页 · iOS 26 版
//
//  技术要点：
//    · SwiftUI 原生 WebView + WebPage（WebKit for SwiftUI，iOS 26）
//      不再需要 UIViewRepresentable 包 WKWebView
//    · callJavaScript(_:arguments:) 直接注入参数，无需手写 JSON 转义
//    · glassEffect 做 Liquid Glass 材质（iOS 26），低版本回退到 .thinMaterial
//

import SwiftUI
import WebKit
import Observation

// MARK: - 登录阶段

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
        case .done: return "成功"
        case .failed: return "重试"
        }
    }
}

// MARK: - 登录页

struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var page: WebPage
    @State private var username = ""
    @State private var password = ""
    @State private var stage: LoginStage = .idle
    @State private var manualMode = false
    @State private var didInject = false
    @State private var logLines: [String] = []

    @FocusState private var focused: Field?
    private enum Field { case user, pass }

    init() {
        var config = WebPage.Configuration()
        config.websiteDataStore = WebStore.dataStore
        let page = WebPage(configuration: config)
        page.customUserAgent = UserAgent.mobile
        _page = State(initialValue: page)
    }

    var body: some View {
        ZStack {
            // WebView 必须留在层级里，否则不执行 JS；平时缩成 1×1
            webHost

            if !manualMode {
                nativeLayer
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.smooth(duration: 0.28), value: manualMode)
        .onChange(of: page.url) { _, newValue in
            guard let newValue else { return }
            handleNavigation(to: newValue)
        }
        .onAppear {
            if username.isEmpty,
               let saved = UserDefaults.standard.string(forKey: "ccsut.lastUsername") {
                username = saved
            }
        }
    }

    // MARK: WebView 承载

    @ViewBuilder
    private var webHost: some View {
        if manualMode {
            VStack(spacing: 0) {
                manualBar
                WebView(page)
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(.background)
        } else {
            WebView(page)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var manualBar: some View {
        HStack {
            Button {
                manualMode = false
                stage = .idle
            } label: {
                Label("返回", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            Text("网页登录")
                .font(.subheadline.weight(.semibold))
            Spacer()
            // 占位保持居中
            Label("返回", systemImage: "chevron.left")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: 原生层

    private var nativeLayer: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                brand
                formCard
                if case .failed(let msg) = stage { errorBanner(msg) }
                fallbackRow
                footer
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 36)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(backdrop)
    }

    // MARK: 品牌区

    private var brand: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 92, height: 92)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.breathe, options: .repeat(2), value: stage == .idle)
            }

            VStack(spacing: 6) {
                Text("长工院教务")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text("长沙工业学院 · 统一身份认证")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    // MARK: 表单

    private var formCard: some View {
        VStack(spacing: 16) {
            inputRow(
                symbol: "person.text.rectangle",
                placeholder: "学号",
                text: $username,
                secure: false
            )
            .textContentType(.username)
            .keyboardType(.asciiCapable)
            .focused($focused, equals: .user)
            .submitLabel(.next)
            .onSubmit { focused = .pass }

            Divider().overlay(.white.opacity(0.18))

            inputRow(
                symbol: "lock.rotation",
                placeholder: "密码",
                text: $password,
                secure: true
            )
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
                    Text(stage.caption)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canSubmit ? Color.white : Color.white.opacity(0.45))
                .foregroundStyle(Color(red: 0.10, green: 0.31, blue: 0.82))
                .clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || stage.isBusy)
            .padding(.top, 4)
        }
        .padding(20)
        .glassCard(radius: 26)

        // 调试日志（仅在忙碌时露出）
        .overlay(alignment: .bottom) {
            if stage.isBusy, !logLines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(logLines.suffix(3), id: \.self) { line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .offset(y: 46)
            }
        }
    }

    private func inputRow(
        symbol: String,
        placeholder: String,
        text: Binding<String>,
        secure: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
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

    // MARK: 兜底入口

    private var fallbackRow: some View {
        Button {
            manualMode = true
            didInject = true          // 手动模式下不再自动注入
            stage = .loading
            page.load(URLRequest(url: SessionStore.casLoginURL))
        } label: {
            Label("用网页登录", systemImage: "safari")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("登录后状态保持 14 天，到期自动续期")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))

            if let days = session.tgcRemainingDays {
                Text("当前凭证剩余 \(days, format: .number.precision(.fractionLength(1))) 天")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
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

    // MARK: 背景

    private var backdrop: some View {
        MeshGradient(
            width: 3,
            height: 3,
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
        logLines = []
        stage = .loading
        page.load(URLRequest(url: SessionStore.casLoginURL))
    }

    private func handleNavigation(to url: URL) {
        let absolute = url.absoluteString

        // 落到教务系统 → 成功
        if absolute.contains("tls.ccsut.cn"),
           !absolute.contains("/admin/login"),
           !absolute.contains("loginFailPage") {
            guard stage != .done else { return }
            stage = .done
            logLines.append("✓ 已进入教务系统")
            Task {
                await session.adoptCookies()
                await session.refreshIfNeeded()
            }
            return
        }

        // CAS 登录页 → 注入
        if absolute.contains("auth.ccsut.cn"),
           absolute.contains("/cas/login"),
           !didInject {
            didInject = true
            Task { await inject() }
        }
    }

    // MARK: 注入填表脚本

    private func inject() async {
        stage = .injecting
        logLines.append("切换密码登录…")

        do {
            let result = try await page.callJavaScript(
                Self.loginScriptBody,
                arguments: [
                    "username": username,
                    "password": password,
                ]
            )

            let outcome = (result as? String) ?? ""
            logLines.append("注入：\(outcome)")

            guard outcome == "ok" else {
                stage = .failed(outcome == "no-form"
                    ? "没找到登录表单，试试下方「用网页登录」"
                    : "页面结构变了（\(outcome)）")
                return
            }

            stage = .submitting
            logLines.append("已提交，等待跳转…")

            // 15 秒还没跳走，视为失败（密码错 / 需要验证码 / 账号被锁）
            try? await Task.sleep(for: .seconds(15))
            if stage == .submitting {
                stage = .failed("登录没有跳转，可能是密码错误或需要验证码。试试「用网页登录」")
            }
        } catch {
            stage = .failed("注入失败：\(error.localizedDescription)")
        }
    }

    /// callJavaScript 传入的是「函数体」，参数直接以变量名可用
    private static let loginScriptBody = """
        const setVal = (el, v) => {
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(el, v);
          ['input', 'change', 'keyup', 'blur'].forEach(t =>
            el.dispatchEvent(new Event(t, { bubbles: true })));
        };

        const sleep = ms => new Promise(r => setTimeout(r, ms));

        // 1. 切到「密码登录」
        const tabs = [...document.querySelectorAll('.ant-tabs-tab')];
        const pwdTab = tabs.find(t => (t.textContent || '').includes('密码登录'));
        if (pwdTab && !pwdTab.classList.contains('ant-tabs-tab-active')) {
          pwdTab.click();
          await sleep(600);
        }

        // 2. 等表单
        let pwd = null;
        for (let i = 0; i < 25 && !pwd; i++) {
          pwd = [...document.querySelectorAll('input')].find(el => el.type === 'password');
          if (!pwd) await sleep(200);
        }
        if (!pwd) return 'no-form';

        // 3. 填值
        const texts = [...document.querySelectorAll('input')].filter(el => el.type === 'text');
        const user = texts.find(el => /用户名|手机号|账号/.test(el.placeholder || '')) || texts[0];
        if (user) setVal(user, username);
        setVal(pwd, password);

        // 4. 勾「记住账号 / 记住密码」—— TGC 长效的前提
        [...document.querySelectorAll('.ant-checkbox-wrapper')].forEach(label => {
          if (/记住/.test(label.textContent || '')) {
            const cb = label.querySelector('input[type=checkbox]');
            if (cb && !cb.checked) label.click();
          }
        });

        // 5. 提交
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
    /// Liquid Glass 卡片
    func glassCard(radius: CGFloat = 22) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}
