import SwiftUI

struct PracticeLabPlaceholderView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type

    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(type.sectionTitle)
                .foregroundStyle(theme.textPrimary)

            Text(summary)
                .font(type.body)
                .foregroundStyle(theme.textSecondary)

            Text("Coming soon")
                .font(type.footnote)
                .foregroundStyle(theme.accent)
                .padding(.top, 4)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

