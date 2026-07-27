import SwiftUI

struct PracticeStudioView: View {
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var toolsPresented = false
    @State private var setupPresented = false

    var body: some View {
        ZStack {
            StudioQuestTokens.ColorRole.background(colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                studioHero
                    .frame(maxHeight: .infinity)

                controlsSurface
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(coordinator.elapsedSeconds > 0)
        .sheet(isPresented: $toolsPresented) {
            NavigationStack {
                PracticeToolsDrawer()
                    .navigationDestination(for: AppRoute.self) { route in
                        StudioQuestRouteView(route: route)
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $setupPresented) {
            NavigationStack {
                PracticeSetupView(
                    preset: PracticePreset(
                        piece: coordinator.currentPiece,
                        task: coordinator.currentTask,
                        durationMinutes: coordinator.plannedMinutes,
                        verified: coordinator.isVerified,
                        launchContext: coordinator.launchContext,
                        tasks: coordinator.tasks
                    )
                )
            }
        }
        .sheet(isPresented: $coordinator.reflectionPresented) {
            PracticeReflectionView()
                .interactiveDismissDisabled()
        }
        .onDisappear {
            if coordinator.studioPresented, !coordinator.reflectionPresented {
                coordinator.studioPresented = false
            }
        }
        .overlay {
            if coordinator.checkInManager.isAwaitingResponse {
                PracticeStudioCheckInOverlay()
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var studioHero: some View {
        ZStack {
            Image("StudioQuestPracticeLight")
                .resizable()
                .scaledToFill()
                .overlay {
                    if colorScheme == .dark {
                        Color(red: 0.015, green: 0.035, blue: 0.065)
                            .opacity(0.62)
                            .blendMode(.multiply)
                    }
                }
                .clipped()

            LinearGradient(
                colors: [
                    StudioQuestTokens.ColorRole.background(colorScheme).opacity(0.55),
                    .clear,
                    StudioQuestTokens.ColorRole.background(colorScheme).opacity(colorScheme == .dark ? 0.50 : 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                HStack {
                    Button {
                        coordinator.pause()
                        coordinator.studioPresented = false
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Minimize Practice Studio")

                    Spacer()

                    StudioQuestVerifiedLabel(isVerified: coordinator.verificationMechanismActive)

                    Menu {
                        Button("Practice setup", systemImage: "slider.horizontal.3") {
                            coordinator.pause()
                            setupPresented = true
                        }
                        Button("Discard session", systemImage: "trash", role: .destructive) {
                            coordinator.discard()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Session options")
                }
                .foregroundStyle(.primary)

                VStack(spacing: 3) {
                    Text(coordinator.currentPiece)
                        .font(.headline)
                    Text(coordinator.currentTask)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(DurationFormatter.string(from: coordinator.elapsedSeconds))
                    .font(StudioQuestTokens.Typography.timer)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .linear(duration: 0.15), value: coordinator.elapsedSeconds)
                    .accessibilityLabel("Elapsed practice time")
                    .accessibilityValue(DurationFormatter.string(from: coordinator.elapsedSeconds))

                Spacer(minLength: 150)
            }
            .padding(.horizontal, StudioQuestTokens.Spacing.md)
            .padding(.top, 4)
        }
    }

    private var controlsSurface: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Session progress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(coordinator.progress * 100))%")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                }
                ProgressView(value: coordinator.progress)
                    .tint(StudioQuestTokens.ColorRole.cobalt)
                HStack {
                    Text(coordinator.currentTask)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if !coordinator.tasks.isEmpty {
                        Text("\(coordinator.activeTaskIndex + 1) / \(coordinator.tasks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Label(
                        DurationFormatter.string(from: coordinator.verifiedSeconds),
                        systemImage: "checkmark.shield.fill"
                    )
                    .foregroundStyle(StudioQuestTokens.ColorRole.mint)

                    Label(
                        DurationFormatter.string(from: coordinator.unverifiedSeconds),
                        systemImage: "shield.slash"
                    )
                    .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))

                if let status = coordinator.checkInStatusMessage, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(alignment: .center) {
                toolButton(title: "Tools", systemImage: "slider.horizontal.3") {
                    toolsPresented = true
                }

                Spacer()

                Button {
                    coordinator.isRunning ? coordinator.pause() : coordinator.resume()
                } label: {
                    Image(systemName: coordinator.isRunning ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(StudioQuestTokens.ColorRole.cobalt, in: Circle())
                        .shadow(color: StudioQuestTokens.ColorRole.cobalt.opacity(0.24), radius: 12, y: 6)
                }
                .accessibilityLabel(coordinator.isRunning ? "Pause practice" : "Resume practice")

                Spacer()

                toolButton(title: "Finish", systemImage: "stop.fill") {
                    coordinator.requestFinish()
                }
                .disabled(coordinator.elapsedSeconds == 0)
            }

            Capsule()
                .fill(StudioQuestTokens.ColorRole.separator(colorScheme))
                .frame(width: 38, height: 4)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, StudioQuestTokens.Spacing.lg)
        .padding(.top, StudioQuestTokens.Spacing.lg)
        .padding(.bottom, 8)
        .background(StudioQuestTokens.ColorRole.background(colorScheme))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func toolButton(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .frame(width: 46, height: 46)
                    .background(
                        StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                        in: Circle()
                    )
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

struct PracticeSetupView: View {
    let preset: PracticePreset?

    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var piece = ""
    @State private var tasks: [PracticePlanTask] = []
    @State private var verified = true
    @State private var isConfiguringVerification = false

    init(preset: PracticePreset? = nil) {
        self.preset = preset
        _piece = State(initialValue: preset?.piece ?? "")
        let initialTasks: [PracticePlanTask]
        if let preset, !preset.tasks.isEmpty {
            initialTasks = preset.tasks
        } else if let preset {
            initialTasks = [
                PracticePlanTask(
                    title: preset.task.isEmpty ? "Focused practice" : preset.task,
                    minutes: max(1, preset.durationMinutes)
                )
            ]
        } else {
            initialTasks = [
                PracticePlanTask(title: "Warm-up", minutes: 10),
                PracticePlanTask(title: "Focused work", minutes: 15),
                PracticePlanTask(title: "Run-through", minutes: 10)
            ]
        }
        _tasks = State(initialValue: initialTasks)
        _verified = State(initialValue: preset?.verified ?? true)
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(
                    title: "Set up practice",
                    subtitle: "A clear plan makes starting easier."
                )

                labeledField("Piece or exercise", text: $piece, prompt: "e.g. Chopin Nocturne")

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Session plan")
                            .font(StudioQuestTokens.Typography.sectionTitle)
                        Spacer()
                        Text("\(totalMinutes) min")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ForEach($tasks) { $task in
                        StudioQuestRowSurface {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    TextField("Task", text: $task.title)
                                        .font(.headline)
                                    if tasks.count > 1 {
                                        Button(role: .destructive) {
                                            tasks.removeAll { $0.id == task.id }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove \(task.title)")
                                    }
                                }
                                Stepper(value: $task.minutes, in: 1...90, step: 5) {
                                    Text("\(task.minutes) minutes")
                                        .font(.subheadline.monospacedDigit())
                                }
                            }
                        }
                    }

                    Button {
                        tasks.append(
                            PracticePlanTask(
                                title: "Task \(tasks.count + 1)",
                                minutes: 10
                            )
                        )
                    } label: {
                        Label("Add task", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                }

                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $verified) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Verified practice")
                                    .font(.headline)
                                Text("Counts only time protected by distraction blocking and check-ins.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(StudioQuestTokens.ColorRole.mint)

                        if verified {
                            Divider()
                            Toggle("Block distracting apps", isOn: $coordinator.distractionBlockEnabled)
                                .tint(StudioQuestTokens.ColorRole.cobalt)
                            Toggle("Practice check-ins", isOn: $coordinator.checkInsEnabled)
                                .tint(StudioQuestTokens.ColorRole.cobalt)

                            if coordinator.checkInsEnabled {
                                Picker("Check-in interval", selection: $coordinator.checkInInterval) {
                                    ForEach(PracticeCheckInInterval.allCases) { interval in
                                        Text(interval.title).tag(interval)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            if !coordinator.appShield.isVerificationConfigured {
                                Button {
                                    isConfiguringVerification = true
                                    coordinator.isVerified = verified
                                    Task {
                                        await coordinator.configureVerificationIfNeeded()
                                        isConfiguringVerification = false
                                    }
                                } label: {
                                    Label(
                                        isConfiguringVerification ? "Setting up…" : "Set up distraction protection",
                                        systemImage: "shield.lefthalf.filled"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(StudioQuestSecondaryButtonStyle())
                                .disabled(isConfiguringVerification)
                            } else {
                                StudioQuestInlineStatus(
                                    text: "Distraction protection is ready.",
                                    kind: .success
                                )
                            }
                        }
                    }
                }

                Button {
                    coordinator.startPlan(
                        piece: piece,
                        tasks: tasks,
                        verified: verified,
                        launchContext: preset?.launchContext
                    )
                    dismiss()
                } label: {
                    Label("Start practice", systemImage: "play.fill")
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
                .disabled(validTasks.isEmpty)

                NavigationLink(value: AppRoute.practiceLibrary) {
                    Label("Browse the Practice Library", systemImage: "books.vertical")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.md)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var validTasks: [PracticePlanTask] {
        tasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var totalMinutes: Int {
        validTasks.reduce(0) { $0 + max(1, $1.minutes) }
    }

    private func labeledField(_ title: LocalizedStringKey, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(14)
                .background(
                    StudioQuestTokens.ColorRole.surface(colorScheme),
                    in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control)
                        .stroke(StudioQuestTokens.ColorRole.separator(colorScheme), lineWidth: 1)
                }
        }
    }
}

struct PracticeToolsDrawer: View {
    var body: some View {
        PracticeLibraryView(contextualOnly: true)
            .navigationTitle("Practice tools")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct PracticeLibraryView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case favorites = "Favorites"
        case recent = "Recent"

        var id: String { rawValue }
    }

    var contextualOnly = false
    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var unavailableMessage: String?
    @AppStorage("practiquest.library.favorites") private var favoritesRaw = ""
    @AppStorage("practiquest.library.recents") private var recentsRaw = ""

    private let items: [PracticeLibraryItem] = [
        .init(id: "smart-coach", title: "Smart Coach", subtitle: "Turn recent practice into a focused plan.", systemImage: "wand.and.stars", category: .planning, tags: ["plan", "adaptive", "history"], route: .smartCoach, supportsActiveSession: false, toolID: .smartCoach, capabilities: [.producesResult]),
        .init(id: "metronome", title: "Metronome", subtitle: "Keep a steady pulse without leaving the session.", systemImage: "metronome", category: .timing, tags: ["tempo", "pulse", "bpm"], route: .metronome, supportsActiveSession: true, toolID: .metronome, capabilities: [.playback, .supportsActiveSession]),
        .init(id: "tuner", title: "Tuner", subtitle: "Check pitch or play a reference tone.", systemImage: "tuningfork", category: .listening, tags: ["pitch", "reference", "intonation"], route: .tuner, supportsActiveSession: true, toolID: .tuner, capabilities: [.microphone, .playback, .supportsActiveSession]),
        .init(id: "smart-loop", title: "Smart Loop", subtitle: "Repeat hard passages with intention.", systemImage: "repeat", category: .timing, tags: ["repeat", "tempo"], route: .smartLoop, supportsActiveSession: true, toolID: .smartLoop, capabilities: [.timed, .playback, .producesResult, .supportsActiveSession, .supportsRecovery]),
        .init(
            id: "warm-up",
            title: "Warm-up Generator",
            subtitle: "Build a focused warm-up in seconds.",
            systemImage: "sparkles",
            category: .planning,
            tags: ["warmup", "routine"],
            route: .warmUp,
            supportsActiveSession: true,
            toolID: .warmUp,
            capabilities: [.timed, .producesResult, .supportsActiveSession, .supportsRecovery]
        ),
        .init(id: "per", title: "Plan · Execute · Reflect", subtitle: "Turn an intention into a useful session.", systemImage: "checklist", category: .planning, tags: ["plan", "reflect"], route: .planExecuteReflect, supportsActiveSession: true, toolID: .planExecuteReflect, capabilities: [.timed, .producesResult, .supportsActiveSession, .supportsRecovery]),
        .init(id: "rhythm", title: "Rhythm Accuracy", subtitle: "Measure pulse and timing accuracy.", systemImage: "waveform.path", category: .listening, tags: ["rhythm", "accuracy"], route: .rhythm, supportsActiveSession: true, toolID: .rhythm, capabilities: [.timed, .microphone, .producesResult, .supportsActiveSession, .supportsRecovery]),
        .init(id: "intonation", title: "Intonation", subtitle: "Practice pitch with visual feedback.", systemImage: "tuningfork", category: .listening, tags: ["pitch", "scales"], route: .intonation, supportsActiveSession: true, toolID: .intonation, capabilities: [.timed, .microphone, .playback, .producesResult, .supportsActiveSession, .supportsRecovery]),
        .init(id: "run-through", title: "Run-through", subtitle: "Perform without stopping, then review.", systemImage: "record.circle", category: .performance, tags: ["performance", "record"], route: .runThrough, supportsActiveSession: true, toolID: .runThrough, capabilities: [.timed, .microphone, .recording, .producesResult, .supportsActiveSession, .supportsRecovery])
    ]

    private var filteredItems: [PracticeLibraryItem] {
        items.filter { item in
            let matchesScope: Bool = switch scope {
            case .all: true
            case .favorites: isFavorite(item.id)
            case .recent: recentDates[item.id] != nil
            }
            return matchesScope
            && (query.isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || item.subtitle.localizedCaseInsensitiveContains(query)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(query) })
        }
        .sorted { lhs, rhs in
            if lhs.id == "smart-coach" { return true }
            if rhs.id == "smart-coach" { return false }
            let lhsRecent = recentDates[lhs.id] ?? .distantPast
            let rhsRecent = recentDates[rhs.id] ?? .distantPast
            if lhsRecent != rhsRecent { return lhsRecent > rhsRecent }
            if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
            return lhs.title < rhs.title
        }
    }

    private var recentDates: [String: Date] {
        Dictionary(
            uniqueKeysWithValues: recentsRaw.split(separator: ";").compactMap { entry in
                let parts = entry.split(separator: "=", maxSplits: 1)
                guard parts.count == 2,
                      let interval = TimeInterval(parts[1]) else { return nil }
                return (String(parts[0]), Date(timeIntervalSince1970: interval))
            }
        )
    }

    var body: some View {
        StudioQuestScrollPage(showsIndicators: true) {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestToolHero(
                    title: contextualOnly ? "Practice tools" : "Practice Library",
                    subtitle: contextualOnly
                        ? "Choose a tool to use without leaving this session."
                        : "Focused utilities for planning, listening, timing, and performance.",
                    systemImage: "books.vertical.fill"
                )

                StudioQuestFlowLayout {
                    ForEach(Scope.allCases) { option in
                        StudioQuestChoiceChip(
                            title: LocalizedStringKey(option.rawValue),
                            isSelected: scope == option
                        ) {
                            scope = option
                        }
                        .accessibilityIdentifier("library.scope.\(option.rawValue.lowercased())")
                    }
                }

                if filteredItems.isEmpty {
                    StudioQuestEmptyState(
                        title: scope == .favorites ? "No favorite tools yet" : "No tools found",
                        message: scope == .favorites
                            ? "Use the star on a tool to keep it close."
                            : "Try another search or show all tools.",
                        systemImage: scope == .favorites ? "star" : "magnifyingglass",
                        actionTitle: "Show all tools"
                    ) {
                        query = ""
                        scope = .all
                    }
                } else {
                    LazyVStack(spacing: StudioQuestTokens.Spacing.sm) {
                        ForEach(filteredItems) { item in
                            libraryRow(item)
                        }
                    }
                }

                if let unavailableMessage {
                    StudioQuestInlineStatus(text: unavailableMessage, kind: .warning)
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.md)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search tools")
    }

    private func libraryRow(_ item: PracticeLibraryItem) -> some View {
        let available = !contextualOnly || item.supportsActiveSession
        return HStack(spacing: 0) {
            Group {
                if available {
                    NavigationLink(value: item.route) {
                        libraryLabel(item, available: true)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            markRecent(item.id)
                            PracticeAnalytics.record(.toolOpened(item.id))
                        }
                    )
                } else {
                    Button {
                        explainUnavailable(item)
                    } label: {
                        libraryLabel(item, available: false)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.tool.\(item.id)")
            .accessibilityHint(
                available
                    ? "Opens \(item.title)"
                    : "Explains why this tool is unavailable"
            )

            Button {
                toggleFavorite(item.id)
            } label: {
                Image(systemName: isFavorite(item.id) ? "star.fill" : "star")
                    .font(.headline)
                    .foregroundStyle(
                        isFavorite(item.id)
                            ? StudioQuestTokens.ColorRole.gold
                            : Color.secondary
                    )
                    .frame(width: 54, height: 76)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isFavorite(item.id)
                    ? "Remove \(item.title) from favorites"
                    : "Add \(item.title) to favorites"
            )
        }
        .studioQuestSurface()
        .opacity(available ? 1 : 0.72)
    }

    private func libraryLabel(
        _ item: PracticeLibraryItem,
        available: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.headline)
                .foregroundStyle(
                    available
                        ? StudioQuestTokens.ColorRole.cobalt
                        : Color.secondary
                )
                .frame(width: 44, height: 44)
                .background(
                    (available
                        ? StudioQuestTokens.ColorRole.cobalt
                        : Color.secondary).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(StudioQuestTokens.Typography.cardTitle)
                    if item.id == "smart-coach" {
                        Text("Coach")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(StudioQuestTokens.ColorRole.violet)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                StudioQuestTokens.ColorRole.violet.opacity(0.10),
                                in: Capsule()
                            )
                    }
                }
                Text(
                    available
                        ? item.subtitle
                        : "Available outside the active session"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(item.category.rawValue)
                    if item.supportsActiveSession {
                        Label("Session-ready", systemImage: "link")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: available ? "chevron.right" : "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }

    private func isFavorite(_ id: String) -> Bool {
        Set(favoritesRaw.split(separator: ",").map(String.init)).contains(id)
    }

    private func explainUnavailable(_ item: PracticeLibraryItem) {
        unavailableMessage = "\(item.title) starts its own practice structure. Finish the current session, then open it from the full Practice Library."
    }

    private func toggleFavorite(_ id: String) {
        var values = Set(favoritesRaw.split(separator: ",").map(String.init))
        if values.contains(id) {
            values.remove(id)
        } else {
            values.insert(id)
        }
        favoritesRaw = values.sorted().joined(separator: ",")
    }

    private func markRecent(_ id: String) {
        var values = recentDates
        values[id] = .now
        recentsRaw = values
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { "\($0.key)=\($0.value.timeIntervalSince1970)" }
            .joined(separator: ";")
    }
}

private struct PracticeStudioCheckInOverlay: View {
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedFocus = ""

    private let focusOptions = [
        "Intonation",
        "Rhythm",
        "Tone",
        "Technique",
        "Expression",
        "Run-through"
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(StudioQuestTokens.ColorRole.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice check-in")
                            .font(StudioQuestTokens.Typography.sectionTitle)
                        Text("\(coordinator.checkInManager.secondsUntilDeadline)s to confirm")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Are you still practicing? Add an optional focus so the check-in is useful in your history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94))], spacing: 8) {
                    ForEach(focusOptions, id: \.self) { focus in
                        Button(focus) {
                            selectedFocus = focus
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedFocus == focus ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedFocus == focus
                                ? StudioQuestTokens.ColorRole.cobalt
                                : StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                            in: Capsule()
                        )
                    }
                }

                Button("Still practicing") {
                    coordinator.respondToCheckIn(focusTag: selectedFocus)
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(
                StudioQuestTokens.ColorRole.surface(colorScheme),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }
}

struct StudioQuestMetronomeToolView: View {
    var body: some View {
        StudioQuestMetronomeToolContent()
    }
}

private struct StudioQuestMetronomeToolContent: View {
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.tools.metronome.bpm") private var bpm = 80
    @AppStorage("pb.tools.metronome.beatsPerBar") private var beatsPerBar = 4
    @AppStorage("pb.tools.metronome.subdivision") private var subdivisionRaw = MetronomeEngine.Subdivision.none.rawValue
    @AppStorage("pb.tools.metronome.soundStyle") private var soundRaw = MetronomeEngine.SoundStyle.click.rawValue
    @State private var statusMessage: String?
    @State private var statusKind: StudioQuestInlineStatus.Kind = .information
    @State private var replaceConfirmationPresented = false

    private var engine: MetronomeEngine { coordinator.metronome }
    private var isContextual: Bool {
        coordinator.toolLaunchContext?.parentSessionID != nil
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: 24) {
                StudioQuestPageTitle(title: "Metronome", subtitle: "A steady pulse, inside your session.")

                StudioQuestSection {
                    VStack(spacing: 18) {
                        Text("\(bpm)")
                            .font(.system(size: 64, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                        Text("BPM")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Slider(
                            value: Binding(
                                get: { Double(bpm) },
                                set: { bpm = Int($0.rounded()) }
                            ),
                            in: 40...220,
                            step: 1
                        )
                        .tint(StudioQuestTokens.ColorRole.cobalt)

                        HStack {
                            Button {
                                bpm = max(40, bpm - 1)
                            } label: {
                                Label("Slower", systemImage: "minus")
                            }
                            .buttonStyle(StudioQuestSecondaryButtonStyle())

                            Button {
                                bpm = min(220, bpm + 1)
                            } label: {
                                Label("Faster", systemImage: "plus")
                            }
                            .buttonStyle(StudioQuestSecondaryButtonStyle())
                        }
                    }
                }

                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Beats per bar", selection: $beatsPerBar) {
                            ForEach([2, 3, 4, 6], id: \.self) { beats in
                                Text("\(beats)/4").tag(beats)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Subdivision", selection: $subdivisionRaw) {
                            ForEach(MetronomeEngine.Subdivision.allCases) { subdivision in
                                Text(subdivision.title).tag(subdivision.rawValue)
                            }
                        }

                        Picker("Sound", selection: $soundRaw) {
                            ForEach(MetronomeEngine.SoundStyle.allCases) { sound in
                                Text(sound.title).tag(sound.rawValue)
                            }
                        }
                    }
                }

                Button {
                    if engine.isRunning {
                        stopMetronome()
                    } else {
                        requestStart()
                    }
                } label: {
                    Label(engine.isRunning ? "Stop metronome" : "Start metronome", systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())

                if coordinator.activeToolID == .metronome,
                   !isContextual,
                   coordinator.elapsedSeconds > 0 {
                    Button("Finish practice and reflect") {
                        stopMetronome()
                        coordinator.studioPresented = true
                        coordinator.requestFinish()
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                }

                if let statusMessage {
                    StudioQuestInlineStatus(text: statusMessage, kind: statusKind)
                }
            }
            .padding(.top, 20)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bpm) { _, value in
            engine.setBPM(value)
            if engine.isRunning {
                engine.applyUpdatedConfiguration(
                    beatsPerBar: beatsPerBar,
                    subdivision: MetronomeEngine.Subdivision(rawValue: subdivisionRaw) ?? .none,
                    soundStyle: MetronomeEngine.SoundStyle(rawValue: soundRaw) ?? .click
                )
            }
        }
        .onChange(of: beatsPerBar) { _, _ in applyConfiguration() }
        .onChange(of: subdivisionRaw) { _, _ in applyConfiguration() }
        .onChange(of: soundRaw) { _, _ in applyConfiguration() }
        .confirmationDialog(
            "Replace \(coordinator.audioSession.owner?.displayName ?? "the current audio tool")?",
            isPresented: $replaceConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Replace and start") {
                Task { await startMetronome(replacingAudio: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only one audio utility can run at a time.")
        }
        .onDisappear {
            engine.stop()
            coordinator.audioSession.release(.metronome)
            guard coordinator.activeToolID == .metronome else { return }
            if isContextual {
                coordinator.detachTool()
            } else {
                coordinator.pauseToolActivity()
                coordinator.pause()
            }
        }
    }

    private func applyConfiguration() {
        engine.applyUpdatedConfiguration(
            beatsPerBar: beatsPerBar,
            subdivision: MetronomeEngine.Subdivision(rawValue: subdivisionRaw) ?? .none,
            soundStyle: MetronomeEngine.SoundStyle(rawValue: soundRaw) ?? .click
        )
    }

    private func requestStart() {
        if let activeTool = coordinator.activeToolID, activeTool != .metronome {
            statusMessage = "Finish or close \(activeTool.title) before starting the metronome."
            statusKind = .warning
            return
        }
        if let owner = coordinator.audioSession.owner, owner != .metronome {
            replaceConfirmationPresented = true
            return
        }
        Task { await startMetronome(replacingAudio: false) }
    }

    private func startMetronome(replacingAudio: Bool) async {
        if let owner = coordinator.audioSession.owner, owner != .metronome {
            guard replacingAudio, replaceAudioOwner(owner) else { return }
        }
        do {
            try await coordinator.audioSession.claim(
                .metronome,
                requirements: .playback
            )
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription
                ?? "The metronome could not start."
            statusKind = .error
            return
        }

        if coordinator.activeToolID == nil {
            if coordinator.hasActivePractice {
                coordinator.attachTool(.metronome)
                if !coordinator.isRunning { coordinator.resume() }
            } else {
                coordinator.beginFocusedTool(
                    .metronome,
                    title: "Metronome practice",
                    durationMinutes: 10,
                    source: .library
                )
            }
        } else if !coordinator.isRunning {
            coordinator.resume()
        }
        coordinator.startToolActivity()
        engine.setBPM(bpm)
        engine.start(
            beatsPerBar: beatsPerBar,
            subdivision: MetronomeEngine.Subdivision(rawValue: subdivisionRaw) ?? .none,
            soundStyle: MetronomeEngine.SoundStyle(rawValue: soundRaw) ?? .click
        )
        statusMessage = "Metronome running."
        statusKind = .success
    }

    private func stopMetronome() {
        engine.stop()
        coordinator.audioSession.release(.metronome)
        guard coordinator.activeToolID == .metronome else { return }
        coordinator.pauseToolActivity()
        if !isContextual {
            coordinator.pause()
        }
        statusMessage = "Metronome stopped."
        statusKind = .information
    }

    private func replaceAudioOwner(_ owner: PracticeAudioOwner) -> Bool {
        switch owner {
        case .tuner:
            coordinator.tuner.stopListening()
            coordinator.tuner.stopReferenceTone()
        case .smartLoop, .metronome:
            coordinator.metronome.stop()
        default:
            statusMessage = "\(owner.displayName) cannot be replaced safely. Close it first."
            statusKind = .warning
            return false
        }
        coordinator.audioSession.release(owner)
        return true
    }
}

struct StudioQuestTunerToolView: View {
    var body: some View {
        StudioQuestTunerToolContent()
    }
}

private struct StudioQuestTunerToolContent: View {
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @AppStorage("pb.tools.tuner.referenceHz") private var referenceHz = 440
    @State private var statusMessage: String?
    @State private var statusKind: StudioQuestInlineStatus.Kind = .information
    @State private var replaceConfirmationPresented = false
    @State private var pendingAudioAction: PendingAudioAction?

    private enum PendingAudioAction {
        case listening
        case referenceTone
    }

    private var engine: TunerEngine { coordinator.tuner }
    private var isContextual: Bool {
        coordinator.toolLaunchContext?.parentSessionID != nil
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: 24) {
                StudioQuestPageTitle(title: "Tuner", subtitle: "Pitch feedback without leaving practice.")

                StudioQuestSection {
                    VStack(spacing: 18) {
                        Text(engine.detectedNoteName)
                            .font(.system(size: 64, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                        Text(centsLabel)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        TunerNeedleGauge(
                            cents: engine.detectedFrequency == nil ? nil : engine.detectedCents,
                            accent: StudioQuestTokens.ColorRole.cobalt
                        )
                        .frame(height: 92)
                    }
                }

                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 14) {
                        Stepper(value: $referenceHz, in: 430...450) {
                            LabeledContent("Reference tone", value: "A \(referenceHz) Hz")
                        }

                        Button {
                            if engine.isReferenceTonePlaying {
                                engine.stopReferenceTone()
                                releaseAudioIfIdle()
                            } else {
                                requestAudio(for: .referenceTone)
                            }
                        } label: {
                            Label(
                                engine.isReferenceTonePlaying ? "Stop reference tone" : "Play reference tone",
                                systemImage: engine.isReferenceTonePlaying ? "speaker.slash.fill" : "speaker.wave.2.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StudioQuestSecondaryButtonStyle())
                    }
                }

                if let status = engine.statusMessage, !status.isEmpty {
                    StudioQuestInlineStatus(text: status)
                }

                Button {
                    if engine.isListening {
                        engine.stopListening()
                        releaseAudioIfIdle()
                    } else {
                        requestAudio(for: .listening)
                    }
                } label: {
                    Label(engine.isListening ? "Stop listening" : "Start tuner", systemImage: engine.isListening ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())

                if coordinator.activeToolID == .tuner,
                   !isContextual,
                   coordinator.elapsedSeconds > 0 {
                    Button("Finish practice and reflect") {
                        stopTuner()
                        coordinator.studioPresented = true
                        coordinator.requestFinish()
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                }

                if let statusMessage {
                    StudioQuestInlineStatus(text: statusMessage, kind: statusKind)
                }
            }
            .padding(.top, 20)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: referenceHz) { _, value in
            if engine.isReferenceTonePlaying {
                engine.startReferenceTone(frequency: Double(value))
            }
        }
        .confirmationDialog(
            "Replace \(coordinator.audioSession.owner?.displayName ?? "the current audio tool")?",
            isPresented: $replaceConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Replace and continue") {
                if let pendingAudioAction {
                    Task { await startAudio(pendingAudioAction, replacingAudio: true) }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAudioAction = nil
            }
        } message: {
            Text("Only one microphone or playback utility can run at a time.")
        }
        .onDisappear {
            stopTuner()
            guard coordinator.activeToolID == .tuner else { return }
            if isContextual {
                coordinator.detachTool()
            } else {
                coordinator.pauseToolActivity()
                coordinator.pause()
            }
        }
    }

    private var centsLabel: String {
        guard engine.detectedFrequency != nil else { return "Play a note to begin" }
        let cents = Int(engine.detectedCents.rounded())
        if abs(cents) <= 1 { return "In tune" }
        return cents < 0 ? "\(abs(cents)) cents flat" : "\(cents) cents sharp"
    }

    private func requestAudio(for action: PendingAudioAction) {
        if let activeTool = coordinator.activeToolID, activeTool != .tuner {
            statusMessage = "Finish or close \(activeTool.title) before starting the tuner."
            statusKind = .warning
            return
        }
        pendingAudioAction = action
        if let owner = coordinator.audioSession.owner, owner != .tuner {
            replaceConfirmationPresented = true
            return
        }
        Task { await startAudio(action, replacingAudio: false) }
    }

    private func startAudio(
        _ action: PendingAudioAction,
        replacingAudio: Bool
    ) async {
        if let owner = coordinator.audioSession.owner, owner != .tuner {
            guard replacingAudio, replaceAudioOwner(owner) else { return }
        }

        var requirements: PracticeAudioRequirement = []
        if action == .listening || engine.isListening {
            requirements.insert(.microphone)
        }
        if action == .referenceTone || engine.isReferenceTonePlaying {
            requirements.insert(.playback)
        }

        do {
            try await coordinator.audioSession.claim(
                .tuner,
                requirements: requirements
            )
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription
                ?? "The tuner could not start."
            statusKind = .error
            pendingAudioAction = nil
            return
        }

        switch action {
        case .listening:
            engine.startListening()
            if engine.isListening {
                activateToolRuntime()
            }
            statusMessage = engine.isListening
                ? "Listening for pitch."
                : (engine.statusMessage ?? "The tuner could not start listening.")
            statusKind = engine.isListening ? .success : .error
        case .referenceTone:
            engine.startReferenceTone(frequency: Double(referenceHz))
            if engine.isReferenceTonePlaying {
                activateToolRuntime()
            }
            statusMessage = engine.isReferenceTonePlaying
                ? "Playing reference tone."
                : (engine.statusMessage ?? "The reference tone could not start.")
            statusKind = engine.isReferenceTonePlaying ? .success : .error
        }
        if !engine.isListening, !engine.isReferenceTonePlaying {
            coordinator.audioSession.release(.tuner)
        }
        pendingAudioAction = nil
    }

    private func activateToolRuntime() {
        if coordinator.activeToolID == nil {
            if coordinator.hasActivePractice {
                coordinator.attachTool(.tuner)
                if !coordinator.isRunning { coordinator.resume() }
            } else {
                coordinator.beginFocusedTool(
                    .tuner,
                    title: "Tuner practice",
                    durationMinutes: 10,
                    source: .library
                )
            }
        } else if !coordinator.isRunning {
            coordinator.resume()
        }
        coordinator.startToolActivity()
    }

    private func releaseAudioIfIdle() {
        guard !engine.isListening, !engine.isReferenceTonePlaying else { return }
        coordinator.audioSession.release(.tuner)
        guard coordinator.activeToolID == .tuner else { return }
        coordinator.pauseToolActivity()
        if !isContextual {
            coordinator.pause()
        }
    }

    private func stopTuner() {
        engine.stopListening()
        engine.stopReferenceTone()
        coordinator.audioSession.release(.tuner)
    }

    private func replaceAudioOwner(_ owner: PracticeAudioOwner) -> Bool {
        switch owner {
        case .metronome, .smartLoop:
            coordinator.metronome.stop()
        case .tuner:
            coordinator.tuner.stopListening()
            coordinator.tuner.stopReferenceTone()
        default:
            statusMessage = "\(owner.displayName) cannot be replaced safely. Close it first."
            statusKind = .warning
            return false
        }
        coordinator.audioSession.release(owner)
        return true
    }
}

struct PracticeReflectionView: View {
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var store: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var mood: PracticeNoteMood = .good
    @State private var title = ""
    @State private var focus = ""
    @State private var accomplishment = ""
    @State private var notes = ""
    @State private var journalPieces: [PracticeSessionJournalPiece] = []
    @State private var showsDetailedJournal = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var discardConfirmationPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                StudioQuestBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nice work.")
                                .font(StudioQuestTokens.Typography.pageTitle)
                            Text("\(DurationFormatter.string(from: coordinator.elapsedSeconds)) of intentional practice")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        StudioQuestSection {
                            HStack {
                                sessionMetric(
                                    "Verified",
                                    coordinator.verifiedSeconds,
                                    color: StudioQuestTokens.ColorRole.mint
                                )
                                sessionMetric(
                                    "Unverified",
                                    coordinator.unverifiedSeconds,
                                    color: .secondary
                                )
                                sessionMetric(
                                    "Check-ins",
                                    coordinator.checkInManager.checkInCount,
                                    suffix: "",
                                    color: StudioQuestTokens.ColorRole.cobalt
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("How did it feel?")
                                .font(.headline)
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    moodButtons
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    moodButtons
                                }
                            }
                        }

                        reflectionField("Session title", text: $title, prompt: coordinator.currentPiece)
                        reflectionField("Overall focus", text: $focus, prompt: coordinator.currentTask)
                        reflectionField("What clicked?", text: $accomplishment, prompt: "A phrase, sound, or breakthrough")
                        reflectionField("Note for next time", text: $notes, prompt: "Optional")

                        DisclosureGroup("Add detailed piece notes", isExpanded: $showsDetailedJournal) {
                            VStack(spacing: 14) {
                                ForEach(journalPieces) { piece in
                                    StudioQuestRowSurface {
                                        VStack(alignment: .leading, spacing: 10) {
                                            TextField("Piece or task", text: pieceBinding(piece.id, \.title))
                                                .font(.headline)
                                            TextField("Tempo", text: pieceBinding(piece.id, \.tempo))
                                            TextField("What went well", text: pieceBinding(piece.id, \.wentWell), axis: .vertical)
                                                .lineLimit(2...4)
                                            TextField("Needs work", text: pieceBinding(piece.id, \.needsWork), axis: .vertical)
                                                .lineLimit(2...4)
                                            TextField("Next action", text: pieceBinding(piece.id, \.nextAction), axis: .vertical)
                                                .lineLimit(2...4)
                                            if journalPieces.count > 1 {
                                                Button("Remove", role: .destructive) {
                                                    journalPieces.removeAll { $0.id == piece.id }
                                                }
                                                .font(.caption.weight(.semibold))
                                            }
                                        }
                                    }
                                }

                                Button {
                                    journalPieces.append(
                                        PracticeSessionJournalPiece(
                                            title: "",
                                            tempo: "",
                                            wentWell: "",
                                            needsWork: "",
                                            nextAction: ""
                                        )
                                    )
                                } label: {
                                    Label("Add piece", systemImage: "plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(StudioQuestSecondaryButtonStyle())
                            }
                            .padding(.top, 12)
                        }
                        .font(.headline)

                        if let saveError {
                            StudioQuestInlineStatus(text: saveError, kind: .error)
                        }

                        Button {
                            save()
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Save session")
                            }
                        }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                        .disabled(isSaving || coordinator.elapsedSeconds == 0)

                        Button("Discard session", role: .destructive) {
                            discardConfirmationPresented = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .padding(StudioQuestTokens.Spacing.lg)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: prepareDraft)
            .confirmationDialog(
                "Discard this practice session?",
                isPresented: $discardConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Discard session", role: .destructive) {
                    coordinator.discard()
                }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("The timer, verification record, and reflection will be lost.")
            }
        }
    }

    @ViewBuilder
    private var moodButtons: some View {
        ForEach(PracticeNoteMood.allCases) { value in
            Button(value.title) { mood = value }
                                        .buttonStyle(.plain)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(mood == value ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(
                                            mood == value
                                                ? StudioQuestTokens.ColorRole.cobalt
                                                : StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                                            in: Capsule()
                                        )
        }
    }

    private func reflectionField(_ title: LocalizedStringKey, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(2...5)
                .padding(14)
                .background(
                    StudioQuestTokens.ColorRole.surface(colorScheme),
                    in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control)
                )
        }
    }

    private func sessionMetric(
        _ title: LocalizedStringKey,
        _ value: Int,
        suffix: String = " time",
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suffix.isEmpty ? "\(value)" : DurationFormatter.string(from: value))
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prepareDraft() {
        guard title.isEmpty, focus.isEmpty, journalPieces.isEmpty else { return }
        title = coordinator.currentPiece == "Your instrument" ? "" : coordinator.currentPiece
        focus = coordinator.tasks.map(\.title).joined(separator: " · ")
        journalPieces = coordinator.tasks.map { task in
            PracticeSessionJournalPiece(
                title: task.title,
                tempo: "\(task.minutes) min",
                wentWell: "",
                needsWork: "",
                nextAction: ""
            )
        }
        if journalPieces.isEmpty {
            journalPieces = [
                PracticeSessionJournalPiece(
                    title: coordinator.currentTask,
                    tempo: "",
                    wentWell: "",
                    needsWork: "",
                    nextAction: ""
                )
            ]
        }
    }

    private func pieceBinding(
        _ id: UUID,
        _ keyPath: WritableKeyPath<PracticeSessionJournalPiece, String>
    ) -> Binding<String> {
        Binding(
            get: {
                journalPieces.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { value in
                guard let index = journalPieces.firstIndex(where: { $0.id == id }) else { return }
                journalPieces[index][keyPath: keyPath] = value
            }
        )
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil

        let snapshot = coordinator.snapshot
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAccomplishment = accomplishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPieces = journalPieces.compactMap { piece -> PracticeSessionJournalPiece? in
            let cleaned = PracticeSessionJournalPiece(
                id: piece.id,
                title: piece.title.trimmingCharacters(in: .whitespacesAndNewlines),
                tempo: piece.tempo.trimmingCharacters(in: .whitespacesAndNewlines),
                wentWell: piece.wentWell.trimmingCharacters(in: .whitespacesAndNewlines),
                needsWork: piece.needsWork.trimmingCharacters(in: .whitespacesAndNewlines),
                nextAction: piece.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let isEmpty = cleaned.title.isEmpty
                && cleaned.tempo.isEmpty
                && cleaned.wentWell.isEmpty
                && cleaned.needsWork.isEmpty
                && cleaned.nextAction.isEmpty
            return isEmpty ? nil : cleaned
        }
        let journal = PracticeSessionJournal(
            pieces: cleanedPieces,
            reflection: cleanedNotes
        )
        let structuredJSON: String = {
            guard let data = try? JSONEncoder().encode(journal),
                  let raw = String(data: data, encoding: .utf8) else { return "" }
            return raw
        }()

        var noteSections: [String] = []
        if !cleanedAccomplishment.isEmpty {
            noteSections.append("### What clicked\n\(cleanedAccomplishment)")
        }
        if !cleanedNotes.isEmpty {
            noteSections.append("### Next time\n\(cleanedNotes)")
        }
        for piece in cleanedPieces {
            var lines = ["## \(piece.title.isEmpty ? "Piece" : piece.title)"]
            if !piece.tempo.isEmpty { lines.append("Tempo: \(piece.tempo)") }
            if !piece.wentWell.isEmpty { lines.append("- Went well: \(piece.wentWell)") }
            if !piece.needsWork.isEmpty { lines.append("- Needs work: \(piece.needsWork)") }
            if !piece.nextAction.isEmpty { lines.append("- Next action: \(piece.nextAction)") }
            noteSections.append(lines.joined(separator: "\n"))
        }

        let didSave = store.savePracticeCompletion(
            PracticeSavePayload(
                sessionID: coordinator.activeSessionID,
                snapshot: snapshot,
                notes: noteSections.joined(separator: "\n\n"),
                noteTitle: cleanedTitle.isEmpty ? coordinator.currentPiece : cleanedTitle,
                noteFocus: cleanedFocus,
                noteMoodRaw: mood.rawValue,
                noteStructuredJSON: structuredJSON,
                toolResult: coordinator.latestToolResult,
                attachedToolResults: coordinator.attachedToolResults
            )
        )

        if didSave {
            coordinator.completeAfterSave(savedSessionID: store.lastSavedSessionID)
        } else {
            saveError = "Your session could not be saved. Your timer and reflection are still here so you can try again."
            isSaving = false
        }
    }
}
