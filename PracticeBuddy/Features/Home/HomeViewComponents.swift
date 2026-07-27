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
    private var loopBuffer: AVAudioPCMBuffer?
    private var renderFormat: AVAudioFormat?
    private var timerCancellable: AnyCancellable?
    private var stepIndex: Int = 0
    private var didSetupAudio = false
    private var beatsPerBar: Int = 4
    private var subdivision: Subdivision = .none
    private var soundStyle: SoundStyle = .click
    private var shouldResumeAfterInterruption = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private let managesAudioSession: Bool

    init(managesAudioSession: Bool = true) {
        self.managesAudioSession = managesAudioSession
        if managesAudioSession {
            installAudioSessionObservers()
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

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

        if managesAudioSession {
            setAudioSessionIfNeeded()
        }
        setupAudioIfNeeded()
        rebuildBuffersIfPossible()
        scheduleLoopPlaybackIfPossible()

        stepIndex = 0
        isRunning = true
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
        player.stop()
    }

    func applyUpdatedConfiguration(beatsPerBar: Int, subdivision: Subdivision, soundStyle: SoundStyle) {
        self.beatsPerBar = Self.clampBeatsPerBar(beatsPerBar)
        self.subdivision = subdivision
        self.soundStyle = soundStyle
        rebuildBuffersIfPossible()

        guard isRunning else { return }
        scheduleLoopPlaybackIfPossible()
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

        if stepInBeat == 0 {
            pulseToken += 1
        }

        currentBeat = beatIndex + 1
        currentSubdivision = stepInBeat + 1
    }

    private func setAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
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

        loopBuffer = makeLoopBuffer(format: format)
    }

    private func scheduleLoopPlaybackIfPossible() {
        guard let loopBuffer else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        player.stop()
        player.scheduleBuffer(loopBuffer, at: nil, options: [.loops], completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    private func makeLoopBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let factor = max(1, subdivision.stepFactor)
        let totalSteps = max(1, beatsPerBar * factor)
        let stepSeconds = 60.0 / (Double(max(40, bpm)) * Double(factor))
        let sampleRate = format.sampleRate
        let totalFramesInt = max(1, Int((Double(totalSteps) * stepSeconds * sampleRate).rounded()))
        let totalFrames = AVAudioFrameCount(totalFramesInt)

        guard let destination = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        destination.frameLength = totalFrames
        guard let channels = destination.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)

        for channelIndex in 0..<channelCount {
            channels[channelIndex].initialize(repeating: 0, count: totalFramesInt)
        }

        for step in 0..<totalSteps {
            let stepInBeat = step % factor
            let beatIndex = step / factor
            let isDownbeat = beatIndex == 0 && stepInBeat == 0
            let isBeatBoundary = stepInBeat == 0

            let source: AVAudioPCMBuffer?
            if isDownbeat {
                source = accentBuffer
            } else if isBeatBoundary {
                source = tickBuffer
            } else {
                source = subdivision == .none ? nil : subdivisionBuffer
            }

            guard let source else { continue }
            let startFrame = Int((Double(step) * stepSeconds * sampleRate).rounded())
            mix(source: source, into: destination, atFrame: startFrame)
        }

        return destination
    }

    private func mix(source: AVAudioPCMBuffer, into destination: AVAudioPCMBuffer, atFrame startFrame: Int) {
        guard let sourceChannels = source.floatChannelData,
              let destinationChannels = destination.floatChannelData else { return }

        let sourceFrames = Int(source.frameLength)
        let destinationFrames = Int(destination.frameLength)
        let channelCount = min(Int(source.format.channelCount), Int(destination.format.channelCount))
        guard startFrame < destinationFrames else { return }

        for channelIndex in 0..<channelCount {
            let sourceChannel = sourceChannels[channelIndex]
            let destinationChannel = destinationChannels[channelIndex]
            var destIndex = startFrame
            var sourceIndex = 0

            while sourceIndex < sourceFrames && destIndex < destinationFrames {
                destinationChannel[destIndex] += sourceChannel[sourceIndex]
                sourceIndex += 1
                destIndex += 1
            }
        }
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

    private func installAudioSessionObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let typeRaw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self.handleAudioInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let reasonRaw = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self.handleAudioRouteChange(reasonRaw: reasonRaw)
            }
        }
    }

    private func handleAudioInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }

        switch type {
        case .began:
            shouldResumeAfterInterruption = isRunning
        case .ended:
            guard shouldResumeAfterInterruption, isRunning else { return }
            shouldResumeAfterInterruption = false
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            if options.contains(.shouldResume) {
                restartPlaybackGraphIfRunning()
            }
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(reasonRaw: UInt?) {
        guard isRunning else { return }
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .override:
            restartPlaybackGraphIfRunning()
        default:
            break
        }
    }

    private func restartPlaybackGraphIfRunning() {
        guard isRunning else { return }
        setAudioSessionIfNeeded()
        setupAudioIfNeeded()
        rebuildBuffersIfPossible()
        scheduleLoopPlaybackIfPossible()
        startTicker()
    }
}

@MainActor
final class PracticeAppShieldManager: ObservableObject {
    private let defaults = UserDefaults.standard
    private let selectionDataKey = "pb.practice.screenTime.selection.v1"
    private let blockAllAppsKey = "pb.practice.screenTime.blockAllApps.v1"
    private let setupCompletedKey = "pb.practice.screenTime.setupCompleted.v1"

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var selectedAppsCount: Int = 0
    @Published private(set) var isShieldingActive: Bool = false
    @Published var statusMessage: String?
    @Published private(set) var entitlementDetected: Bool = false
    private var hasFamilyControlsEntitlement: Bool {
        // Optional manual override from Info.plist for local debug/testing.
        if let override = Bundle.main.object(forInfoDictionaryKey: "PBEnableFamilyControls") as? Bool {
            return override
        }
        // iOS does not expose a stable runtime entitlement API for this capability.
#if targetEnvironment(simulator)
        return false
#else
        return true
#endif
    }

#if canImport(FamilyControls) && canImport(ManagedSettings)
    @Published var selection = FamilyActivitySelection() {
        didSet {
            if !isRestoringSelection {
                blockAllAppsSelection = false
            }
            selectedAppsCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            persistSelection()
        }
    }
    private var managedStore: ManagedSettingsStore?
    private var isRestoringSelection = false
    private var blockAllAppsSelection: Bool = false {
        didSet {
            defaults.set(blockAllAppsSelection, forKey: blockAllAppsKey)
            if blockAllAppsSelection {
                selectedAppsCount = 1
            } else {
                selectedAppsCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            }
        }
    }
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
            if hasCompletedSetup {
                return "Screen Time access is currently off. Re-enable it in Settings, then toggle Verified Mode again."
            }
            return "First-time setup: tap Continue in the iOS Screen Time prompt to finish."
        }
        if selectedAppsCount == 0 {
            return "Preparing app blocking setup."
        }
        if isAllAppsSelected {
            return "All apps selected for blocking during verified practice."
        }
        return "\(selectedAppsCount) target(s) selected for blocking during practice."
    }

    var isAllAppsSelected: Bool {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        blockAllAppsSelection
#else
        false
#endif
    }

    var isVerificationConfigured: Bool {
        isAuthorized && selectedAppsCount > 0
    }

    private var hasCompletedSetup: Bool {
        defaults.bool(forKey: setupCompletedKey)
    }

    func refreshState() {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        entitlementDetected = hasFamilyControlsEntitlement
#if targetEnvironment(simulator)
        isAvailable = false
        isAuthorized = false
        selectedAppsCount = 0
        isShieldingActive = false
        statusMessage = "Screen Time app blocking requires a real iPhone."
#else
        if #available(iOS 16.0, *) {
            isAvailable = true
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            loadSelection()
            if !entitlementDetected {
                statusMessage = "Screen Time signing is not detected yet. Authorization may fail until profile refresh."
            }
        } else {
            isAvailable = false
            isAuthorized = false
            selectedAppsCount = 0
            isShieldingActive = false
        }
#endif
#else
        isAvailable = false
        isAuthorized = false
        selectedAppsCount = 0
        isShieldingActive = false
        entitlementDetected = false
#endif
    }

    func requestAuthorization() async {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard #available(iOS 16.0, *), isAvailable else {
            statusMessage = "Screen Time blocking isn't available here."
            return
        }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            entitlementDetected = hasFamilyControlsEntitlement
            if isAuthorized {
                defaults.set(true, forKey: setupCompletedKey)
            }
            statusMessage = isAuthorized ? "Screen Time authorization granted." : "Screen Time authorization not granted."
        } catch {
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            entitlementDetected = hasFamilyControlsEntitlement
            if isAuthorized {
                defaults.set(true, forKey: setupCompletedKey)
            }
            if isLikelyEntitlementFailure(error) {
                statusMessage = "Screen Time signing is missing for this build. Recreate provisioning profile and reinstall."
            } else {
                statusMessage = L10n.f("Screen Time authorization failed: %@", error.localizedDescription)
            }
        }
#else
        statusMessage = "Screen Time blocking requires FamilyControls support."
#endif
    }

    func configureAutoVerificationDefaults() async {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard #available(iOS 16.0, *), isAvailable else {
            statusMessage = "Screen Time blocking isn't available here."
            return
        }

        if !isAuthorized {
            if !hasCompletedSetup {
                statusMessage = "First-time setup: tap Continue in the iOS Screen Time prompt."
            }
            await requestAuthorization()
        }
        guard isAuthorized else { return }

        applyAllAppsSelection()
        statusMessage = "Verified Mode is ready. All apps will be blocked during practice."
#endif
    }

    func startShieldingIfPossible() async {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard #available(iOS 16.0, *), isAvailable else {
            statusMessage = "Screen Time blocking isn't available here."
            return
        }

        if !isAuthorized {
            await requestAuthorization()
        }
        guard isAuthorized else { return }

        guard selectedAppsCount > 0 else {
            statusMessage = "Verification setup is incomplete. Toggle Verified Mode off and on again."
            return
        }

        let store = managedStore ?? ManagedSettingsStore()
        managedStore = store
        if blockAllAppsSelection {
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: Set())
            store.shield.webDomains = nil
            store.shield.webDomainCategories = .all(except: Set())
            store.webContent.blockedByFilter = .all(except: Set())
        } else {
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty
                ? nil
                : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = nil
        }
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
        store.shield.webDomainCategories = nil
        store.webContent.blockedByFilter = nil
#else
        isShieldingActive = false
#endif
    }

#if canImport(FamilyControls) && canImport(ManagedSettings)
    var selectionBinding: Binding<FamilyActivitySelection>? {
        guard #available(iOS 16.0, *) else { return nil }
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

    private func applyAllAppsSelection() {
        isRestoringSelection = true
        selection = FamilyActivitySelection()
        isRestoringSelection = false
        blockAllAppsSelection = true
    }

    private func loadSelection() {
        blockAllAppsSelection = defaults.bool(forKey: blockAllAppsKey)
        guard let data = defaults.data(forKey: selectionDataKey),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            selectedAppsCount = blockAllAppsSelection
                ? 1
                : selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            return
        }
        isRestoringSelection = true
        selection = decoded
        isRestoringSelection = false
        selectedAppsCount = blockAllAppsSelection
            ? 1
            : selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }
#else
    var selectionBinding: Binding<Never>? { nil }
#endif

    private func isLikelyEntitlementFailure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("entitlement")
            || message.contains("family controls")
            || message.contains("not permitted")
            || message.contains("missing")
    }
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
