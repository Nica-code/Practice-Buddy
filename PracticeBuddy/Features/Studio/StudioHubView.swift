import SwiftUI

struct StudioHubView: View {
    private enum StudioSection: String, CaseIterable, Identifiable {
        case buddies
        case chat

        var id: String { rawValue }
        var title: String {
            switch self {
            case .buddies: return "Buddies"
            case .chat: return "Chat"
            }
        }
    }

    @Environment(\.pbTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.studio.hub.section") private var sectionRawValue: String = StudioSection.buddies.rawValue

    private var sectionBinding: Binding<StudioSection> {
        Binding(
            get: { StudioSection(rawValue: sectionRawValue) ?? .buddies },
            set: { sectionRawValue = $0.rawValue }
        )
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Studio", selection: sectionBinding) {
                ForEach(StudioSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(chrome)

            switch StudioSection(rawValue: sectionRawValue) ?? .buddies {
            case .buddies:
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

