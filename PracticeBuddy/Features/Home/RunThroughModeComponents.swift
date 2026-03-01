import SwiftUI

struct LabeledValueRow: View {
    let title: String
    let value: String
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value)
                .font(type.number)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(value))
    }
}
