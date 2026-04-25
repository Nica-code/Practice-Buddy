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
    @StateObject private var notifications = PBNotificationStore.shared
    @State private var showNotificationsSheet = false

    var body: some View {
        HStack(spacing: 9) {
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
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(item.isDisabled ? 0.14 : 0.28),
                                                palette.surface.opacity(item.isDisabled ? 0.34 : 0.54),
                                                palette.surfaceAlt.opacity(item.isDisabled ? 0.24 : 0.42),
                                                palette.accent.opacity(item.isDisabled ? 0.06 : 0.20)
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
                                        .white.opacity(item.isDisabled ? 0.28 : 0.58),
                                        palette.accent.opacity(item.isDisabled ? 0.10 : 0.40),
                                        .white.opacity(0.16)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .clipShape(Capsule())
                    .shadow(
                        color: item.isDisabled ? .clear : palette.accent.opacity(0.16),
                        radius: 9,
                        x: 0,
                        y: 5
                    )
                }
                .buttonStyle(.plain)
                .disabled(item.isDisabled)
            }

            Button {
                PBHaptics.tap()
                showNotificationsSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 44, height: 38)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.28),
                                                    palette.surface.opacity(0.54),
                                                    palette.surfaceAlt.opacity(0.44),
                                                    palette.accent.opacity(0.24)
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
                                            .white.opacity(0.58),
                                            palette.accent.opacity(0.42),
                                            .white.opacity(0.16)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .clipShape(Capsule())
                        .shadow(color: palette.accent.opacity(0.18), radius: 10, x: 0, y: 5)

                    if notifications.unreadCount > 0 {
                        Text("\(min(notifications.unreadCount, 99))")
                            .font(type.fontChoice.headlineFont(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(palette.accent))
                            .offset(x: 6, y: -5)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .animation(PBLayout.quickAnimation, value: items.map(\.isDisabled))
        .animation(PBLayout.quickAnimation, value: notifications.unreadCount)
        .fullScreenCover(isPresented: $showNotificationsSheet) {
            PBNotificationsInboxView()
        }
    }
}
