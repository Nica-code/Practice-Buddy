import SwiftUI

/// Reusable empty-state block: icon + title + message, with an optional CTA.
///
/// Use for the first-run moments a list has no content (no buddies, no chats),
/// where a polished prompt reads far better than a bare line of gray text.
struct PBEmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        VStack(spacing: PBLayout.padSM) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.12))
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(type.cardTitle)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button {
                    PBHaptics.tap()
                    action()
                } label: {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
                .padding(.top, PBLayout.padXS)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PBLayout.padLG)
        .padding(.horizontal, PBLayout.padMD)
    }
}
