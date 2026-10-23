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

    var body: some Scene {
        WindowGroup {
            Group {
                if InterfacePreview.enabled { MainTabs() } else { RootView() }
            }
                .environment(session)
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
    @State private var spin = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.20, blue: 0.62),
                    Color(red: 0.22, green: 0.47, blue: 0.95),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(spin ? 1.06 : 0.94)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: spin)

                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)

                Text("正在恢复会话…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .onAppear { spin = true }
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
        _selection = State(initialValue: InterfacePreview.page == "academic" ? .academic : .schedule)
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
        .tabBarMinimizeBehavior(.onScrollDown)   // iOS 26
    }
}

// MARK: - 账号入口与面板

struct AccountButton: View {
    @Environment(SessionStore.self) private var session
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("账号")
        .sheet(isPresented: $isPresented) {
            ProfileView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .onAppear {
            if InterfacePreview.page == "account" { isPresented = true }
        }
    }
}

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(.tint.opacity(0.15))
                                .frame(width: 54, height: 54)
                            Text(initials)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tint)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.studentName ?? (InterfacePreview.enabled ? "预览同学" : "已登录"))
                                .font(.headline)
                            Text(session.studentId ?? (InterfacePreview.enabled ? "示例账号" : "—"))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        showLogoutAlert = true
                    }
                }
            }
            .navigationTitle("账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
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

    private var initials: String {
        let name = session.studentName ?? (InterfacePreview.enabled ? "预览同学" : "")
        guard let first = name.first else { return "?" }
        return String(first)
    }
}
