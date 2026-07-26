import SwiftUI
import Combine

struct WarmUpGeneratorView: View {
    private enum Instrument: String, CaseIterable, Identifiable {
        case strings
        case piano
        case voice
        case woodwinds

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    private enum Focus: String, CaseIterable, Identifiable {
        case intonation
        case shifts
        case bowStrokes
        case rhythm
        case tone

        var id: String { rawValue }
        var title: String {
            switch self {
            case .bowStrokes: return "Bow Strokes"
            default: return rawValue.capitalized
            }
        }
    }

    private struct WarmupStep: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let seconds: Int
    }

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var store: SessionStore

    @State private var minutes: Int = 10
    @State private var instrument: Instrument = .strings
    @State private var selectedFocus: Set<String> = [Focus.intonation.rawValue, Focus.rhythm.rawValue]

    @State private var generatedTitle: String = "Custom Warm-up"
    @State private var generatedSteps: [WarmupStep] = []
    @State private var statusMessage: String?

    @State private var isRunning: Bool = false
    @State private var stepIndex: Int = 0
    @State private var stepRemainingSeconds: Int = 0
    @State private var elapsedSeconds: Int = 0
    @State private var timerCancellable: AnyCancellable?

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var currentStep: WarmupStep? {
        generatedSteps.indices.contains(stepIndex) ? generatedSteps[stepIndex] : nil
    }

    var body: some View {
        Form {
            Section("Generate Warm-up") {
                Picker("Time", selection: $minutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("20 min").tag(20)
                }
                .pickerStyle(.segmented)

                Picker("Instrument", selection: $instrument) {
                    ForEach(Instrument.allCases) { i in
                        Text(LocalizedStringKey(i.title)).tag(i)
                    }
                }
                .pickerStyle(.segmented)

                Text("Focus")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)

                ForEach(Focus.allCases) { focus in
                    Button {
                        if selectedFocus.contains(focus.rawValue) {
                            selectedFocus.remove(focus.rawValue)
                        } else {
                            selectedFocus.insert(focus.rawValue)
                        }
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(focus.title))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Image(systemName: selectedFocus.contains(focus.rawValue) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedFocus.contains(focus.rawValue) ? palette.accent : palette.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button("Generate") {
                    generateWarmup()
                }
                .buttonStyle(.borderedProminent)
                .font(type.button)
            }
            .listRowBackground(palette.surface)

            if !generatedSteps.isEmpty {
                Section("Plan") {
                    Text(generatedTitle)
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)

                    ForEach(Array(generatedSteps.enumerated()), id: \.offset) { idx, step in
                        HStack {
                            Text(L10n.f("%@. %@", "\(idx + 1)", String(localized: String.LocalizationValue(step.title))))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(2)
                            Spacer()
                            Text(DurationFormatter.string(from: step.seconds))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                    }

                }
                .listRowBackground(palette.surface)

                Section("Run") {
                    if let step = currentStep {
                        HStack {
                            Text("Current")
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(LocalizedStringKey(step.title))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Remaining")
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(DurationFormatter.string(from: stepRemainingSeconds))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                        HStack {
                            Text("Elapsed")
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(DurationFormatter.string(from: elapsedSeconds))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                    }

                    HStack(spacing: 10) {
                        Button(isRunning ? "Pause" : "Start") {
                            isRunning ? pauseRun() : startRun()
                        }
                        .buttonStyle(.borderedProminent)
                        .font(type.button)
                        .disabled(generatedSteps.isEmpty)

                        Button("Next") {
                            nextStep()
                        }
                        .buttonStyle(.bordered)
                        .font(type.button)
                        .disabled(currentStep == nil)
                    }

                    Button("Finish Warm-up") {
                        finishWarmup()
                    }
                    .buttonStyle(.bordered)
                    .font(type.button)
                    .disabled(elapsedSeconds == 0)
                }
                .listRowBackground(palette.surface)
            }

            if let msg = statusMessage, !msg.isEmpty {
                Section {
                    Text(LocalizedStringKey(msg))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .modifier(StudioQuestToolChrome(fallback: chrome))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            stopTimer()
        }
    }

    private func generateWarmup() {
        let focus = selectedFocus.isEmpty ? [Focus.intonation.rawValue] : selectedFocus.sorted()
        let totalSeconds = minutes * 60
        let perStep = max(45, totalSeconds / max(1, focus.count + 1))
        var steps: [WarmupStep] = [
            WarmupStep(title: "Open strings + long tones", seconds: perStep)
        ]

        for item in focus {
            let title: String
            switch item {
            case Focus.intonation.rawValue:
                title = "Slow scales with drone (intonation)"
            case Focus.shifts.rawValue:
                title = "Position shifts ladder"
            case Focus.bowStrokes.rawValue:
                title = "Bow stroke patterns"
            case Focus.rhythm.rawValue:
                title = "Subdivision claps + rhythms"
            case Focus.tone.rawValue:
                title = "Tone core + resonance"
            default:
                title = item.capitalized
            }
            steps.append(WarmupStep(title: title, seconds: perStep))
        }

        let current = steps.reduce(0) { $0 + $1.seconds }
        if current < totalSeconds, var last = steps.last {
            let bonus = totalSeconds - current
            steps.removeLast()
            last = WarmupStep(title: last.title, seconds: last.seconds + bonus)
            steps.append(last)
        }

        generatedTitle = L10n.f("%@m %@ Warm-up", "\(minutes)", String(localized: String.LocalizationValue(instrument.title)))
        generatedSteps = steps
        stepIndex = 0
        stepRemainingSeconds = steps.first?.seconds ?? 0
        elapsedSeconds = 0
        isRunning = false
        statusMessage = "Warm-up generated."
    }

    private func startRun() {
        guard currentStep != nil else { return }
        if stepRemainingSeconds <= 0 {
            stepRemainingSeconds = currentStep?.seconds ?? 0
        }
        isRunning = true
        startTimer()
    }

    private func pauseRun() {
        isRunning = false
        stopTimer()
    }

    private func nextStep() {
        guard currentStep != nil else { return }
        if stepIndex + 1 >= generatedSteps.count {
            isRunning = false
            stopTimer()
            return
        }
        stepIndex += 1
        stepRemainingSeconds = generatedSteps[stepIndex].seconds
    }

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                tick()
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func tick() {
        guard isRunning else { return }
        elapsedSeconds += 1
        stepRemainingSeconds -= 1
        if stepRemainingSeconds <= 0 {
            nextStep()
        }
    }

    private func finishWarmup() {
        stopTimer()
        isRunning = false

        let summary = """
        Warm-up Generator
        Title: \(generatedTitle)
        Duration: \(DurationFormatter.string(from: elapsedSeconds))
        Focus: \(selectedFocus.sorted().joined(separator: ", "))
        Steps: \(generatedSteps.map(\.title).joined(separator: " | "))
        """

        let didSave = store.addSession(
            date: Date(),
            durationSeconds: max(1, elapsedSeconds),
            notes: summary,
            noteTitle: "Warm-up Generator",
            noteFocus: selectedFocus.sorted().joined(separator: ", ")
        )

        if didSave {
            PracticeQuestProgressStore.shared.record("warm-up-warrior")
            statusMessage = "Warm-up saved."
        } else {
            statusMessage = "The warm-up could not be saved. Please try again."
        }
    }
}
