import SwiftUI

struct ThemePickerView: View {
    @Environment(\.pbTheme) private var currentTheme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @EnvironmentObject private var themeManager: ThemeManager

    @State private var previewTheme: PBTheme? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                livePreviewCard(theme: themeManager.theme)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Themes")
                        .font(type.sectionTitle)
                        .foregroundStyle(currentTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    customColorSection

                    LazyVStack(spacing: 10) {
                        ForEach(PBTheme.all) { theme in
                            themeRow(theme)
                        }
                        themeRow(themeManager.customTheme)
                    }
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
        .background(currentTheme.background.ignoresSafeArea())
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $previewTheme) { theme in
            ThemePreviewSheet(
                themeModel: theme,
                isSelected: theme.id == themeManager.theme.id,
                onApply: {
                    themeManager.select(theme)
                    previewTheme = nil
                },
                onClose: { previewTheme = nil }
            )
            .pbTheme(theme)
        }
    }

    private var customColorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Accent")
                .font(type.body)
                .foregroundStyle(currentTheme.textPrimary)

            HStack(spacing: 10) {
                ColorPicker(
                    "Pick color",
                    selection: Binding(
                        get: { themeManager.customAccentColor },
                        set: { newColor in
                            themeManager.updateCustomAccent(newColor, applyImmediately: false)
                        }
                    ),
                    supportsOpacity: false
                )
                .font(type.footnote)

                Button(themeManager.isUsingCustomTheme ? "Applied" : "Use Custom") {
                    themeManager.updateCustomAccent(themeManager.customAccentColor, applyImmediately: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(themeManager.isUsingCustomTheme)
            }
        }
        .padding(12)
        .pbSurfaceCard(palette: currentTheme.resolvedPalette(for: colorScheme), cornerRadius: 14)
    }

    @ViewBuilder
    private func themeRow(_ theme: PBTheme) -> some View {
        let selected = theme.id == themeManager.theme.id

        Button {
            themeManager.select(theme)
        } label: {
            HStack(spacing: 12) {
                swatches(for: theme)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(theme.name))
                            .font(type.sectionTitle)
                            .foregroundStyle(currentTheme.textPrimary)

                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(currentTheme.accent)
                        }
                    }

                    Text("Tap to apply")
                        .font(type.footnote)
                        .foregroundStyle(currentTheme.textSecondary)
                        .opacity(0.85)
                }

                Spacer()

                Button {
                    previewTheme = theme
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(currentTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(currentTheme.surfaceAlt)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(currentTheme.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? currentTheme.accent.opacity(0.65) : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func swatches(for theme: PBTheme) -> some View {
        let palette = theme.resolvedPalette(for: colorScheme)

        return HStack(spacing: 6) {
            Circle().fill(palette.accent).frame(width: 12, height: 12)
            Circle().fill(palette.surface).frame(width: 12, height: 12)
            Circle().fill(palette.background).frame(width: 12, height: 12)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .pbSurfaceCard(palette: currentTheme.resolvedPalette(for: colorScheme), cornerRadius: 12)
        .accessibilityLabel(Text(LocalizedStringKey("\(theme.name) swatches")))
    }

    private func livePreviewCard(theme: PBTheme) -> some View {
        let palette = theme.resolvedPalette(for: colorScheme)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Live Preview")
                .font(type.sectionTitle)
                .foregroundStyle(palette.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Practice Buddy")
                    .font(type.sectionTitle)
                    .foregroundStyle(palette.textPrimary)

                Text("This is how the app will look with this theme.")
                    .font(type.body)
                    .foregroundStyle(palette.textSecondary)

                HStack {
                    Text("Today")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("42 min")
                        .font(type.number)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }
                .padding(12)
                .pbSurfaceCard(palette: palette, cornerRadius: 14)

                Button {} label: {
                    Text("Accent Button")
                        .font(type.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(palette.accent.opacity(0.18))
                        .foregroundStyle(palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
        }
        .padding()
        .pbSurfaceCard(palette: palette, cornerRadius: 18)
    }
}

private struct ThemePreviewSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pbTypography) private var type
    @Environment(\.pbTheme) private var theme

    let themeModel: PBTheme
    let isSelected: Bool
    let onApply: () -> Void
    let onClose: () -> Void

    var body: some View {
        let palette = themeModel.resolvedPalette(for: colorScheme)

        return NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey(themeModel.name))
                            .font(type.sectionTitle)
                            .foregroundStyle(palette.textPrimary)

                        Text("Preview")
                            .font(type.body)
                            .foregroundStyle(palette.textSecondary)

                        HStack(spacing: 10) {
                            pill("Accent", color: palette.accent, palette: palette)
                            pill("Surface", color: palette.surface, palette: palette)
                            pill("Background", color: palette.background, palette: palette)
                        }

                        Divider().opacity(0.2)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Example")
                                .font(type.sectionTitle)
                                .foregroundStyle(palette.textPrimary)

                            Text("Week of Jan 26 – Feb 1")
                                .font(type.body)
                                .foregroundStyle(palette.textSecondary)

                            HStack {
                                Text("Practice")
                                    .font(type.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text("120 min")
                                    .font(type.number)
                                    .foregroundStyle(palette.accent)
                                    .monospacedDigit()
                            }
                            .padding(12)
                            .pbSurfaceCard(palette: palette, cornerRadius: 14)
                        }
                    }
                    .padding()
                    .pbSurfaceCard(palette: palette, cornerRadius: 18)

                    Button {
                        onApply()
                    } label: {
                        Text(isSelected ? "Selected" : "Apply Theme")
                            .font(type.button)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(palette.accent.opacity(0.18))
                            .foregroundStyle(palette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelected)
                }
                .padding()
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Theme Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    private func pill(_ label: String, color: Color, palette: PBTheme.Palette) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(palette.surfaceAlt)
        )
    }
}
