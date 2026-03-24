import SwiftUI

struct FirstRunTutorialStep: Identifiable {
    let id: String
    let tabIndex: Int
    let title: String
    let message: String
}

struct FirstRunTutorialView: View {
    let steps: [FirstRunTutorialStep]
    let onSelectTab: (Int) -> Void
    let onComplete: (_ skipped: Bool, _ dontShowAgain: Bool) -> Void

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @State private var stepIndex: Int = 0
    @State private var dontShowAgain: Bool = true

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    private static let fallbackStep = FirstRunTutorialStep(
        id: "fallback",
        tabIndex: 0,
        title: "Quick Tour",
        message: "Explore the main tabs to get familiar with PractiQuest."
    )

    private var currentStep: FirstRunTutorialStep {
        guard !steps.isEmpty else { return Self.fallbackStep }
        return steps[min(max(stepIndex, 0), max(steps.count - 1, 0))]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Quick Tour")
                    .font(type.sectionTitle)
                    .foregroundStyle(palette.textPrimary)

                Text(LocalizedStringKey(currentStep.title))
                    .font(type.number)
                    .foregroundStyle(palette.textPrimary)

                Text(LocalizedStringKey(currentStep.message))
                    .font(type.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                        Capsule()
                            .fill(index == stepIndex ? palette.accent : palette.surfaceAlt)
                            .frame(width: index == stepIndex ? 24 : 8, height: 8)
                    }
                }

                Toggle("Don't show again", isOn: $dontShowAgain)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .toggleStyle(.switch)

                HStack {
                    Button("Skip") {
                        onComplete(true, dontShowAgain)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(stepIndex == steps.count - 1 ? "Done" : "Next") {
                        guard !steps.isEmpty else {
                            onComplete(false, dontShowAgain)
                            return
                        }
                        if stepIndex < steps.count - 1 {
                            stepIndex += 1
                            onSelectTab(currentStep.tabIndex)
                        } else {
                            onComplete(false, dontShowAgain)
                        }
                    }
                    .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
                }
            }
            .padding(PBLayout.padLG)
            .pbModernCard(palette: palette)
            .padding(.horizontal, PBLayout.padLG)
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            onSelectTab(currentStep.tabIndex)
        }
    }
}
