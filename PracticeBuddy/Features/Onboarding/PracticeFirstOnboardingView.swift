import SwiftUI

struct PracticeFirstOnboardingView: View {
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onComplete: () -> Void

    @State private var step = 0
    @State private var instrument = "Piano"
    @State private var goalMinutes = 30
    @State private var avatarID = "avatar_note"
    @State private var wantsVerifiedPractice = true

    private let instruments = ["Piano", "Strings", "Voice", "Guitar", "Woodwinds", "Brass", "Percussion"]

    var body: some View {
        ZStack {
            StudioQuestBackground()
            VStack(spacing: 0) {
                HStack {
                    StudioQuestWordmark()
                    Spacer()
                    if step > 0 {
                        Button("Back") {
                            advance(to: step - 1)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(StudioQuestTokens.Spacing.lg)

                TabView(selection: $step) {
                    welcome.tag(0)
                    instrumentAndGoal.tag(1)
                    verificationChoice.tag(2)
                    avatarStarter.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : StudioQuestTokens.Motion.gentle, value: step)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [StudioQuestTokens.ColorRole.cobalt, StudioQuestTokens.ColorRole.violet],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .accessibilityHidden(true)
            Text("Your practice,\nwith purpose.")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .tracking(-1.5)
            Text("Start focused practice immediately. Build a musical path as your real sessions add up.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Set up my practice") {
                advance(to: 1)
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            Text("No permanent account required.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(StudioQuestTokens.Spacing.lg)
    }

    private var instrumentAndGoal: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What do you practice?")
                    .font(.largeTitle.bold())
                Text("This sets a useful starting point. You can change it anytime.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible()),
                        count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
                    ),
                    spacing: 12
                ) {
                    ForEach(instruments, id: \.self) { value in
                        Button {
                            instrument = value
                        } label: {
                            Text(value)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(instrument == value ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    instrument == value
                                        ? StudioQuestTokens.ColorRole.cobalt
                                        : StudioQuestTokens.ColorRole.surface(colorScheme),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily goal")
                        .font(.headline)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible()),
                            count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
                        ),
                        spacing: 10
                    ) {
                        ForEach([15, 30, 45, 60], id: \.self, content: goalButton)
                    }
                    Text("Minutes per day. This is guidance, never a guilt streak.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Continue") {
                    advance(to: 2)
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
            }
            .padding(StudioQuestTokens.Spacing.lg)
        }
    }

    private var verificationChoice: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("How should we track your practice?")
                .font(.largeTitle.bold())
            Text("You can change this anytime in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                verificationOption(
                    title: "Verified practice",
                    description: "Distraction blocking confirms you're actually focused, so your time is a trustworthy record.",
                    systemImage: "checkmark.shield.fill",
                    tint: StudioQuestTokens.ColorRole.mint,
                    isSelected: wantsVerifiedPractice
                ) {
                    wantsVerifiedPractice = true
                }

                verificationOption(
                    title: "Just track time",
                    description: "No distraction blocking. Simple, unverified practice timing.",
                    systemImage: "clock",
                    tint: .secondary,
                    isSelected: !wantsVerifiedPractice
                ) {
                    wantsVerifiedPractice = false
                }
            }

            if wantsVerifiedPractice {
                Text("You'll be asked to allow Screen Time access the first time you start a verified session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Continue") {
                coordinator.isVerified = wantsVerifiedPractice
                advance(to: 3)
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
        }
        .padding(StudioQuestTokens.Spacing.lg)
    }

    private func verificationOption(
        title: String,
        description: String,
        systemImage: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? StudioQuestTokens.ColorRole.cobalt : .secondary)
            }
            .padding(StudioQuestTokens.Spacing.md)
            .background(
                StudioQuestTokens.ColorRole.surface(colorScheme),
                in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous)
                    .stroke(isSelected ? StudioQuestTokens.ColorRole.cobalt : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var avatarStarter: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Choose a studio identity")
                .font(.largeTitle.bold())
            Text("Optional—and separate from the profile photo your friends see.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible()),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
                ),
                spacing: 12
            ) {
                ForEach(PBAvatarStyle.freeStyles.prefix(4)) { avatar in
                    Button {
                        avatarID = avatar.id
                    } label: {
                        PBAvatarView(avatarID: avatar.id, displayName: avatar.title, size: 58)
                            .padding(5)
                            .overlay {
                                Circle()
                                    .stroke(
                                        avatarID == avatar.id ? StudioQuestTokens.ColorRole.cobalt : .clear,
                                        lineWidth: 3
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(avatar.title)
                    .accessibilityAddTraits(avatarID == avatar.id ? .isSelected : [])
                }
            }

            Spacer()

            Button("Start my first practice") {
                UserDefaults.standard.set(goalMinutes, forKey: "pb.settings.dailyGoalMinutes")
                UserDefaults.standard.set(avatarID, forKey: "pb.profile.avatarID")
                UserDefaults.standard.set(instrument, forKey: "practiquest.profile.instrument")
                UserDefaults.standard.set(true, forKey: "practiquest.v2.onboarding.completed")
                PracticeAnalytics.record(.onboardingCompleted)
                onComplete()
                coordinator.start(
                    task: "Get comfortable and make one clear sound",
                    piece: instrument,
                    durationMinutes: goalMinutes,
                    verified: wantsVerifiedPractice
                )
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())

            Button("Skip avatar for now") {
                UserDefaults.standard.set(goalMinutes, forKey: "pb.settings.dailyGoalMinutes")
                UserDefaults.standard.set(instrument, forKey: "practiquest.profile.instrument")
                UserDefaults.standard.set(true, forKey: "practiquest.v2.onboarding.completed")
                PracticeAnalytics.record(.onboardingCompleted)
                onComplete()
                coordinator.start(
                    task: "Get comfortable and make one clear sound",
                    piece: instrument,
                    durationMinutes: goalMinutes,
                    verified: wantsVerifiedPractice
                )
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            .frame(maxWidth: .infinity)
        }
        .padding(StudioQuestTokens.Spacing.lg)
    }

    private func advance(to newStep: Int) {
        if reduceMotion {
            step = newStep
        } else {
            withAnimation(StudioQuestTokens.Motion.quick) {
                step = newStep
            }
        }
    }

    private func goalButton(minutes: Int) -> some View {
        Button("\(minutes)") { goalMinutes = minutes }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(goalMinutes == minutes ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                goalMinutes == minutes
                    ? StudioQuestTokens.ColorRole.cobalt
                    : StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .accessibilityLabel("\(minutes) minute daily goal")
            .accessibilityAddTraits(goalMinutes == minutes ? .isSelected : [])
    }
}
