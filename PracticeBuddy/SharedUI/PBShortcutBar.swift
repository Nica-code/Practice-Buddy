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
                Button(action: {
                    if !item.isDisabled { PBHaptics.tap() }
                    item.action()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(LocalizedStringKey(item.title))
                            .font(type.fontChoice.headlineFont(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .allowsTightening(true)
                            .layoutPriority(1)
                    }
                    .foregroundStyle(item.isDisabled ? palette.textSecondary.opacity(0.72) : palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                palette.surface.opacity(item.isDisabled ? 0.36 : 0.54),
                                                palette.surfaceAlt.opacity(item.isDisabled ? 0.28 : 0.44),
                                                palette.accent.opacity(item.isDisabled ? 0.06 : 0.16)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.34),
                                        palette.accent.opacity(item.isDisabled ? 0.10 : 0.30)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(item.isDisabled)
            }
        }
        .animation(PBLayout.quickAnimation, value: items.map(\.isDisabled))
    }
}
