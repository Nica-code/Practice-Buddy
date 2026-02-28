import SwiftUI
import SwiftData
import AVFoundation
import Combine

struct RunThroughModeView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var assignmentLinkManager: AssignmentLinkManager

    @AppStorage("pb.runthrough.noPauseMode") private var noPauseMode: Bool = false
    @AppStorage("pb.runthrough.useMetronome") private var useMetronome: Bool = false
    @AppStorage("pb.runthrough.metronomeBPM") private var metronomeBPM: Int = 72

    @StateObject private var recorder = RunThroughRecorder()
    @StateObject private var metronome = MetronomeEngine()
    @State private var timerCancellable: AnyCancellable?
    @State private var elapsedSeconds: Int = 0
    @State private var showFinishSheet = false
    @State private var noteInput: String = ""
    @State private var pieceNameInput: String = ""
    @State private var selfRating: Int = 3
    @State private var markLinkedAssignmentComplete: Bool = true
    @State private var linkedAssignmentNote: String = ""
    @State private var statusMessage: String?
    @State private var markerLabel: String = "shift"
    @State private var markers: [RunThroughMarker] = []
    private let markerOptions: [String] = ["shift", "rhythm", "intonation", "bow", "memory", "other"]

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        Form {
            Section("Setup") {
                Toggle("No pause mode", isOn: $noPauseMode)
                    .font(type.body)
                Toggle("Use metronome click", isOn: $useMetronome)
                    .font(type.body)
                if useMetronome {
                    Stepper(L10n.f("Metronome: %@ BPM", "\(metronomeBPM)"), value: $metronomeBPM, in: 40...220)
                        .font(type.body)
                }
            }
            .listRowBackground(palette.surface)

            Section("Run-through") {
                HStack {
                    Text("Status")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(LocalizedStringKey(recorder.stateTitle))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Timer")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(DurationFormatter.string(from: elapsedSeconds))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                if recorder.isRecording || recorder.isPaused {
                    Picker("Marker", selection: $markerLabel) {
                        ForEach(markerOptions, id: \.self) { option in
                            Text(LocalizedStringKey(option.capitalized)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button("Add Marker") {
                        markers.append(RunThroughMarker(second: elapsedSeconds, label: markerLabel))
                    }
                    .buttonStyle(.bordered)
                    .font(type.button)

                    if !markers.isEmpty {
                        Text(L10n.f("Markers: %@", "\(markers.count)"))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    Button(recorder.isRecording ? "Stop" : "Record") {
                        recorder.isRecording ? stopRecording(showFinish: true) : startRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(type.button)

                    if !noPauseMode {
                        Button(recorder.isPaused ? "Resume" : "Pause") {
                            togglePause()
                        }
                        .buttonStyle(.bordered)
                        .font(type.button)
                        .disabled(!recorder.canPauseToggle)
                    }
                }
            }
            .listRowBackground(palette.surface)

            if let statusMessage {
                Section {
                    Text(LocalizedStringKey(statusMessage))
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
        .sheet(isPresented: $showFinishSheet) {
            NavigationStack {
                Form {
                    Section("Review") {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(DurationFormatter.string(from: elapsedSeconds))
                                .monospacedDigit()
                        }
                        Stepper(L10n.f("Self rating: %@/5", "\(selfRating)"), value: $selfRating, in: 1...5)
                        TextField("Piece / Passage (optional)", text: $pieceNameInput)
                        TextField("Notes (optional)", text: $noteInput, axis: .vertical)
                            .lineLimit(3...8)

                        if !markers.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Mistake markers")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textPrimary)
                                ForEach(markers) { marker in
                                    Text(L10n.f("%@ • %@", DurationFormatter.string(from: marker.second), marker.label.capitalized))
                                        .font(type.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                        }

                        if let linked = assignmentLinkManager.linkedAssignment {
                            Divider().padding(.vertical, 4)
                            Text(L10n.f("Linked assignment: %@", linked.title))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Toggle("Mark linked assignment complete", isOn: $markLinkedAssignmentComplete)
                            TextField("Assignment note (optional)", text: $linkedAssignmentNote, axis: .vertical)
                                .lineLimit(2...5)
                        }
                    }
                }
                .navigationTitle("Finish Run-through")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showFinishSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveRunThrough()
                            showFinishSheet = false
                        }
                    }
                }
            }
        }
        .onDisappear {
            stopTicker()
            if recorder.isRecording || recorder.isPaused {
                stopRecording(showFinish: false)
            }
            metronome.stop()
        }
        .onChange(of: recorder.isRecording) { _, recording in
            if recording {
                startTicker()
            } else if !recorder.isPaused {
                stopTicker()
            }
        }
        .onChange(of: recorder.statusMessage) { _, msg in
            if let msg, !msg.isEmpty {
                statusMessage = msg
            }
        }
    }

    private func startRecording() {
        metronomeBPM = min(max(metronomeBPM, 40), 220)
        noteInput = ""
        pieceNameInput = ""
        selfRating = 3
        statusMessage = nil
        elapsedSeconds = 0
        markers = []
        if useMetronome {
            metronome.setBPM(metronomeBPM)
            metronome.start(beatsPerBar: 4, subdivision: .none, soundStyle: (MetronomeEngine.SoundStyle(rawValue: JourneyProgressManager.preferredMetronomeSoundStyleRaw() ?? "click") ?? .click))
        }
        recorder.startRecording()
    }

    private func stopRecording(showFinish: Bool) {
        metronome.stop()
        recorder.stopRecording()
        stopTicker()
        if let message = recorder.statusMessage {
            statusMessage = message
        }
        if showFinish, recorder.lastOutputURL != nil, elapsedSeconds > 0 {
            showFinishSheet = true
        }
    }

    private func togglePause() {
        if recorder.isPaused {
            recorder.resume()
            if recorder.isRecording {
                startTicker()
            }
        } else {
            recorder.pause()
            stopTicker()
        }
        if let message = recorder.statusMessage {
            statusMessage = message
        }
    }

    private func startTicker() {
        stopTicker()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                elapsedSeconds += 1
            }
    }

    private func stopTicker() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func saveRunThrough() {
        guard let url = recorder.lastOutputURL else {
            statusMessage = "No recording found to save."
            return
        }
        let model = RunThroughModel(
            durationSeconds: elapsedSeconds,
            audioFilePath: url.path,
            notes: noteInput.trimmingCharacters(in: .whitespacesAndNewlines),
            selfRating: selfRating,
            noPauseMode: noPauseMode,
            usedMetronome: useMetronome,
            markerJSON: encodeMarkers(markers),
            pieceName: pieceNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(model)
        try? modelContext.save()

        if assignmentLinkManager.linkedAssignment != nil {
            let trimmed = linkedAssignmentNote.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = trimmed.isEmpty
                ? L10n.f(
                    "Run-through saved in History (%@, rating %@/5).",
                    DurationFormatter.string(from: elapsedSeconds),
                    "\(selfRating)"
                )
                : trimmed
            Task {
                await assignmentLinkManager.submitLinkedPracticeResult(
                    tool: "run_through",
                    note: note,
                    attachmentPath: url.path,
                    markComplete: markLinkedAssignmentComplete
                )
            }
        }

        statusMessage = "Run-through saved in History."
    }

    private func encodeMarkers(_ rows: [RunThroughMarker]) -> String {
        guard !rows.isEmpty,
              let data = try? JSONEncoder().encode(rows),
              let raw = String(data: data, encoding: .utf8) else {
            return ""
        }
        return raw
    }
}

@MainActor
final class RunThroughRecorder: ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var lastOutputURL: URL?
    @Published var statusMessage: String?

    private var recorder: AVAudioRecorder?

    var canPauseToggle: Bool { isRecording || isPaused }

    var stateTitle: String {
        if isPaused { return "Paused" }
        if isRecording { return "Recording" }
        return "Ready"
    }

    func startRecording() {
        requestPermissionAndRecord()
    }

    func pause() {
        guard let recorder, recorder.isRecording else { return }
        recorder.pause()
        isRecording = false
        isPaused = true
        statusMessage = "Recording paused."
    }

    func resume() {
        guard let recorder, isPaused else { return }
        if recorder.record() {
            isRecording = true
            isPaused = false
            statusMessage = "Recording resumed."
        }
    }

    func stopRecording() {
        recorder?.stop()
        isRecording = false
        isPaused = false
        statusMessage = "Recording stopped."
    }

    private func requestPermissionAndRecord() {
        statusMessage = "Requesting microphone permission..."
        let session = AVAudioSession.sharedInstance()
        let handler: (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.statusMessage = "Microphone permission is required for recording."
                    return
                }
                self.prepareAndRecord()
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

    private func prepareAndRecord() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true, options: [])

            let url = makeOutputURL()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            if recorder.record() {
                self.recorder = recorder
                self.lastOutputURL = url
                self.isRecording = true
                self.isPaused = false
                self.statusMessage = "Recording..."
            } else {
                self.statusMessage = "Recording could not start."
            }
        } catch {
            statusMessage = L10n.f("Recording failed: %@", error.localizedDescription)
        }
    }

    private func makeOutputURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent("RunThrough", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let name = "runthrough-\(Int(Date().timeIntervalSince1970)).m4a"
        return folder.appendingPathComponent(name)
    }
}
