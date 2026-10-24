//
//  CCSUTApp.swift
//  CCSUT
//
//  入口 · TabView 使用 iOS 18 的 Tab 值绑定语法
//

import SwiftUI
import WebKit

@main
struct CCSUTApp: App {
    @State private var session = SessionStore()
    @State private var deviceCornerRadius: CGFloat = 0

    var body: some Scene {
        WindowGroup {
            Group {
                if InterfacePreview.enabled {
                    switch InterfacePreview.page {
                    case "login": LoginView()
                    case "launch": LaunchView()
                    default: MainTabs()
                    }
                } else { RootView() }
            }
                .environment(session)
                .tint(.accentColor)
                .environment(\.deviceCornerRadius, deviceCornerRadius)
                .background {
                    ScreenCornerReader { deviceCornerRadius = $0 }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .task {
                    guard !InterfacePreview.enabled else { return }
                    await session.bootstrap()
                }
        }
    }
}

// MARK: - 根视图

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .checking:
                LaunchView()
            case .loggedOut:
                LoginView()
            case .loggedIn, .refreshing:
                MainTabs()
            }
        }
        .animation(.smooth(duration: 0.35), value: session.phase)
    }
}

// MARK: - 启动页

struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                SchoolEmblemView(size: 116, rotatingRing: true)
                Text("登陆中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

struct SchoolEmblemView: View {
    let size: CGFloat
    var rotatingRing = false
    var monochrome = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            Image("SchoolEmblemCore")
                .renderingMode(monochrome ? .template : .original)
                .resizable().scaledToFit()
            Image("SchoolEmblemRing")
                .renderingMode(monochrome ? .template : .original)
                .resizable().scaledToFit()
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(rotatingRing && !reduceMotion ? .linear(duration: 8).repeatForever(autoreverses: false) : nil,
                           value: spinning)
        }
        .foregroundStyle(.primary)
        .frame(width: size, height: size)
        .accessibilityLabel("长沙工业学院校徽")
        .onAppear { spinning = rotatingRing && !reduceMotion }
        .onChange(of: reduceMotion) { _, reduced in spinning = rotatingRing && !reduced }
        .onDisappear { spinning = false }
    }
}

/// The supplied PNG stays intact. Clip its right-hand signature in native layout.
struct SchoolWordmarkView: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 724
            Image("SchoolSignature")
                .renderingMode(.template)
                .resizable()
                .frame(width: 992 * scale, height: 329 * scale)
                .offset(x: -268 * scale, y: -64 * scale)
                .foregroundStyle(.primary)
        }
        .aspectRatio(724.0 / 198.0, contentMode: .fit)
        .clipped()
        .accessibilityLabel("长沙工业学院 Changsha Institute of Technology")
    }
}

// MARK: - 主 Tab

struct MainTabs: View {
    @Environment(SessionStore.self) private var session

    enum AppTab: Hashable {
        case schedule, academic
    }

    @State private var selection: AppTab = .schedule

    init() {
        _selection = State(initialValue: ["academic", "scores", "exams", "electives"].contains(InterfacePreview.page) ? .academic : .schedule)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("课表", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }

            Tab("教务", systemImage: "square.grid.2x2", value: AppTab.academic) {
                AcademicView()
            }
        }
        .tabBarMinimizeBehavior(.never)
    }
}

// MARK: - 账号入口与面板

struct StudentAvatar: View {
    @Environment(SessionStore.self) private var session
    let size: CGFloat

    var body: some View {
        let name = session.studentName ?? (InterfacePreview.enabled ? "预览同学" : "")
        Text(name.first.map(String.init) ?? "同")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.12), in: .circle)
            .accessibilityHidden(true)
    }
}

struct AccountButton: View {
    @Environment(\.deviceCornerRadius) private var deviceCornerRadius
    @ScaledMetric(relativeTo: .body) private var profileSheetHeight: CGFloat = 320
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            StudentAvatar(size: 34)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("账号")
        .sheet(isPresented: $isPresented) {
            ProfileView()
                .presentationDetents([.height(profileSheetHeight)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(SheetLayout.cornerRadius(deviceCornerRadius))
        }
        .onAppear {
            if InterfacePreview.page == "account" { isPresented = true }
        }
    }
}

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.deviceCornerRadius) private var deviceCornerRadius
    @State private var showLogoutAlert = false

    var body: some View {
        GeometryReader { viewport in
            let edgeInset = max(20, SheetLayout.cornerRadius(deviceCornerRadius) - 25)
            let reservedHeight = max(96, SheetLayout.cornerRadius(deviceCornerRadius) + 30)
            ScrollView {
                VStack(spacing: 14) {
                    StudentAvatar(size: 76)

                    VStack(spacing: 6) {
                        Text(session.studentName ?? (InterfacePreview.enabled ? "预览同学" : "已登录"))
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(session.studentId ?? (InterfacePreview.enabled ? "示例账号" : "—"))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, reservedHeight)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .top) {
                SheetHeader(title: "账号") { dismiss() }
            }
            .overlay(alignment: .bottom) {
                Button(role: .destructive) { showLogoutAlert = true } label: {
                    Text("退出登录")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.red)
                .padding(.horizontal, edgeInset)
                .padding(.bottom, max(edgeInset, viewport.safeAreaInsets.bottom))
            }
        }
        .ignoresSafeArea(.container)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("退出登录", isPresented: $showLogoutAlert) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                Task { await session.logout(); dismiss() }
            }
        } message: {
            Text("下次打开需要重新登录。")
        }
    }

}
