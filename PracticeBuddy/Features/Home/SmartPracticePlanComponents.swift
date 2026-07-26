import SwiftUI

struct SmartPracticePlanBlockRow: View {
    let title: String
    let minutes: Int
    let details: String
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(L10n.f("%@ min", "\(minutes)"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(LocalizedStringKey(details))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(StudioQuestTokens.ColorRole.surface(colorScheme).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(L10n.f("%@ minutes. %@", "\(minutes)", details)))
    }
}
