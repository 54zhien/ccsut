//
//  LoginView.swift
//  CCSUT
//
//  登录页 · 验证码登录 + 扫码登录
//
//  学校 CAS 有三条路，密码那条要求「学号 + 密码 + 短信验证码」三重校验，
//  而密码根本不是同一个（很多人记不住）。改成走「验证码登录」页签：
//  只要工号/学号/手机号 + 一条短信，不需要密码。
//
//  所有网页操作都在 WebLoginSheet 里完成。
//

import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var account = ""
    @State private var code = ""
    @State private var sheet: LoginSheetRequest?

    @FocusState private var focused: Field?
    private enum Field { case account, code }

    var body: some View {
        ZStack {
            backdrop

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 48)
                    brand
                    formCard
                    qrRow
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            if account.isEmpty,
               let saved = UserDefaults.standard.string(forKey: "ccsut.lastAccount") {
                account = saved
            }
        }
        .sheet(item: $sheet) { req in
            WebLoginSheet(request: req)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
        }
    }

    // MARK: 品牌

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

    // MARK: 表单

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
                    .onSubmit { login() }

                Button {
                    sendCode()
                } label: {
                    Text("获取验证码")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.22), in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canSendCode)
            }

            Button {
                login()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
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
            .padding(.top, 4)
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

    // MARK: 扫码

    private var qrRow: some View {
        Button {
            open(LoginSheetRequest(mode: .qr, account: "", code: "", autoSend: false))
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

    // MARK: 背景

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

    private var trimmedAccount: String {
        account.trimmingCharacters(in: .whitespaces)
    }

    private var canSendCode: Bool { !trimmedAccount.isEmpty }
    private var canLogin: Bool { !trimmedAccount.isEmpty && code.count >= 4 }

    private func open(_ req: LoginSheetRequest) {
        focused = nil
        if !trimmedAccount.isEmpty {
            UserDefaults.standard.set(trimmedAccount, forKey: "ccsut.lastAccount")
        }
        sheet = req
    }

    /// 只发验证码：打开弹窗，自动切到验证码登录并点「获取验证码」
    private func sendCode() {
        open(LoginSheetRequest(
            mode: .sms,
            account: trimmedAccount,
            code: "",
            autoSend: true
        ))
    }

    /// 带验证码登录：打开弹窗，填账号 + 验证码并直接提交
    private func login() {
        open(LoginSheetRequest(
            mode: .sms,
            account: trimmedAccount,
            code: code.trimmingCharacters(in: .whitespaces),
            autoSend: false
        ))
    }
}

// MARK: - Liquid Glass 卡片

extension View {
    func glassCard(radius: CGFloat = 22) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}
