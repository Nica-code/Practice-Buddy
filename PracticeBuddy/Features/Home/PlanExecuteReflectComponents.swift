import SwiftUI

struct PlanExecuteReflectChipView: View {
    let title: String
    let isSelected: Bool
    let palette: PBTheme.Palette
    let type: PBTypography
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(LocalizedStringKey(title))
                .font(type.footnote)
                .foregroundStyle(isSelected ? palette.accent : palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? palette.accent.opacity(0.18) : palette.surfaceAlt)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
    }
}
