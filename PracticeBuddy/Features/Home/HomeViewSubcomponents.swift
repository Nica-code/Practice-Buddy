import SwiftUI

struct CompactTimeStatView: View {
    let title: String
    let seconds: Int
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            Text(DurationFormatter.string(from: seconds))
                .font(type.number)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .pbSurfaceCard(palette: palette, cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(DurationFormatter.string(from: seconds)))
    }
}

struct PracticeLabCardView: View {
    let title: String
    let subtitle: String
    let icon: String
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accent)

            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .multilineTextAlignment(.leading)

            Text(LocalizedStringKey(subtitle))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(3)
                .minimumScaleFactor(0.86)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .frame(minWidth: 220, idealWidth: 236, maxWidth: 252, minHeight: 140, maxHeight: 140, alignment: .topLeading)
        .padding(12)
        .pbSurfaceCard(palette: palette, cornerRadius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(LocalizedStringKey(subtitle)))
    }
}

struct PracticeToolCardView: View {
    let title: String
    let subtitle: String
    let icon: String
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.accent)

            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)

            Text(LocalizedStringKey(subtitle))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 0)
        }
        .frame(minWidth: 220, idealWidth: 236, maxWidth: 252, minHeight: 102, maxHeight: 102, alignment: .topLeading)
        .padding(12)
        .pbSurfaceCard(palette: palette, cornerRadius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(LocalizedStringKey(subtitle)))
    }
}

struct StepperMinutesRow: View {
    let title: String
    @Binding var value: Int
    let palette: PBTheme.Palette
    let type: PBTypography

    var body: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Button {
                value = max(0, value - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.textSecondary)
            .accessibilityLabel(Text("Decrease \(title) minutes"))
            .accessibilityHint(Text("Reduces by one minute"))

            Text(L10n.f("%@ min", "\(value)"))
                .font(type.number)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .center)

            Button {
                value = min(90, value + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
            .accessibilityLabel(Text("Increase \(title) minutes"))
            .accessibilityHint(Text("Adds one minute"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .pbSurfaceCard(palette: palette, cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(L10n.f("%@ minutes", "\(value)")))
    }
}
