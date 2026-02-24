import SwiftUI

struct StudioHubView: View {
    private enum StudioSection: String, CaseIterable, Identifiable {
        case friends
        case chat

        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .friends: return "Friends"
            case .chat: return "Chat"
            }
        }
    }

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.studio.hub.section") private var sectionRawValue: String = StudioSection.friends.rawValue

    private var sectionBinding: Binding<StudioSection> {
        Binding(
            get: { StudioSection(rawValue: sectionRawValue) ?? .friends },
            set: { sectionRawValue = $0.rawValue }
        )
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Social")
                    .font(type.sectionTitle)
                    .foregroundStyle(theme.textPrimary)
                Text(
                    StudioSection(rawValue: sectionRawValue) == .chat
                    ? "Studio conversations in one place."
                    : "Manage friends and studio connections."
                )
                .font(type.footnote)
                .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(chrome)

            Picker("Social", selection: sectionBinding) {
                ForEach(StudioSection.allCases) { section in
                    Text(LocalizedStringKey(section.titleKey)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(chrome)

            switch StudioSection(rawValue: sectionRawValue) ?? .friends {
            case .friends:
                FriendsView()
            case .chat:
                SocialView()
            }
        }
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
