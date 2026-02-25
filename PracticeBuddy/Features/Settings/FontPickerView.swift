import SwiftUI

struct FontPickerView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(PBFontChoice.selectionKey) private var selectedFontID: String = PBFontChoice.systemDefault.id

    private var selected: PBFontChoice { PBFontChoice.byID(selectedFontID) }

    var body: some View {
        List {
            Section {
                previewCard
                    .listRowBackground(theme.background)
            }

            Section("Type Palettes") {
                ForEach(PBFontChoice.all) { choice in
                    fontRow(choice)
                        .listRowBackground(theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Typography")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewCard: some View {
        let previewChoice = selected
        let previewTitle = previewChoice.homeTitleFont(size: 28)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(type.sectionTitle)
                .foregroundStyle(theme.textPrimary)

            Text("Practice Buddy")
                .font(previewTitle)
                .foregroundStyle(theme.textPrimary)

            Text(L10n.f("Selected: %@", String(localized: String.LocalizationValue(previewChoice.name))))
                .font(type.footnote)
                .foregroundStyle(theme.textSecondary)

            Text("Each palette applies a full type system: title, body, and number styles.")
                .font(type.body)
                .foregroundStyle(theme.textSecondary)

            Text(previewChoice.resolvedRoleDebugText())
                .font(.caption2.monospaced())
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Section Header")
                    .font(previewChoice.headlineFont(weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Text("Journal reflection text with markdown-style notes.")
                    .font(previewChoice.bodyFont())
                    .foregroundStyle(theme.textSecondary)

                HStack {
                    Text("Timer")
                        .font(previewChoice.bodyFont())
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text("42:15")
                        .font(previewChoice.numberFont(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .monospacedDigit()
                }
            }
            .padding(12)
            .pbSurfaceCard(palette: theme.resolvedPalette(for: colorScheme), cornerRadius: 14)
        }
        .padding()
        .pbSurfaceCard(palette: theme.resolvedPalette(for: colorScheme), cornerRadius: 18)
    }

    private func fontRow(_ choice: PBFontChoice) -> some View {
        let isSelected = (choice.id == selectedFontID)

        return Button {
            selectedFontID = choice.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(choice.name))
                            .font(type.body)
                            .foregroundStyle(theme.textPrimary)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.accent)
                        }
                    }

                    Text(LocalizedStringKey(choice.subtitle))
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .opacity(0.85)
                }

                Spacer()

                Text("Aa")
                    .font(choice.homeTitleFont(size: 20))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(theme.surfaceAlt)
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
