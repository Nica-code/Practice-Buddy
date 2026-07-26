import SwiftUI

struct SocialMessageBubbleView: View {
    let message: SocialChatMessage
    let isCurrentUser: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 40) }
            HStack(alignment: .top, spacing: 8) {
                if !isCurrentUser {
                    PBAvatarView(avatarID: message.senderAvatarID, displayName: message.senderName, size: 30)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(message.senderName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isCurrentUser ? Color.white.opacity(0.86) : .secondary)
                        PBLevelBadgeView(level: message.senderLevel)
                    }

                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(isCurrentUser ? .white : .primary)

                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(isCurrentUser ? Color.white.opacity(0.72) : .secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous)
                    .fill(
                        isCurrentUser
                            ? StudioQuestTokens.ColorRole.cobalt
                            : StudioQuestTokens.ColorRole.surface(colorScheme)
                    )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(message.senderName) message"))
            .accessibilityValue(Text(message.text))
            if !isCurrentUser { Spacer(minLength: 40) }
        }
    }
}
