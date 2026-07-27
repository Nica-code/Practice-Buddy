import AVFAudio
import Combine
import Foundation

enum PracticeAudioOwner: String, Codable, Hashable {
    case practiceSession
    case metronome
    case tuner
    case smartLoop
    case rhythm
    case intonation
    case runThrough
    case duel
}

struct PracticeAudioRequirement: OptionSet, Hashable {
    let rawValue: Int

    static let microphone = PracticeAudioRequirement(rawValue: 1 << 0)
    static let playback = PracticeAudioRequirement(rawValue: 1 << 1)
    static let recording = PracticeAudioRequirement(rawValue: 1 << 2)
}

enum PracticeAudioEvent: Equatable {
    case activated(PracticeAudioOwner)
    case released(PracticeAudioOwner)
    case interrupted(PracticeAudioOwner)
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(hasHeadphones: Bool)
}

enum PracticeAudioSessionError: LocalizedError, Equatable {
    case ownedBy(PracticeAudioOwner)
    case microphoneDenied
    case activationFailed

    var errorDescription: String? {
        switch self {
        case .ownedBy(let owner):
            "\(owner.displayName) is already using audio. Finish or close it before starting another tool."
        case .microphoneDenied:
            "Microphone access is off. Enable it in Settings to use this practice tool."
        case .activationFailed:
            "Audio could not be started. Check your audio route and try again."
        }
    }
}

extension PracticeAudioOwner {
    var displayName: String {
        switch self {
        case .practiceSession: "Practice Studio"
        case .metronome: "Metronome"
        case .tuner: "Tuner"
        case .smartLoop: "Smart Loop"
        case .rhythm: "Rhythm Accuracy"
        case .intonation: "Intonation"
        case .runThrough: "Run-through"
        case .duel: "Duel recording"
        }
    }
}

/// Serializes the process-wide AVAudioSession. Tools still own their signal
/// processing engines, but none may activate the microphone, recorder, tuner,
/// or playback route without first claiming this coordinator.
@MainActor
final class PracticeAudioSessionCoordinator: ObservableObject {
    @Published private(set) var owner: PracticeAudioOwner?
    @Published private(set) var requirements: PracticeAudioRequirement = []
    @Published private(set) var hasHeadphones = false
    @Published private(set) var lastEvent: PracticeAudioEvent?

    private let session: AVAudioSession
    private var observers: [NSObjectProtocol] = []

    init(
        session: AVAudioSession = .sharedInstance(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.session = session
        hasHeadphones = Self.detectHeadphones(in: session.currentRoute)

        observers.append(
            notificationCenter.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                Task { @MainActor [weak self] in
                    self?.handleInterruption(
                        rawType: rawType,
                        rawOptions: rawOptions
                    )
                }
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshRoute()
                }
            }
        )
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func claim(
        _ requestedOwner: PracticeAudioOwner,
        requirements requestedRequirements: PracticeAudioRequirement
    ) async throws {
        if let owner, owner != requestedOwner {
            throw PracticeAudioSessionError.ownedBy(owner)
        }

        if requestedRequirements.contains(.microphone)
            || requestedRequirements.contains(.recording) {
            guard await requestMicrophonePermission() else {
                throw PracticeAudioSessionError.microphoneDenied
            }
        }

        do {
            try configureSession(for: requestedRequirements)
            try session.setActive(true)
            owner = requestedOwner
            requirements = requestedRequirements
            refreshRoute()
            lastEvent = .activated(requestedOwner)
        } catch {
            if owner == requestedOwner {
                owner = nil
                requirements = []
            }
            throw PracticeAudioSessionError.activationFailed
        }
    }

    func release(_ releasingOwner: PracticeAudioOwner) {
        guard owner == releasingOwner else { return }
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // The ownership state must still be released. A later claimant
            // will configure and activate the process-wide session again.
        }
        owner = nil
        requirements = []
        lastEvent = .released(releasingOwner)
    }

    func releaseCurrentOwner() {
        guard let owner else { return }
        release(owner)
    }

    func canClaim(_ requestedOwner: PracticeAudioOwner) -> Bool {
        owner == nil || owner == requestedOwner
    }

    #if DEBUG
    func applyStudioQuestFixture(
        owner: PracticeAudioOwner?,
        requirements: PracticeAudioRequirement = []
    ) {
        self.owner = owner
        self.requirements = owner == nil ? [] : requirements
        lastEvent = owner.map(PracticeAudioEvent.activated)
    }
    #endif

    private func configureSession(for requirements: PracticeAudioRequirement) throws {
        let needsInput = requirements.contains(.microphone)
            || requirements.contains(.recording)
        let needsOutput = requirements.contains(.playback)

        if needsInput && needsOutput {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
        } else if needsInput {
            try session.setCategory(.record, mode: .measurement)
        } else {
            try session.setCategory(.playback, mode: .default)
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            switch session.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    session.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }
    }

    private func handleInterruption(rawType: UInt?, rawOptions: UInt?) {
        guard let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            if let owner {
                lastEvent = .interrupted(owner)
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            lastEvent = .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func refreshRoute() {
        hasHeadphones = Self.detectHeadphones(in: session.currentRoute)
        lastEvent = .routeChanged(hasHeadphones: hasHeadphones)
    }

    private static func detectHeadphones(in route: AVAudioSessionRouteDescription) -> Bool {
        let privateOutputs: Set<AVAudioSession.Port> = [
            .headphones,
            .headsetMic,
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE,
            .usbAudio
        ]
        return route.outputs.contains(where: { privateOutputs.contains($0.portType) })
    }
}
