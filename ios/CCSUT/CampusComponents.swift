import SwiftUI

/// The dock's upper corners follow the rendered capsule control, including Dynamic Type.
struct CampusActionDock<Content: View>: View {
    @State private var controlHeight: CGFloat = 52
    var controlInset: CGFloat = 0
    private let content: Content
    init(controlInset: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.controlInset = controlInset
        self.content = content()
    }
    var body: some View {
        content
            .onPreferenceChange(CampusActionHeight.self) { if $0 > 0 { controlHeight = $0 } }
            .background {
                Color.clear
                    .glassEffect(.regular, in: UnevenRoundedRectangle(
                        topLeadingRadius: controlHeight / 2 + controlInset, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: controlHeight / 2 + controlInset))
                    .ignoresSafeArea(.container, edges: .bottom)
                    .allowsHitTesting(false)
            }
    }
}

private struct CampusActionHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    func campusActionControl() -> some View {
        buttonBorderShape(.capsule)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: CampusActionHeight.self, value: geometry.size.height)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

struct CampusSection<Content: View>: View {
    let title: String
    private let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
        }
    }
}

struct CampusInfoRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let value: String
    init(_ title: String, value: String) { self.title = title; self.value = value }
    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { label; detail.multilineTextAlignment(.leading) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    label; Spacer(minLength: 4); detail.multilineTextAlignment(.trailing)
                }
            }
        }
        .font(.subheadline).accessibilityElement(children: .combine)
    }
    private var label: some View { Text(title).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private var detail: some View { Text(CampusPrivacy.redact(value)).fixedSize(horizontal: false, vertical: true).privacySensitive() }
}

struct CampusStatusBadge: View {
    let text: String
    var pending = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(pending ? Color.orange : Color.accentColor).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(CampusPrivacy.redact(text)).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background((pending ? Color.orange : Color.accentColor).opacity(0.10), in: .capsule)
    }
}

struct CampusDateRange: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let start: String?
    let end: String?
    var chineseDates = false
    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) { point("开始", start); point("结束", end) }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    point("开始", start).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                    point("结束", end).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private func point(_ title: String, _ raw: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(CampusDisplayDate.date(raw, chinese: chineseDates)).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            let time = CampusDisplayDate.time(raw)
            if !time.isEmpty { Text(time).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

struct CampusServiceAction: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44).background(Color.accentColor.opacity(0.09), in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "plus").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 28)).accessibilityLabel(title)
    }
}
