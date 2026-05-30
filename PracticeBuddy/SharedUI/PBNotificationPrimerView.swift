import SwiftUI

/// Soft pre-prompt shown before the system notification permission dialog.
///
/// iOS only ever surfaces the OS permission alert once. Priming first — explaining
/// the value and letting the user opt in on their own terms — meaningfully lifts
/// grant rates and preserves the one-shot OS prompt for users who are ready to say yes.
struct PBNotificationPrimerView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    private let perks: [(icon: String, text: String)] = [
        ("bolt.heart.fill", "Know the moment a friend challenges you to a duel"),
        ("message.fill", "Never miss a new message from your practice buddies"),
        ("person.2.fill", "Get notified when someone sends you a friend request")
    ]

    var body: some View {
        VStack(spacing: PBLayout.padLG) {
            Spacer(minLength: PBLayout.padMD)

            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: PBLayout.padXS) {
                Text("Stay in the loop")
                    .font(type.sheetTitle)
                    .foregroundStyle(palette.textPrimary)
                Text("Turn on notifications so PractiQuest can reach you when it matters.")
                    .font(type.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, PBLayout.padMD)

            VStack(alignment: .leading, spacing: PBLayout.padSM) {
                ForEach(perks, id: \.icon) { perk in
                    HStack(alignment: .center, spacing: PBLayout.padSM) {
                        Image(systemName: perk.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 28)
                        Text(LocalizedStringKey(perk.text))
                            .font(type.footnote)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(PBLayout.padMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pbSurfaceCard(palette: palette, cornerRadius: PBLayout.radiusControl)
            .padding(.horizontal, PBLayout.padMD)

            Spacer(minLength: 0)

            VStack(spacing: PBLayout.padSM) {
                Button {
                    PBHaptics.tap()
                    onEnable()
                } label: {
                    Text("Enable Notifications")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))

                Button {
                    onSkip()
                } label: {
                    Text("Not Now")
                        .font(type.button)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PBLayout.padXS)
                }
            }
            .padding(.horizontal, PBLayout.padMD)
            .padding(.bottom, PBLayout.padMD)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PBBackdropView(palette: palette).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
