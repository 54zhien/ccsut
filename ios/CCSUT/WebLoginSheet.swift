//
//  WebLoginSheet.swift
//  CCSUT
//
//  统一身份认证 · 底部弹起的 large sheet
//
//  设计要点：
//    · 用 .presentationDetents([.large]) 走 Apple 官方 sheet
//    · WebView 生命周期跟着 sheet 走，关闭即销毁，不留在主界面上
//    · 传了账号密码就自动填表；验证码这关必须人工（短信验证码）
//    · 一旦落到 tls.ccsut.cn 就接管 Cookie 并自动关闭
//

import SwiftUI
import WebKit

// MARK: - 模式

enum LoginSheetMode: String, Identifiable {
    case password     // 账号密码，自动填表
    case qr           // 扫码，不填表

    var id: String { rawValue }
    var title: String {
        switch self {
        case .password: return "账号密码登录"
        case .qr: return "扫码登录"
        }
    }
}

// MARK: - 弹窗

struct WebLoginSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    let mode: LoginSheetMode
    let username: String
    let password: String

    @State private var webView: WKWebView
    @State private var nav = WebNavigator()
    @State private var status: String = ""
    @State private var didInject = false

    init(mode: LoginSheetMode, username: String = "", password: String = "") {
        self.mode = mode
        self.username = username
        self.password = password
        _webView = State(initialValue: WebFactory.make())
    }

    var body: some View {
        NavigationStack {
            WebPanel(webView: webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if !status.isEmpty {
                        statusBar
                    }
                }
                .navigationTitle(mode.title)
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

    // MARK: 状态条

    private var statusBar: some View {
        HStack(spacing: 8) {
            if webView.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "info.circle")
                    .font(.caption)
            }
            Text(status)
                .font(.caption)
                .lineLimit(2)
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

        // 1. 到了教务系统 → 接管
        //    必须按 host 判断：CAS 登录页的 service 参数里也含 tls.ccsut.cn
        if url.host == "tls.ccsut.cn",
           !absolute.contains("/admin/login"),
           !absolute.contains("loginFailPage") {
            Task { await finish() }
            return
        }

        // 2. 停在 CAS 登录页 → 自动填表（仅账号密码模式）
        if url.host == "auth.ccsut.cn",
           absolute.contains("/cas/login"),
           mode == .password,
           !didInject {
            didInject = true
            Task { await inject() }
        }
    }

    private func inject() async {
        status = "填写账号密码…"

        do {
            let raw = try await webView.callAsync(Self.fillScript, arguments: [
                "username": username,
                "password": password,
            ])
            let outcome = (raw as? String) ?? "(nil)"

            switch outcome {
            case "need-captcha":
                // 账号密码已填好，停在页面上等用户点「获取验证码」
                status = "已填好账号密码 · 请点「获取验证码」并输入短信码，然后点「登录」"
            case "waiting":
                status = "账号密码已填好，请手动点「登录」"
            case "ok":
                status = "已提交，等待跳转…"
            case "no-tab":
                status = "认证页没渲染出页签，点右上角刷新试试"
            case "no-form":
                status = "没找到密码框，点右上角刷新试试"
            default:
                status = "填表异常（\(outcome)）"
            }
        } catch {
            status = "填表失败：\(error.localizedDescription)"
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

    // MARK: 注入脚本

    /// 只填账号密码，不点提交。
    /// 原因：这个 CAS 强制要短信验证码，自动提交必然返回「验证码不正确」，
    /// 不如把账号密码填好，让用户补一位验证码再自己点登录。
    private static let fillScript = """
        const setVal = (el, v) => {
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(el, v);
          ['input', 'change', 'keyup', 'blur'].forEach(t =>
            el.dispatchEvent(new Event(t, { bubbles: true })));
        };

        const sleep = ms => new Promise(r => setTimeout(r, ms));

        // 1. 等 Angular 渲染页签
        let pwdTab = null;
        for (let i = 0; i < 50 && !pwdTab; i++) {
          const tabs = [...document.querySelectorAll('.ant-tabs-tab')];
          pwdTab = tabs.find(t => (t.textContent || '').includes('密码登录'));
          if (!pwdTab) await sleep(200);
        }
        if (!pwdTab) return 'no-tab';

        // 2. 切到密码登录
        if (!pwdTab.classList.contains('ant-tabs-tab-active')) {
          pwdTab.click();
          await sleep(900);
        }

        // 3. 等密码框
        let pwd = null;
        for (let i = 0; i < 40 && !pwd; i++) {
          pwd = [...document.querySelectorAll('input')]
            .find(el => el.type === 'password' && el.offsetWidth > 0);
          if (!pwd) await sleep(200);
        }
        if (!pwd) return 'no-form';

        // 4. 填账号密码
        const user = [...document.querySelectorAll('input')]
          .find(el => /用户名|手机号|账号/.test(el.placeholder || '') && el.offsetWidth > 0);
        if (user) setVal(user, username);
        setVal(pwd, password);

        // 5. 勾「记住账号」「记住密码」
        [...document.querySelectorAll('label.ant-checkbox-wrapper')].forEach(label => {
          if (/记住/.test(label.textContent || '')) {
            const cb = label.querySelector('input[type=checkbox]');
            if (cb && !cb.checked) label.click();
          }
        });

        await sleep(400);

        // 6. 有验证码框就停下，交给用户
        const captcha = [...document.querySelectorAll('input')]
          .find(el => /验证码/.test(el.placeholder || '') && el.offsetWidth > 0);
        if (captcha) return 'need-captcha';

        // 7. 没有验证码 → 直接提交
        const btn = [...document.querySelectorAll('button')]
          .find(b => (b.textContent || '').trim() === '登录');
        if (!btn) return 'waiting';
        btn.click();
        return 'ok';
        """
}
