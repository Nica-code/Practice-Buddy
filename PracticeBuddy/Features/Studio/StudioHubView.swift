import SwiftUI

struct StudioHubView: View {
    private enum SocialJumpTarget: String {
        case pendingRequests
        case leaderboard
    }

    private enum StudioSection: String, CaseIterable, Identifiable {
        case friends
        case chat

        var id: String { rawValue }
    }

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var socialChatManager: StudioChatViewModel
    @AppStorage("pb.studio.hub.section") private var sectionRawValue: String = StudioSection.friends.rawValue
    @AppStorage("pb.social.jumpTarget") private var socialJumpTargetRaw: String = ""
    @State private var animateHeader = false
    @State private var showShopSheet = false

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
            socialShortcutRow
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !animateHeader {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    animateHeader = true
                }
            }
        }
        .sheet(isPresented: $showShopSheet) {
            NavigationStack {
                ShopView()
            }
        }
    }

    private var socialShortcutRow: some View {
        PBShortcutBar(items: socialShortcutItems, palette: palette)
            .padding(.horizontal, PBLayout.padSM)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .offset(y: animateHeader ? 0 : 10)
            .opacity(animateHeader ? 1 : 0)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Social")
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .foregroundStyle(palette.textPrimary)

            Text(
                StudioSection(rawValue: sectionRawValue) == .chat
                ? "Studio and friend conversations in one place."
                : "Manage friends and studio connections."
            )
            .font(type.footnote)
            .foregroundStyle(palette.textSecondary)

            Picker("Social", selection: sectionBinding) {
                ForEach(StudioSection.allCases) { section in
                    Text(sectionTitle(for: section)).tag(section)
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

    private var socialShortcutItems: [PBShortcutItem] {
        [
            PBShortcutItem(
                id: "social_requests",
                title: "Requests",
                systemImage: "person.badge.plus",
                action: {
                    sectionRawValue = StudioSection.friends.rawValue
                    socialJumpTargetRaw = "\(SocialJumpTarget.pendingRequests.rawValue):\(Date().timeIntervalSince1970)"
                }
            ),
            PBShortcutItem(
                id: "social_leaderboard",
                title: "Leaderboard",
                systemImage: "list.number",
                action: {
                    sectionRawValue = StudioSection.friends.rawValue
                    socialJumpTargetRaw = "\(SocialJumpTarget.leaderboard.rawValue):\(Date().timeIntervalSince1970)"
                }
            ),
            PBShortcutItem(
                id: "social_store",
                title: "Shop",
                systemImage: "bag.fill",
                action: { showShopSheet = true }
            )
        ]
    }

    private func sectionTitle(for section: StudioSection) -> String {
        switch section {
        case .friends:
            return "Friends"
        case .chat:
            if socialChatManager.unreadCount > 0 {
                return "Chat (\(socialChatManager.unreadCount))"
            }
            return "Chat"
        }
    }
}
