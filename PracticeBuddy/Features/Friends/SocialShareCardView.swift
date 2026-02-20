import SwiftUI

struct SocialShareCardView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type

    let title: String
    let subtitle: String
    let valueText: String
    let streakText: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.surface)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(type.sectionTitle)
                    .foregroundStyle(theme.textPrimary)

                Text(subtitle)
                    .font(type.body)
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(valueText)
                            .font(type.fontChoice.numberFont(size: 42, weight: .bold))
                            .foregroundStyle(theme.accent)
                        Spacer()
                    }

                    if let streakText {
                        Text(streakText)
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                HStack {
                    Text("Tracked with PracticeBuddy")
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)

                    Spacer()

                    Image(systemName: "music.note")
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
