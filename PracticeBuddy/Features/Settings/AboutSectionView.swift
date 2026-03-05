import SwiftUI
import UIKit

struct AboutSectionView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private let emailAddress = "contact@alexmalaimare.com"
    private let websiteURLString = "https://alexmalaimare.com"

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let version, let build {
            return "\(version) (\(build))"
        } else if let version {
            return version
        } else {
            return "—"
        }
    }

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    
    private func aboutSectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
        .listRowInsets(
            EdgeInsets(
                top: 4,
                leading: 0,
                bottom: 4,
                trailing: 0
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    var body: some View {
        Section("About") {
            aboutSectionCard {
                HStack {
                    Text("Version")
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(versionString)
                        .foregroundStyle(palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Contact Information & Feedback")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.vertical, 2)

                HStack(spacing: 10) {
                    pillButton(title: "Email") {
                        openEmail()
                    }

                    pillButton(title: "Website") {
                        openWebsite()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - UI

    private func pillButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(type.body)
                // Classic model: black in light, white in dark via .primary
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pbSurfaceCard(palette: palette, cornerRadius: 12)
    }

    // MARK: - Actions

    private func openEmail() {
        guard let url = URL(string: "mailto:\(emailAddress)") else { return }
        openURL(url)
    }

    private func openWebsite() {
        guard let url = URL(string: websiteURLString) else { return }
        openURL(url)
    }

    private func openURL(_ url: URL) {
        let app = UIApplication.shared
        guard app.canOpenURL(url) else {
            // On Simulator, mailto often cannot be handled. Not a production concern.
            return
        }
        app.open(url, options: [:], completionHandler: nil)
    }
}
