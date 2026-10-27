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
    @Environment(\.deviceCornerRadius) private var deviceCornerRadius
    @ScaledMetric(relativeTo: .body) private var topSymbolSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var browserSymbolSize: CGFloat = 24

    private let request: LoginSheetRequest?
    private let ownsNavigation: Bool

    @State private var webView: WKWebView
    @State private var nav = WebNavigator()
    @State private var status = ""
    @State private var didPrepare = false
    @State private var topControlDiameter: CGFloat = 0
    @State private var bottomControlDiameter: CGFloat = 0

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
        GeometryReader { viewport in
            WebPanel(webView: webView, extendsUnderControls: true)
                .overlay(alignment: .top) { topControls }
                .overlay(alignment: .bottom) {
                    bottomControls
                        .padding(.bottom, max(SheetLayout.controlInset(deviceCornerRadius, diameter: bottomControlDiameter), viewport.safeAreaInsets.bottom))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container)
        .tint(nil)
        .onAppear {
            #if DEBUG
            if InterfacePreview.enabled { loadPreview(); return }
            #endif
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
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(SheetLayout.cornerRadius(deviceCornerRadius))
    }

    private var topControls: some View {
        HStack {
            SheetSymbolButton(symbol: "xmark", label: "关闭网页登录", symbolSize: topSymbolSize) { dismiss() }
            Spacer()
            SheetSymbolButton(symbol: "arrow.clockwise", label: "刷新网页", symbolSize: topSymbolSize, action: refresh)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topControlDiameter = $0 }
        .padding(.horizontal, SheetLayout.controlInset(deviceCornerRadius, diameter: topControlDiameter))
        .padding(.top, SheetLayout.controlInset(deviceCornerRadius, diameter: topControlDiameter))
    }

    private var bottomControls: some View {
        HStack(alignment: .center, spacing: 12) {
            if !status.isEmpty {
                Text(AppMessages.readable(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .frame(height: bottomControlDiameter > 0 ? bottomControlDiameter : nil)
                    .glassEffect(.regular, in: .capsule)
            }
            Spacer(minLength: 0)
            SheetSymbolButton(symbol: "safari", label: "在 Safari 中打开当前网址", symbolSize: browserSymbolSize, action: openCurrentURLInSafari)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomControlDiameter = $0 }
        }
        .padding(.horizontal, SheetLayout.controlInset(deviceCornerRadius, diameter: bottomControlDiameter))
    }

    private var currentURL: URL? {
        webView.url ?? nav.currentURL ?? SessionStore.casLoginURL
    }

    private func refresh() {
        #if DEBUG
        if InterfacePreview.enabled { loadPreview(); return }
        #endif
        status = "加载认证页…"
        didPrepare = false
        nav.refresh(in: webView)
    }

    #if DEBUG
    private func loadPreview() {
        webView.loadHTMLString("""
        <!doctype html><html lang="zh"><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>:root{color-scheme:light dark}body{font-family:system-ui;margin:0;padding:140px 28px;background:Canvas;color:CanvasText}
        h1{font-size:28px}p{font-size:16px;line-height:1.7;opacity:.65}</style></head>
        <body><h1>统一身份认证</h1><p>此页面用于检查网页登录控件的布局。<br>未连接学校服务器。</p></body></html>
        """, baseURL: nil)
    }
    #endif

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
           !APIClient.isAuthenticationURL(url) {
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

        let tabs = [];
        for (let i = 0; i < 50; i++) {
          tabs = [...document.querySelectorAll('.ant-tabs-tab')];
          if (tabs.length) break;
          await sleep(200);
        }
        if (!tabs.length) return 'no-tab';

        const target = tabs.find(t => (t.textContent || '').includes('验证码登录'));
        if (!target) return 'no-tab';
        if (!target.classList.contains('ant-tabs-tab-active')) {
          target.click();
          await sleep(1000);
        }

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

        if (accountBox && account) {
          setVal(accountBox, account);
        } else if (!accountBox) {
          return 'no-account';
        }
        await sleep(400);

        [...document.querySelectorAll('label.ant-checkbox-wrapper')].forEach(label => {
          if (/记住/.test(label.textContent || '')) {
            const cb = label.querySelector('input[type=checkbox]');
            if (cb && !cb.checked) label.click();
          }
        });

        if (autoSend === '1') {
          const sendBtn = [...document.querySelectorAll('button')]
            .find(b => (b.textContent || '').includes('获取验证码'));
          if (!sendBtn) return 'send-failed';
          sendBtn.click();
          await sleep(1200);
          return 'sent';
        }

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
