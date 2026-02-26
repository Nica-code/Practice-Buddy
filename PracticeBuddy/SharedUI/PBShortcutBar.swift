import SwiftUI

struct PBShortcutItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isDisabled: Bool = false
    let action: () -> Void
}

struct PBShortcutBar: View {
    let items: [PBShortcutItem]
    let palette: PBTheme.Palette
    @Environment(\.pbTypography) private var type

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(LocalizedStringKey(item.title))
                            .font(type.footnote)
                    }
                    .foregroundStyle(item.isDisabled ? palette.textSecondary.opacity(0.7) : palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(palette.surfaceAlt)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(item.isDisabled)
            }
        }
    }
}
