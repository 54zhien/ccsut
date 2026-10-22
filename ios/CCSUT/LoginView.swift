//
//  LoginView.swift
//  CCSUT
//
//  登录页
//
//  两个入口：
//    · 账号密码 → 弹 large sheet，里面自动填表，验证码人工补
//    · 扫码     → 弹同样的 sheet，直接显示二维码
//
//  WebView 不再嵌在主界面里，生命周期跟着 sheet 走。
//

import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var username = ""
    @State private var password = ""
    @State private var sheet: LoginSheetMode?

    @FocusState private var focused: Field?
    private enum Field { case user, pass }

    var body: some View {
        ZStack {
            backdrop

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 48)
                    brand
                    formCard
                    qrRow
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            if username.isEmpty,
               let saved = UserDefaults.standard.string(forKey: "ccsut.lastUsername") {
                username = saved
            }
        }
        .sheet(item: $sheet) { mode in
            WebLoginSheet(mode: mode, username: username, password: password)
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
                .onSubmit { open(.password) }

            Button {
                open(.password)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("登录")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canSubmit ? Color.white : Color.white.opacity(0.45))
                .foregroundStyle(Color(red: 0.10, green: 0.31, blue: 0.82))
                .clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .padding(.top, 4)

            Text("登录时会自动填好账号密码，验证码处按提示补一位短信码即可")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
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

    // MARK: 扫码

    private var qrRow: some View {
        Button {
            open(.qr)
        } label: {
            Label("扫码登录 · 不需要验证码", systemImage: "qrcode")
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

    private var footer: some View {
        Text("登录后状态保持 14 天，到期自动续期")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.7))
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

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func open(_ mode: LoginSheetMode) {
        focused = nil
        if !username.isEmpty {
            UserDefaults.standard.set(username, forKey: "ccsut.lastUsername")
        }
        sheet = mode
    }
}

// MARK: - Liquid Glass 卡片

extension View {
    func glassCard(radius: CGFloat = 22) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}
