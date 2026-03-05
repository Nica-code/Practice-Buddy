import SwiftUI
import Combine
import AVFoundation
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(ManagedSettings)
import ManagedSettings
#endif

struct TunerNeedleGauge: View {
    let cents: Double?
    let accent: Color
    @Environment(\.pbTypography) private var type

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let centerX = width / 2
            let clamped = max(-50.0, min(50.0, cents ?? 0))
            let x = centerX + CGFloat(clamped / 50.0) * (width * 0.42)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)

                Rectangle()
                    .fill(accent.opacity(0.25))
                    .frame(width: width * 0.04)
                    .position(x: centerX, y: geo.size.height * 0.5)

                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: geo.size.height * 0.7)
                    .position(x: centerX, y: geo.size.height * 0.5)

                Rectangle()
                    .fill(cents == nil ? .secondary : accent)
                    .frame(width: 2, height: geo.size.height * 0.86)
                    .position(x: x, y: geo.size.height * 0.5)
                    .animation(.easeOut(duration: 0.12), value: x)

                HStack {
                    Text("Flat")
                        .font(type.fontChoice.bodyFont(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("In Tune")
                        .font(type.fontChoice.bodyFont(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Sharp")
                        .font(type.fontChoice.bodyFont(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .position(x: centerX, y: geo.size.height - 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tuner needle"))
        .accessibilityValue(Text(accessibilityValueText))
    }

    private var accessibilityValueText: String {
        guard let cents else { return "No pitch detected" }
        let absValue = Int(abs(cents).rounded())
        if absValue <= 1 { return "In tune" }
        if cents < 0 { return "\(absValue) cents flat" }
        return "\(absValue) cents sharp"
    }
}

@MainActor
final class MetronomeEngine: ObservableObject {
    enum Subdivision: String, CaseIterable, Identifiable {
        case none
        case eighths
        case triplets
        case sixteenths

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "1/4"
            case .eighths: return "8th"
            case .triplets: return "Triplet"
            case .sixteenths: return "16th"
            }
        }

        var stepFactor: Int {
            switch self {
            case .none: return 1
            case .eighths: return 2
            case .triplets: return 3
            case .sixteenths: return 4
            }
        }
    }

    enum SoundStyle: String, CaseIterable, Identifiable {
        case click
        case wood
        case beep

        var id: String { rawValue }

        var title: String {
            switch self {
            case .click: return "Click"
            case .wood: return "Wood"
            case .beep: return "Beep"
            }
        }
    }

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var currentBeat: Int = 0
    @Published private(set) var currentSubdivision: Int = 0
    @Published private(set) var pulseToken: Int = 0

    private(set) var bpm: Int = 80

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var tickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private var subdivisionBuffer: AVAudioPCMBuffer?
    private var renderFormat: AVAudioFormat?
    private var timerCancellable: AnyCancellable?
    private var stepIndex: Int = 0
    private var didSetupAudio = false
    private var beatsPerBar: Int = 4
    private var subdivision: Subdivision = .none
    private var soundStyle: SoundStyle = .click

    static func clampBeatsPerBar(_ value: Int) -> Int {
        [2, 3, 4, 6].contains(value) ? value : 4
    }

    func setBPM(_ newBPM: Int) {
        bpm = min(max(newBPM, 40), 220)
    }

    func start(beatsPerBar: Int, subdivision: Subdivision, soundStyle: SoundStyle) {
        self.beatsPerBar = Self.clampBeatsPerBar(beatsPerBar)
        self.subdivision = subdivision
        self.soundStyle = soundStyle

        setAudioSessionIfNeeded()
        setupAudioIfNeeded()
        rebuildBuffersIfPossible()

        stepIndex = 0
        isRunning = true
        playTick(isAccent: true)
        currentBeat = 1
        currentSubdivision = 1
        pulseToken += 1

        startTicker()
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isRunning = false
        currentBeat = 0
        currentSubdivision = 0
        stepIndex = 0
    }

    func applyUpdatedConfiguration(beatsPerBar: Int, subdivision: Subdivision, soundStyle: SoundStyle) {
        self.beatsPerBar = Self.clampBeatsPerBar(beatsPerBar)
        self.subdivision = subdivision

        if self.soundStyle != soundStyle {
            self.soundStyle = soundStyle
            rebuildBuffersIfPossible()
        }

        guard isRunning else { return }
        startTicker()
    }

    private func startTicker() {
        timerCancellable?.cancel()
        let factor = max(1, subdivision.stepFactor)
        let interval = 60.0 / (Double(max(40, bpm)) * Double(factor))

        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.advanceStep()
            }
    }

    private func advanceStep() {
        let factor = max(1, subdivision.stepFactor)
        let totalSteps = max(1, beatsPerBar * factor)
        stepIndex = (stepIndex + 1) % totalSteps

        let stepInBeat = stepIndex % factor
        let beatIndex = stepIndex / factor

        let isDownbeat = (stepIndex == 0)
        let isBeatBoundary = (stepInBeat == 0)

        if isDownbeat {
            playTick(isAccent: true)
            pulseToken += 1
        } else if isBeatBoundary {
            playTick(isAccent: false)
            pulseToken += 1
        } else {
            playSubdivisionTick()
        }

        currentBeat = beatIndex + 1
        currentSubdivision = stepInBeat + 1
    }

    private func setAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal; metronome will just be silent if audio session fails.
        }
    }

    private func setupAudioIfNeeded() {
        guard !didSetupAudio else { return }
        didSetupAudio = true

        engine.attach(player)
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let playerFormat = AVAudioFormat(
            standardFormatWithSampleRate: mixerFormat.sampleRate,
            channels: mixerFormat.channelCount
        )
        renderFormat = playerFormat
        engine.connect(player, to: engine.mainMixerNode, format: playerFormat)

        do {
            try engine.start()
            player.play()
        } catch {
            // Non-fatal; metronome UI can still operate.
        }
    }

    private func rebuildBuffersIfPossible() {
        guard let format = renderFormat else { return }

        switch soundStyle {
        case .click:
            accentBuffer = makeClickBuffer(format: format, frequency: 1900, milliseconds: 20, amplitude: 0.70)
            tickBuffer = makeClickBuffer(format: format, frequency: 1500, milliseconds: 18, amplitude: 0.52)
            subdivisionBuffer = makeClickBuffer(format: format, frequency: 1200, milliseconds: 14, amplitude: 0.32)
        case .wood:
            accentBuffer = makeClickBuffer(format: format, frequency: 720, milliseconds: 26, amplitude: 0.80)
            tickBuffer = makeClickBuffer(format: format, frequency: 520, milliseconds: 22, amplitude: 0.58)
            subdivisionBuffer = makeClickBuffer(format: format, frequency: 360, milliseconds: 16, amplitude: 0.34)
        case .beep:
            accentBuffer = makeClickBuffer(format: format, frequency: 1120, milliseconds: 40, amplitude: 0.62)
            tickBuffer = makeClickBuffer(format: format, frequency: 860, milliseconds: 34, amplitude: 0.48)
            subdivisionBuffer = makeClickBuffer(format: format, frequency: 700, milliseconds: 24, amplitude: 0.28)
        }
    }

    private func playTick(isAccent: Bool) {
        guard let buffer = isAccent ? accentBuffer : tickBuffer else { return }

        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func playSubdivisionTick() {
        guard subdivision != .none else { return }
        guard let buffer = subdivisionBuffer else { return }

        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func makeClickBuffer(
        format: AVAudioFormat,
        frequency: Double,
        milliseconds: Double,
        amplitude: Float
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(max(1, Int((milliseconds / 1000.0) * sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)

        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for i in 0..<Int(frameCount) {
                let t = Double(i) / sampleRate
                let decay = exp(-28.0 * t)
                let sample = sin(2.0 * .pi * frequency * t) * decay
                channel[i] = Float(sample) * amplitude
            }
        }

        return buffer
    }
}

@MainActor
final class PracticeAppShieldManager: ObservableObject {
    private let defaults = UserDefaults.standard
    private let selectionDataKey = "pb.practice.screenTime.selection.v1"

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var selectedAppsCount: Int = 0
    @Published private(set) var isShieldingActive: Bool = false
    @Published var statusMessage: String?
    private var hasFamilyControlsEntitlement: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "PBEnableFamilyControls") as? Bool) == true
    }

#if canImport(FamilyControls) && canImport(ManagedSettings)
    @Published var selection = FamilyActivitySelection() {
        didSet {
            selectedAppsCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            persistSelection()
        }
    }
    private var managedStore: ManagedSettingsStore?
#endif

    init() {
        refreshState()
    }

    var statusLine: String {
        if let statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        if !isAvailable {
            return "Screen Time app blocking is unavailable on this device/configuration."
        }
        if !isAuthorized {
            return "Authorization needed. Tap Authorize, then choose apps to block."
        }
        if selectedAppsCount == 0 {
            return "No apps/categories selected yet. Tap Select Apps."
        }
        return "\(selectedAppsCount) target(s) selected for blocking during practice."
    }

    func refreshState() {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard hasFamilyControlsEntitlement else {
            isAvailable = false
            isAuthorized = false
            selectedAppsCount = 0
            isShieldingActive = false
            return
        }
        if #available(iOS 16.0, *) {
            isAvailable = true
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            loadSelection()
        } else {
            isAvailable = false
            isAuthorized = false
            selectedAppsCount = 0
            isShieldingActive = false
        }
#else
        isAvailable = false
        isAuthorized = false
        selectedAppsCount = 0
        isShieldingActive = false
#endif
    }

    func requestAuthorization() async {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard hasFamilyControlsEntitlement else {
            isAvailable = false
            isAuthorized = false
            statusMessage = "Screen Time blocking isn't available in this build."
            return
        }
        guard #available(iOS 16.0, *), isAvailable else {
            statusMessage = "Screen Time blocking isn't available here."
            return
        }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            statusMessage = isAuthorized ? "Screen Time authorization granted." : "Screen Time authorization not granted."
        } catch {
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            statusMessage = L10n.f("Screen Time authorization failed: %@", error.localizedDescription)
        }
#else
        statusMessage = "Screen Time blocking requires FamilyControls support."
#endif
    }

    func startShieldingIfPossible() async {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard hasFamilyControlsEntitlement else {
            isAvailable = false
            isAuthorized = false
            statusMessage = "Screen Time blocking isn't available in this build."
            return
        }
        guard #available(iOS 16.0, *), isAvailable else {
            statusMessage = "Screen Time blocking isn't available here."
            return
        }

        if !isAuthorized {
            await requestAuthorization()
        }
        guard isAuthorized else { return }

        guard selectedAppsCount > 0 else {
            statusMessage = "Pick apps or categories first with Select Apps."
            return
        }

        let store = managedStore ?? ManagedSettingsStore()
        managedStore = store
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        isShieldingActive = true
        statusMessage = "Distracting apps/categories are blocked while practice is running."
#else
        statusMessage = "Screen Time blocking requires FamilyControls support."
        isShieldingActive = false
#endif
    }

    func stopShielding() {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        isShieldingActive = false
        guard let store = managedStore else { return }
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
#else
        isShieldingActive = false
#endif
    }

#if canImport(FamilyControls) && canImport(ManagedSettings)
    var selectionBinding: Binding<FamilyActivitySelection>? {
        guard #available(iOS 16.0, *), hasFamilyControlsEntitlement else { return nil }
        return Binding(
            get: { self.selection },
            set: {
                self.selection = $0
                self.statusMessage = nil
            }
        )
    }

    private func persistSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: selectionDataKey)
    }

    private func loadSelection() {
        guard let data = defaults.data(forKey: selectionDataKey),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            selectedAppsCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            return
        }
        selection = decoded
        selectedAppsCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }
#else
    var selectionBinding: Binding<Never>? { nil }
#endif
}

struct PracticeAppShieldPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
#if canImport(FamilyControls) && canImport(ManagedSettings)
    let selection: Binding<FamilyActivitySelection>?
#else
    let selection: Binding<Never>?
#endif

    func body(content: Content) -> some View {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        if #available(iOS 16.0, *) {
            if let selection {
                content.familyActivityPicker(isPresented: $isPresented, selection: selection)
            } else {
                content
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

extension View {
#if canImport(FamilyControls) && canImport(ManagedSettings)
    func practiceAppShieldPicker(
        isPresented: Binding<Bool>,
        selection: Binding<FamilyActivitySelection>?
    ) -> some View {
        modifier(PracticeAppShieldPickerModifier(isPresented: isPresented, selection: selection))
    }
#else
    func practiceAppShieldPicker(
        isPresented: Binding<Bool>,
        selection: Binding<Never>?
    ) -> some View {
        modifier(PracticeAppShieldPickerModifier(isPresented: isPresented, selection: selection))
    }
#endif
}
