import SwiftUI

struct LaunchPrepView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        List {
            Section("Pre-launch reset") {
                step("1. Deploy rules first", command: "firebase deploy --only firestore:rules")
                step("2. Run launch reset script", command: "./scripts/firestore_launch_reset.sh")
                step("3. Delete Firebase Auth test users", command: "Firebase Console → Authentication → Users")
            }

            Section("Whitelist all-access users") {
                step("Grant all_access from whitelist", command: "cd functions && node scripts/grant_all_access_from_whitelist.js --service-account /absolute/path/to/service-account.json --project practicebuddytracker --file ../scripts/all_access_whitelist.json")
                step("Revoke all_access from whitelist", command: "cd functions && node scripts/revoke_all_access_from_whitelist.js --service-account /absolute/path/to/service-account.json --project practicebuddytracker --file ../scripts/all_access_whitelist.json")
            }

            Section("Master account checks") {
                Text("Master account allowlist is configured in Info.plist keys PBMasterEmails and PBMasterUIDs.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                Text("Privileged fields are now server-authoritative in Firestore rules. Use Admin SDK/scripts for entitlement updates.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .navigationTitle("Launch Prep")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func step(_ title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Text(command)
                .font(type.footnote.monospaced())
                .foregroundStyle(palette.textSecondary)
                .textSelection(.enabled)
        }
    }
}
