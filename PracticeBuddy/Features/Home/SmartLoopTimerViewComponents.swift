import SwiftUI

struct SmartLoopTagChip: View {
    let tag: SmartLoopTimerView.LoopTag
    let isSelected: Bool
    let palette: PBTheme.Palette
    let type: PBTypography
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            Text(tag.title)
                .font(type.footnote)
                .foregroundStyle(isSelected ? palette.accent : palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background((isSelected ? palette.accent.opacity(0.18) : palette.surfaceAlt))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tag.title))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
    }
}
