import SwiftUI

struct AppIconPickerView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @State private var iconManager = AppIconManager()

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        List {
            Section {
                if !iconManager.supportsAlternateIcons {
                    Text("Alternate app icons aren’t supported on this device.")
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(PBAppIcon.allCases) { icon in
                        Button {
                            iconManager.apply(icon)
                        } label: {
                            HStack(spacing: 12) {
                                iconThumbnail(icon)

                                Text(LocalizedStringKey(icon.displayName))
                                    .font(type.body)
                                    .foregroundStyle(theme.textPrimary)

                                Spacer()

                                if iconManager.selectedIcon == icon {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Choose App Icon")
            } footer: {
                Text("Your selection applies immediately. You can switch back to Default anytime.")
                    .font(type.footnote)
            }
            .listRowBackground(theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle("App Icon")
        .onAppear {
            iconManager.syncFromSystem()
        }
        .alert(item: Binding(
            get: { iconManager.lastError },
            set: { iconManager.lastError = $0 }
        )) { err in
            Alert(
                title: Text(LocalizedStringKey(err.title)),
                message: Text(LocalizedStringKey(err.message)),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func iconThumbnail(_ icon: PBAppIcon) -> some View {
        let border = theme.textSecondary.opacity(0.25)

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surface)
                .frame(width: 44, height: 44)

            Image(icon.previewImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .accessibilityLabel(Text(LocalizedStringKey("\(icon.displayName) icon preview")))
    }
}
