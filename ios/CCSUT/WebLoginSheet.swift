//
//  WebLoginSheet.swift
//  CCSUT
//
//  统一身份认证 · 底部弹起的 large sheet
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

    let request: LoginSheetRequest

    @State private var webView: WKWebView
    @State private var nav = WebNavigator()
    @State private var status = ""
    @State private var didPrepare = false

    init(request: LoginSheetRequest) {
        self.request = request
        _webView = State(initialValue: WebFactory.make())
    }

    var body: some View {
        NavigationStack {
            WebPanel(webView: webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if !status.isEmpty { statusBar }
                }
                .navigationTitle(request.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            webView.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .onAppear(perform: start)
                .onChange(of: nav.currentURL) { _, url in
                    guard let url else { return }
                    handle(url)
                }
                .onChange(of: nav.lastError) { _, err in
                    if let err { status = "⚠️ \(err)" }
                }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if webView.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "info.circle").font(.caption)
            }
            Text(status).font(.caption).lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.thinMaterial)
    }

    // MARK: 流程

    private func start() {
        webView.navigationDelegate = nav
        nav.onNavigate = { url in handle(url) }
        status = "加载认证页…"
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
                status = "认证页没渲染出页签，点右上角刷新"
            case "no-form":
                status = "没找到验证码登录表单，点右上角刷新"
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
