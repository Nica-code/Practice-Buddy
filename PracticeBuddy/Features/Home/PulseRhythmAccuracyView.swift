import SwiftUI
import SwiftData
import AVFoundation
import Combine

struct PulseRhythmAccuracyView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var assignmentLinkManager: AssignmentLinkManager

    @AppStorage("pb.rhythm.bpm") private var bpm: Int = 80
    @AppStorage("pb.rhythm.useMetronome") private var useMetronome: Bool = true
    @AppStorage("pb.rhythm.targetBeats") private var targetBeats: Int = 16
    @StateObject private var engine = RhythmAccuracyEngine()
    @StateObject private var metronome = MetronomeEngine()
    @State private var statusMessage: String?
    @State private var markLinkedAssignmentComplete: Bool = true
    @State private var linkedAssignmentNote: String = ""

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        Form {
            Section("Setup") {
                Stepper("Tempo: \(bpm) BPM", value: $bpm, in: 40...220)
                    .font(type.body)

                Stepper("Target beats: \(targetBeats)", value: $targetBeats, in: 8...128, step: 8)
                    .font(type.body)

                Toggle("Use metronome click", isOn: $useMetronome)
                    .font(type.body)
            }
            .listRowBackground(palette.surface)

            Section("Live") {
                HStack {
                    Text("State")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(engine.isRunning ? "Listening" : "Ready")
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Beats analyzed")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(engine.beatsAnalyzed)")
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Live feel")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(engine.liveFeelText)
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack(spacing: 10) {
                    Button(engine.isRunning ? "Stop Take" : "Start Take") {
                        if engine.isRunning {
                            stopTake()
                        } else {
                            startTake()
                        }
                    }
                    .font(type.button)
                    .buttonStyle(.borderedProminent)

                    if engine.isRunning {
                        Button("Reset") {
                            stopTake(clear: true)
                        }
                        .font(type.button)
                        .buttonStyle(.bordered)
                    }
                }
            }
            .listRowBackground(palette.surface)

            if let summary = engine.summary {
                Section("Summary") {
                    HStack {
                        Text("Average offset")
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(String(format: "%+.1f ms", summary.averageOffsetMs))
                            .font(type.number)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Groove score")
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("\(summary.grooveScore)")
                            .font(type.number)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }

                    if purchaseManager.isPro {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Detailed breakdown")
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            ForEach(Array(summary.windowStats.enumerated()), id: \.offset) { idx, row in
                                Text("Window \(idx + 1): \(row)")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    } else {
                        Text("Detailed per-window rhythm stats are part of Practice Buddy Pro.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }

                    if let linked = assignmentLinkManager.linkedAssignment {
                        Divider().padding(.vertical, 4)
                        Text("Linked assignment: \(linked.title)")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Toggle("Mark linked assignment complete", isOn: $markLinkedAssignmentComplete)
                            .font(type.body)
                        TextField("Assignment note (optional)", text: $linkedAssignmentNote, axis: .vertical)
                            .font(type.body)
                            .lineLimit(2...5)
                    }

                    Button("Save Take") {
                        saveTake(summary: summary)
                    }
                    .font(type.button)
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(palette.surface)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)
            }

            if let engineMessage = engine.statusMessage, !engineMessage.isEmpty {
                Section {
                    Text(engineMessage)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            stopTake(clear: false)
        }
    }

    private func startTake() {
        bpm = min(max(bpm, 40), 220)
        targetBeats = min(max(targetBeats, 8), 128)
        if useMetronome {
            metronome.setBPM(bpm)
            metronome.start(beatsPerBar: 4, subdivision: .none, soundStyle: .click)
        }
        engine.start(bpm: bpm, targetBeats: targetBeats)
    }

    private func stopTake(clear: Bool = false) {
        metronome.stop()
        engine.stop(clear: clear)
    }

    private func saveTake(summary: RhythmAccuracySummary) {
        let detail = purchaseManager.isPro ? summary.windowStats.joined(separator: "|") : ""
        let log = RhythmAccuracyTakeModel(
            bpm: bpm,
            beatsAnalyzed: summary.beatsAnalyzed,
            averageOffsetMs: summary.averageOffsetMs,
            grooveScore: summary.grooveScore,
            usedMetronome: useMetronome,
            detailJSON: detail
        )
        modelContext.insert(log)
        try? modelContext.save()

        if assignmentLinkManager.linkedAssignment != nil {
            let fallback = String(format: "Rhythm take: score %d, avg %+.1f ms.", summary.grooveScore, summary.averageOffsetMs)
            let note = linkedAssignmentNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallback
                : linkedAssignmentNote.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                await assignmentLinkManager.submitLinkedPracticeResult(
                    tool: "rhythm_accuracy",
                    note: note,
                    attachmentPath: nil,
                    markComplete: markLinkedAssignmentComplete
                )
            }
        }

        statusMessage = "Rhythm take saved in History."
    }
}

struct RhythmAccuracySummary {
    let beatsAnalyzed: Int
    let averageOffsetMs: Double
    let grooveScore: Int
    let windowStats: [String]
}

@MainActor
final class RhythmAccuracyEngine: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var beatsAnalyzed: Int = 0
    @Published private(set) var liveFeelText: String = "--"
    @Published private(set) var summary: RhythmAccuracySummary?
    @Published private(set) var statusMessage: String?

    private let engine = AVAudioEngine()
    private var startHostSeconds: TimeInterval?
    private var beatInterval: TimeInterval = 0.75
    private var targetBeats: Int = 16
    private var offsetsMs: [Double] = []
    private var envelopeState: Float = 0
    private var wasAboveThreshold = false
    private var lastOnsetTime: TimeInterval = 0
    private let threshold: Float = 0.02
    private let refractorySeconds: TimeInterval = 0.08

    func start(bpm: Int, targetBeats: Int) {
        stop(clear: true)
        self.targetBeats = targetBeats
        self.beatInterval = 60.0 / Double(min(max(bpm, 40), 220))
        self.startHostSeconds = nil
        self.summary = nil
        self.statusMessage = "Requesting microphone permission..."
        requestPermissionAndStartInput()
    }

    func stop(clear: Bool) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        statusMessage = nil
        if clear {
            offsetsMs = []
            beatsAnalyzed = 0
            liveFeelText = "--"
            summary = nil
        } else if !offsetsMs.isEmpty {
            summary = buildSummary()
        }
    }

    private func requestPermissionAndStartInput() {
        let session = AVAudioSession.sharedInstance()
        let handler: (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.statusMessage = "Microphone permission is required for rhythm accuracy."
                    return
                }
                self.startInput()
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                handler(granted)
            }
        } else {
            session.requestRecordPermission { granted in
                handler(granted)
            }
        }
    }

    private func startInput() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true, options: [])

            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
                self?.processBuffer(buffer: buffer, sampleRate: format.sampleRate, hostTime: when.hostTime)
            }
            try engine.start()
            isRunning = true
            statusMessage = "Listening..."
        } catch {
            isRunning = false
            statusMessage = "Rhythm input failed to start."
        }
    }

    private func processBuffer(buffer: AVAudioPCMBuffer, sampleRate: Double, hostTime: UInt64) {
        guard let channelData = buffer.floatChannelData else { return }
        let channel = channelData[0]
        let count = Int(buffer.frameLength)
        if count < 32 { return }

        var peak: Float = 0
        for i in 0..<count {
            let v = abs(channel[i])
            envelopeState = max(v, envelopeState * 0.96)
            peak = max(peak, envelopeState)
        }

        let secondsNow = AVAudioTime.seconds(forHostTime: hostTime)
        let above = peak >= threshold
        let canTrigger = (secondsNow - lastOnsetTime) > refractorySeconds

        if above && !wasAboveThreshold && canTrigger {
            lastOnsetTime = secondsNow
            registerOnset(at: secondsNow)
        }
        wasAboveThreshold = above
    }

    private func registerOnset(at absoluteSeconds: TimeInterval) {
        if startHostSeconds == nil {
            startHostSeconds = absoluteSeconds
        }
        guard let startHostSeconds else { return }
        let elapsed = absoluteSeconds - startHostSeconds
        guard elapsed >= 0 else { return }

        let beatIndex = Int(round(elapsed / beatInterval))
        let gridTime = Double(beatIndex) * beatInterval
        let offsetMs = (elapsed - gridTime) * 1000.0

        offsetsMs.append(offsetMs)
        beatsAnalyzed = offsetsMs.count
        liveFeelText = offsetMs == 0 ? "On" : (offsetMs < 0 ? "Early" : "Late")

        if beatsAnalyzed >= targetBeats {
            isRunning = false
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            summary = buildSummary()
            statusMessage = "Take complete."
        }
    }

    private func buildSummary() -> RhythmAccuracySummary {
        let count = max(1, offsetsMs.count)
        let avg = offsetsMs.reduce(0, +) / Double(count)
        let avgAbs = offsetsMs.map { abs($0) }.reduce(0, +) / Double(count)
        let score = Int(max(0, min(100, 100.0 - (avgAbs / 80.0) * 100.0)))

        var windows: [String] = []
        var idx = 0
        while idx < offsetsMs.count {
            let end = min(idx + 16, offsetsMs.count)
            let chunk = Array(offsetsMs[idx..<end])
            let chunkAvg = chunk.reduce(0, +) / Double(max(1, chunk.count))
            let chunkAbs = chunk.map { abs($0) }.reduce(0, +) / Double(max(1, chunk.count))
            windows.append(String(format: "avg %+.1f ms, abs %.1f ms", chunkAvg, chunkAbs))
            idx = end
        }

        return RhythmAccuracySummary(
            beatsAnalyzed: offsetsMs.count,
            averageOffsetMs: avg,
            grooveScore: score,
            windowStats: windows
        )
    }
}
