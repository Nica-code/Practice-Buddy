import SwiftUI

struct HistoryRetentionPickerView: View {
    @Binding var selection: Int

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    private struct Option: Identifiable {
        let value: Int
        let title: String
        var id: Int { value }
    }

    private let options: [Option] = [
        Option(value: 0, title: "Unlimited"),
        Option(value: 30, title: "30"),
        Option(value: 90, title: "90"),
        Option(value: 180, title: "180"),
        Option(value: 365, title: "365"),
        Option(value: 1000, title: "1000")
    ]

    var body: some View {
        List {
            Section {
                ForEach(options) { opt in
                    Button {
                        selection = opt.value
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(opt.title))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)

                            Spacer()

                            if selection == opt.value {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(palette.surface)
                }
            } footer: {
                Text(selection == 0
                     ? "Your practice history is kept indefinitely."
                     : "Older sessions are automatically deleted after you exceed \(selection) sessions.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
