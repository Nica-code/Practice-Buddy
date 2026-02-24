import SwiftUI

struct AssignmentLinkedPracticeView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var assignmentLinkManager: AssignmentLinkManager
    @EnvironmentObject private var purchaseManager: PurchaseManager

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        Form {
            Section("Linked Assignment") {
                if !purchaseManager.hasRole(.student) {
                    Text("Assignment-linked practice is available on student accounts.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else if let linked = assignmentLinkManager.linkedAssignment {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(linked.title)
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                        Text(linked.details)
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Text(L10n.f("Due: %@", linked.dueAt.formatted(date: .abbreviated, time: .omitted)))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }

                    Button("Unlink Assignment") {
                        assignmentLinkManager.linkAssignment(nil)
                    }
                    .buttonStyle(.bordered)
                    .font(type.button)
                } else {
                    Text("No linked assignment selected yet. Link one from Home -> Today’s Assignments.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .listRowBackground(palette.surface)

            Section("Start Linked Activity") {
                NavigationLink {
                    PBLazyView(SmartLoopTimerView())
                } label: {
                    Text("Smart Loop Timer")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                }

                NavigationLink {
                    PBLazyView(PlanExecuteReflectView())
                } label: {
                    Text("Plan → Execute → Reflect")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                }

                NavigationLink {
                    PBLazyView(PulseRhythmAccuracyView())
                } label: {
                    Text("Pulse + Rhythm Accuracy")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                }

                NavigationLink {
                    PBLazyView(RunThroughModeView())
                } label: {
                    Text("Run-through Mode")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                }

                NavigationLink {
                    PBLazyView(WarmUpGeneratorView())
                } label: {
                    Text("Warm-up Generator")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
