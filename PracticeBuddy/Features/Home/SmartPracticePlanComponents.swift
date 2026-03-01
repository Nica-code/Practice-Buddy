import SwiftUI

struct SmartPracticePlanBlockRow: View {
    let title: String
    let minutes: Int
    let details: String
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(L10n.f("%@ min", "\(minutes)"))
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
            Text(LocalizedStringKey(details))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(10)
        .background(palette.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(L10n.f("%@ minutes. %@", "\(minutes)", details)))
    }
}
