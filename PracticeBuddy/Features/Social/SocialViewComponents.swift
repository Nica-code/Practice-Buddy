import SwiftUI

struct SocialMessageBubbleView: View {
    let message: SocialChatMessage
    let isCurrentUser: Bool
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 40) }
            HStack(alignment: .top, spacing: 8) {
                PBAvatarView(avatarID: message.senderAvatarID, displayName: message.senderName, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(message.senderName)
                            .font(type.footnote)
                            .foregroundStyle(isCurrentUser ? palette.textPrimary : palette.textSecondary)
                        PBLevelBadgeView(level: message.senderLevel)
                    }

                    Text(message.text)
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)

                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                    .fill(isCurrentUser ? palette.accent.opacity(0.22) : palette.surface)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(message.senderName) message"))
            .accessibilityValue(Text(message.text))
            if !isCurrentUser { Spacer(minLength: 40) }
        }
    }
}
