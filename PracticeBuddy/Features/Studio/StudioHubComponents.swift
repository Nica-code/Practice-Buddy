import SwiftUI

struct StudioHubHeaderCard<Content: View>: View {
    let palette: PBTheme.Palette
    let type: PBTypography
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .foregroundStyle(palette.textPrimary)

            Text(subtitle)
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            content()
        }
        .padding(PBLayout.padLG)
        .pbFlatCard(palette: palette)
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }
}
