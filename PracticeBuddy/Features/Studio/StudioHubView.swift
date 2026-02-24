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
    @State private var animateHeader = false

    private var sectionBinding: Binding<StudioSection> {
        Binding(
            get: { StudioSection(rawValue: sectionRawValue) ?? .friends },
            set: { sectionRawValue = $0.rawValue }
        )
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            headerCard

            switch StudioSection(rawValue: sectionRawValue) ?? .friends {
            case .friends:
                FriendsView()
            case .chat:
                SocialView()
            }
        }
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !animateHeader {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    animateHeader = true
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Social")
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .foregroundStyle(palette.textPrimary)

            Text(
                StudioSection(rawValue: sectionRawValue) == .chat
                ? "Studio conversations in one place."
                : "Manage friends and studio connections."
            )
            .font(type.footnote)
            .foregroundStyle(palette.textSecondary)

            Picker("Social", selection: sectionBinding) {
                ForEach(StudioSection.allCases) { section in
                    Text(LocalizedStringKey(section.titleKey)).tag(section)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(PBLayout.padLG)
        .pbModernCard(palette: palette)
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }
}
