import SwiftUI
import AuthenticationServices

struct GuestAccountBannerView<Content: View>: View {
    let palette: PBTheme.Palette
    let type: PBTypography
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Guest account")
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Text("Sign in with Apple to keep your account across devices.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            content()
        }
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Guest account"))
        .accessibilityValue(Text("Sign in with Apple to keep your account across devices"))
    }
}
