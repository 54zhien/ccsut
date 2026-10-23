//
//  WebLoginSheet.swift
//  CCSUT
//
//  统一身份认证 · 高度跟随网页内容的系统玻璃 sheet
//
//  CAS 有三个页签：扫码登录 / 密码登录 / 验证码登录
//  这里只走两条不需要密码的：
//    · 扫码      —— 二维码，扫完自动跳转
//    · 验证码登录 —— 工号/学号/手机号 + 短信验证码
//
//  验证码必须人工输入（短信），脚本负责切页签、填账号、
//  必要时点「获取验证码」，剩下的交给用户。
//

import SwiftUI
import WebKit

// MARK: - 请求

struct LoginSheetRequest: Identifiable {
    enum Mode {
        case sms      // 验证码登录
        case qr       // 扫码登录
    }

    let id = UUID()
    let mode: Mode
    let account: String
    let code: String
    let autoSend: Bool       // 打开后自动点「获取验证码」

    var title: String {
        switch mode {
        case .sms: return "验证码登录"
        case .qr: return "扫码登录"
        }
    }
}

// MARK: - 弹窗

struct WebLoginSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let request: LoginSheetRequest?
    private let ownsNavigation: Bool

    @State private var webView: WKWebView
    @State private var nav = WebNavigator()
    @State private var status = ""
    @State private var didPrepare = false
    @State private var contentHeight: CGFloat = 320
    @State private var topControlsHeight: CGFloat = 64
    @State private var bottomControlsHeight: CGFloat = 64

    /// LoginView passes its already-running web view and navigator. They are moved
    /// into this sheet only after the source WebPanel has left the main view tree.
    init(webView: WKWebView, navigator: WebNavigator) {
        request = nil
        ownsNavigation = false
        _webView = State(initialValue: webView)
        _nav = State(initialValue: navigator)
    }

    /// Standalone entry retained for callers that need a dedicated web login flow.
    init(request: LoginSheetRequest) {
        self.request = request
        ownsNavigation = true
        _webView = State(initialValue: WebFactory.make())
        _nav = State(initialValue: WebNavigator())
    }

    var body: some View {
        VStack(spacing: 0) {
            topControls
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topControlsHeight = $0 }
            WebPanel(webView: webView, onContentHeight: { height in
                if abs(contentHeight - height) > 1 { contentHeight = height }
            })
            bottomControls
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomControlsHeight = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(nil)
        .onAppear {
            if ownsNavigation { start() }
            else { nav.recoverLoginPageIfNeeded(in: webView) }
        }
        .onChange(of: nav.currentURL) { _, url in
            guard let url else { return }
            handle(url)
        }
        .onChange(of: nav.isFinished) { _, finished in
            if finished { status = "" }
        }
        .onChange(of: nav.lastError) { _, err in
            if err != nil { status = AppMessages.loadFailure }
        }
        .presentationDetents([.height(max(320, contentHeight) + topControlsHeight + bottomControlsHeight)])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    private var topControls: some View {
        HStack {
            Button(role: .close) { dismiss() }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("关闭网页登录")
            Spacer()
            Button("刷新网页", systemImage: "arrow.clockwise", action: refresh)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        }
        .controlSize(.large)
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            if !status.isEmpty {
                Text(AppMessages.readable(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Safari", systemImage: "safari", action: openCurrentURLInSafari)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .foregroundStyle(.primary)
                .accessibilityLabel("在 Safari 中打开当前网址")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var currentURL: URL? {
        webView.url ?? nav.currentURL ?? SessionStore.casLoginURL
    }

    private func refresh() {
        status = "加载认证页…"
        didPrepare = false
        nav.refresh(in: webView)
    }

    private func openCurrentURLInSafari() {
        guard let url = currentURL else { return }
        openURL(url)
    }

    // MARK: 流程

    private func start() {
        guard request != nil else { return }
        webView.navigationDelegate = nav
        nav.onNavigate = { url in handle(url) }
        status = "加载认证页…"
        nav.loadLoginPage(in: webView)
    }

    private func handle(_ url: URL) {
        guard let request else { return }
        let absolute = url.absoluteString

        // 到教务系统 → 接管
        if url.host == "tls.ccsut.cn",
           !absolute.contains("/admin/login"),
           !absolute.contains("loginFailPage") {
            Task { await finish() }
            return
        }

        // 停在 CAS 页 → 预置表单（只做一次）
        if url.host == "auth.ccsut.cn",
           absolute.contains("/cas/login"),
           request.mode == .sms,
           !didPrepare {
            didPrepare = true
            Task { await prepareSMS() }
        }
    }

    private func prepareSMS() async {
        guard let request else { return }
        status = "切到验证码登录…"
        do {
            let raw = try await webView.callAsync(Self.smsScript, arguments: [
                "account": request.account,
                "code": request.code,
                "autoSend": request.autoSend ? "1" : "0",
            ])
            let outcome = (raw as? String) ?? "(nil)"

            switch outcome {
            case "sent":
                status = "验证码已发送 · 收到短信后填进去，再点「登录」"
            case "filled":
                status = "已填好，正在提交…"
            case "no-code":
                status = "账号已填好 · 点「获取验证码」，收到短信后填进去再点登录"
            case "no-tab":
                status = "认证页没渲染出页签，请点右上角刷新"
            case "no-form":
                status = "没找到验证码登录表单，请点右上角刷新"
            case "no-account":
                status = "账号框是空的，请手动填一下"
            case "send-failed":
                status = "发送验证码失败，请手动点「获取验证码」"
            default:
                status = "准备表单时出错（\(outcome)）"
            }
        } catch {
            status = "准备失败：\(error.localizedDescription)"
        }
    }

    private func finish() async {
        guard ownsNavigation else { return }
        status = "接管会话…"
        let ok = await session.adoptCookies()
        if ok {
            dismiss()
        } else {
            status = session.lastError ?? "会话无效"
        }
    }

    // MARK: 脚本

    /// 切到「验证码登录」页签，填账号，
    /// 需要时点「获取验证码」，验证码非空则一并提交。
    private static let smsScript = """
        const setVal = (el, v) => {
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(el, v);
          ['input', 'change', 'keyup', 'blur'].forEach(t =>
            el.dispatchEvent(new Event(t, { bubbles: true })));
        };
        const sleep = ms => new Promise(r => setTimeout(r, ms));

        // 1. 等页签渲染
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

        // 3. 等表单（账号框 + 验证码框）
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

        // 4. 填账号
        if (accountBox && account) {
          setVal(accountBox, account);
        } else if (!accountBox) {
          return 'no-account';
        }
        await sleep(400);

        // 5. 勾「记住账号」
        [...document.querySelectorAll('label.ant-checkbox-wrapper')].forEach(label => {
          if (/记住/.test(label.textContent || '')) {
            const cb = label.querySelector('input[type=checkbox]');
            if (cb && !cb.checked) label.click();
          }
        });

        // 6. 需要时点「获取验证码」
        if (autoSend === '1') {
          const sendBtn = [...document.querySelectorAll('button')]
            .find(b => (b.textContent || '').includes('获取验证码'));
          if (!sendBtn) return 'send-failed';
          sendBtn.click();
          await sleep(1200);
          return 'sent';
        }

        // 7. 验证码已填 → 一并提交
        if (code) {
          setVal(codeBox, code);
          await sleep(400);
          const loginBtn = [...document.querySelectorAll('button')]
            .find(b => (b.textContent || '').trim() === '登录');
          if (!loginBtn) return 'no-code';
          loginBtn.click();
          return 'filled';
        }

        return 'no-code';
        """
}
