import SwiftUI

struct StudioQuestProfileUpgradeView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var coordinator: IdentityUpgradeCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var displayName = ""
    @State private var handle = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now
    @State private var instrument = "Piano"
    @State private var privacy = ProfilePrivacy.default
    @State private var isSaving = false

    private let instruments = ["Piano", "Violin", "Cello", "Guitar", "Voice", "Woodwind", "Brass", "Percussion", "Production", "Other"]

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestWordmark(compact: true)
                StudioQuestPageTitle(title: "Set up your musician profile", subtitle: "This keeps your practice private by default.")

                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 14) {
                        labeledField("Display name", text: $displayName, prompt: "How musicians will know you")
                        labeledField("Handle", text: $handle, prompt: "lowercase.handle")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        DatePicker("Date of birth", selection: $dateOfBirth, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        Picker("Instrument", selection: $instrument) {
                            ForEach(instruments, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Privacy")
                            .font(StudioQuestTokens.Typography.sectionTitle)
                        Text("Your account starts private. You can change these controls later in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Toggle("Keep profile private", isOn: $privacy.isPrivate)
                        Toggle("Show instrument on profile", isOn: $privacy.showInstrument)
                        Toggle("Show bio on profile", isOn: $privacy.showBio)
                        Toggle("Share practice totals", isOn: $privacy.showPracticeTotals)
                    }
                }

                if case .failed(let message) = coordinator.state {
                    StudioQuestInlineStatus(text: message, kind: .error)
                } else if let status = coordinator.statusMessage {
                    StudioQuestInlineStatus(text: status, kind: .information)
                }

                Button(isSaving ? "Saving…" : "Finish profile") {
                    isSaving = true
                    Task {
                        let complete = await coordinator.complete(
                            displayName: displayName,
                            handle: handle,
                            dateOfBirth: dateOfBirth,
                            instrument: instrument,
                            privacy: privacy
                        )
                        isSaving = false
                        if complete { dismiss() }
                    }
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
                .disabled(isSaving)
                .accessibilityHint("Completes your private musician profile")
            }
            .padding(.top, StudioQuestTokens.Spacing.xl)
        }
        .task(id: firebase.currentUserID) {
            await coordinator.configure(
                uid: firebase.currentUserID,
                isAnonymous: firebase.isAnonymousUser
            )
            if let profile = coordinator.profile {
                displayName = profile.displayName
                handle = profile.handle
                dateOfBirth = profile.dateOfBirth
                instrument = profile.instrument
                privacy = profile.privacy
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(12)
                .background(StudioQuestTokens.ColorRole.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct StudioQuestOfflineProfileUpgradeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator

    var body: some View {
        NavigationStack {
            StudioQuestScrollPage {
                VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                    StudioQuestPageTitle(title: "Practice is still yours", subtitle: "Finish your profile when you reconnect.")
                    StudioQuestInlineStatus(
                        text: "Community, duels, cloud inventory, and notifications are temporarily unavailable while your profile upgrade is offline.",
                        kind: .warning
                    )
                    Button("Start practice") {
                        coordinator.quickStart()
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    Button("Practice setup") {
                        router.navigate(to: .practiceSetup(preset: nil), in: .today)
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                }
                .padding(.top, StudioQuestTokens.Spacing.xl)
            }
            .navigationDestination(for: AppRoute.self) { StudioQuestRouteView(route: $0) }
        }
    }
}
