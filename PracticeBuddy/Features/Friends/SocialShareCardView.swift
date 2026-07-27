import SwiftUI

struct SocialShareCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let valueText: String
    let streakText: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(StudioQuestTokens.ColorRole.surface(colorScheme))

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(StudioQuestTokens.Typography.sectionTitle)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(valueText)
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        Spacer()
                    }

                    if let streakText {
                        Text(streakText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Tracked with PractiQuest")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
