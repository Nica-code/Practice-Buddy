import SwiftUI

/// Soft pre-prompt shown before the system notification permission dialog.
///
/// iOS only ever surfaces the OS permission alert once. Priming first — explaining
/// the value and letting the user opt in on their own terms — meaningfully lifts
/// grant rates and preserves the one-shot OS prompt for users who are ready to say yes.
struct PBNotificationPrimerView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let perks: [(icon: String, text: String)] = [
        ("bolt.heart.fill", "Know the moment a friend challenges you to a duel"),
        ("message.fill", "Never miss a new message from a friend"),
        ("person.2.fill", "Get notified when someone sends you a friend request")
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                StudioQuestBackground()
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: StudioQuestTokens.Spacing.lg) {
                        Spacer(minLength: StudioQuestTokens.Spacing.sm)

                        ZStack {
                            Circle()
                                .fill(StudioQuestTokens.ColorRole.cobalt.opacity(0.12))
                                .frame(width: 92, height: 92)
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityHidden(true)

                        VStack(spacing: StudioQuestTokens.Spacing.xs) {
                            Text("Stay in the loop")
                                .font(StudioQuestTokens.Typography.heroTitle)
                                .multilineTextAlignment(.center)
                            Text("PractiQuest can let you know when a friend reaches out or a duel needs your attention.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)

                        StudioQuestSection {
                            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
                                ForEach(perks, id: \.icon) { perk in
                                    HStack(alignment: .center, spacing: StudioQuestTokens.Spacing.sm) {
                                        Image(systemName: perk.icon)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                                            .frame(width: 30, height: 30)
                                            .background(
                                                StudioQuestTokens.ColorRole.cobalt.opacity(0.10),
                                                in: Circle()
                                            )
                                        Text(LocalizedStringKey(perk.text))
                                            .font(.subheadline)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }

                        VStack(spacing: StudioQuestTokens.Spacing.sm) {
                            Button {
                                StudioQuestHaptics.tap()
                                onEnable()
                            } label: {
                                Text("Enable Notifications")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(StudioQuestPrimaryButtonStyle())
                            .accessibilityIdentifier("notifications.enable")

                            Button("Not Now", action: onSkip)
                                .buttonStyle(StudioQuestSecondaryButtonStyle())
                                .accessibilityIdentifier("notifications.skip")
                        }
                    }
                    .frame(
                        width: min(
                            StudioQuestTokens.Spacing.pageMaxWidth,
                            max(0, proxy.size.width - (StudioQuestTokens.Spacing.pageMargin(for: proxy.size.width) * 2))
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StudioQuestTokens.Spacing.lg)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
