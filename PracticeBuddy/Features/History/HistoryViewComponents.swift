import SwiftUI

struct HistoryStatCardView: View {
    let title: String
    let value: String
    let subtitle: String
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            Text(LocalizedStringKey(value))
                .font(type.number)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(LocalizedStringKey(subtitle))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .pbSurfaceCard(palette: palette, cornerRadius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text("\(value). \(subtitle)"))
    }
}

struct HistoryEmptyStateRow: View {
    let title: String
    let subtitle: String
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(type.sectionTitle)
                .foregroundStyle(palette.textPrimary)
            Text(LocalizedStringKey(subtitle))
                .font(type.body)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
