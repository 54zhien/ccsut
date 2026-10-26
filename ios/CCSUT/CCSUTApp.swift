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
    @State private var session = SessionStore(studentNameResolver: { account, generation in
        let client = CampusClient(account: account, credentials: CampusCookieCredentials())
        guard let name = try? await client.authenticatedDisplayName(expectedAccount: account,
                                                                    expectedGeneration: generation) else { return nil }
        return SessionStudentName(account: name.account, generation: name.generation, value: name.value)
    })
    @State private var deviceCornerRadius: CGFloat = 0

    var body: some Scene {
        WindowGroup {
            Group {
                if InterfacePreview.enabled {
                    switch InterfacePreview.page {
                    case "login": LoginView()
                    case "launch": LaunchView()
                    #if DEBUG
                    case "web-login": WebLoginPreviewHost()
                    case "elective-detail": DetailPreviewHost { CourseDetailSheet(item: InterfacePreview.classes[0]) }
                    case "enrolled-detail": DetailPreviewHost { EnrolledCourseDetail(record: InterfacePreview.enrolledCourses(term: "2026-2027-1")[1]) }
                    case "campus-privacy": CampusPrivacyPreview()
                    case "campus-form-leave": CampusFormPreviewHost(kind: .leave)
                    case "campus-form-departure": CampusFormPreviewHost(kind: .departure)
                    case "campus-electricity", "campus-electricity-confirmation", "campus-electricity-result", "campus-electricity-pending",
                         "campus-electricity-recovery-read", "campus-electricity-recovery-version",
                         "campus-electricity-recovery-corrupt", "campus-electricity-recovery-missing":
                        NavigationStack { EcardPaymentView() }
                    #endif
                    default: MainTabs()
                    }
                } else { RootView() }
            }
                .environment(session)
                .overlay(alignment: .bottomTrailing) {
                    #if DEBUG
                    if InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-reduce-motion") { CampusMotionPreviewProbe() }
                    #endif
                }
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

#if DEBUG
private struct DetailPreviewHost<Content: View>: View {
    @State private var presented = true
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
            .sheet(isPresented: $presented) { content }
    }
}

private struct WebLoginPreviewHost: View {
    @State private var presented = true
    var body: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
            .sheet(isPresented: $presented) {
                WebLoginSheet(request: .init(mode: .sms, account: "", code: "", autoSend: false))
            }
    }
}

private struct CampusFormPreviewHost: View {
    let kind: CampusFormKind
    @State private var showingForm = true
    var body: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
            .sheet(isPresented: $showingForm) { CampusFormView(kind: kind, account: "preview-account") }
    }
}

private struct CampusMotionPreviewProbe: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Text(reduced ? "reduce-motion-on" : "reduce-motion-off")
            .font(.caption2).padding(4).background(.background)
            .accessibilityIdentifier("campus-reduce-motion")
    }
}
#endif

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
        case schedule, academic, campus
    }

    @State private var selection: AppTab = .schedule

    init() {
        let page = InterfacePreview.page
        _selection = State(initialValue: page.hasPrefix("campus") ? .campus :
            (["academic", "scores", "exams", "electives"].contains(page) ? .academic : .schedule))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("课表", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }

            Tab("教务", systemImage: "square.grid.2x2", value: AppTab.academic) {
                AcademicView()
            }

            Tab("校园", systemImage: "building.2", value: AppTab.campus) {
                CampusView()
            }
        }
        .tabBarMinimizeBehavior(.never)
        #if DEBUG
        .background {
            if InterfacePreview.enabled && ProcessInfo.processInfo.arguments.contains("--preview-transition") {
                AcademicTabTransitionRootProbe()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        #endif
    }
}

// MARK: - 账号入口与面板

struct StudentAvatar: View {
    @Environment(SessionStore.self) private var session
    let size: CGFloat

    var body: some View {
        let name = session.studentName ?? (InterfacePreview.enabled ? "预览同学" : "")
        Group {
            if let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first {
                Text(String(first))
            } else {
                Image(systemName: "person.fill")
            }
        }
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
                .presentationDetents([.height(profileSheetHeight), .large])
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
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StudentAvatar(size: 72)

                    VStack(spacing: 6) {
                        Text(session.studentName ?? (InterfacePreview.enabled ? "预览同学" : "已登录"))
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(session.studentId ?? (InterfacePreview.enabled ? "示例账号" : "—"))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) { showLogoutAlert = true } label: {
                    Text("退出登录")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.red)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .navigationTitle("账号").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .foregroundStyle(.primary).tint(nil).accessibilityLabel("关闭账号")
                }
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
