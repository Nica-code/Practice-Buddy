import Foundation
import AVFoundation
import Combine

nonisolated struct TunerAnalysisGate: Sendable {
    let minimumInterval: TimeInterval
    private var lastAnalysisTime: TimeInterval?

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    mutating func shouldAnalyze(at time: TimeInterval) -> Bool {
        guard let lastAnalysisTime else {
            self.lastAnalysisTime = time
            return true
        }
        guard time >= lastAnalysisTime + minimumInterval else { return false }
        self.lastAnalysisTime = time
        return true
    }
}

nonisolated struct TunerPitchAnalyzer: Sendable {
    nonisolated static func detectFrequency(
        in samples: [Float],
        sampleRate: Double
    ) -> Double? {
        let minFrequency = 80.0
        let maxFrequency = 1_200.0
        let minLag = max(2, Int(sampleRate / maxFrequency))
        let maxLag = min(samples.count - 2, Int(sampleRate / minFrequency))
        guard minLag < maxLag else { return nil }

        var correlations = Array(repeating: 0.0, count: maxLag + 2)
        var bestCorrelation = -Double.infinity
        for lag in minLag...maxLag {
            let correlation = normalizedCorrelation(samples: samples, lag: lag)
            correlations[lag] = correlation
            bestCorrelation = max(bestCorrelation, correlation)
        }

        guard bestCorrelation >= 0.15 else { return nil }
        let peakThreshold = max(0.15, bestCorrelation * 0.90)
        let bestLag = (minLag...maxLag).first { lag in
            correlations[lag] >= peakThreshold
                && correlations[lag] >= correlations[lag - 1]
                && correlations[lag] >= correlations[lag + 1]
        } ?? minLag

        let c1 = correlations[bestLag - 1]
        let c2 = correlations[bestLag]
        let c3 = correlations[bestLag + 1]
        let denominator = c1 - 2 * c2 + c3
        var refinedLag = Double(bestLag)
        if abs(denominator) > 1e-9 {
            refinedLag += 0.5 * (c1 - c3) / denominator
        }

        guard refinedLag > 0 else { return nil }
        return sampleRate / refinedLag
    }

    private nonisolated static func normalizedCorrelation(
        samples: [Float],
        lag: Int
    ) -> Double {
        guard lag > 0, lag < samples.count else { return 0 }
        let end = samples.count - lag
        var sum = 0.0
        var energyA = 0.0
        var energyB = 0.0
        for index in 0..<end {
            let a = Double(samples[index])
            let b = Double(samples[index + lag])
            sum += a * b
            energyA += a * a
            energyB += b * b
        }
        let denominator = sqrt(energyA * energyB)
        return denominator > 0 ? sum / denominator : 0
    }
}

nonisolated private struct TunerAnalysisResult: Sendable {
    let samples: [Float]
    let hostSeconds: TimeInterval
    let level: Double
    let frequency: Double?
}

nonisolated private final class TunerAudioAnalyzer: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.practiquest.tuner-analysis",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private var gate = TunerAnalysisGate(minimumInterval: 0.1)
    private var analysisInFlight = false

    nonisolated func submit(
        buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        hostSeconds: TimeInterval,
        completion: @escaping @Sendable (TunerAnalysisResult) -> Void
    ) {
        lock.lock()
        let accepted = !analysisInFlight && gate.shouldAnalyze(at: hostSeconds)
        if accepted { analysisInFlight = true }
        lock.unlock()
        guard accepted, let channelData = buffer.floatChannelData else { return }

        let count = Int(buffer.frameLength)
        guard count >= 512 else {
            finishAnalysis()
            return
        }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

        queue.async { [weak self] in
            guard let self else { return }
            let reduced = Self.downsample(samples, sourceSampleRate: sampleRate)
            var rms: Float = 0
            for sample in reduced.samples { rms += sample * sample }
            rms = sqrt(rms / Float(max(1, reduced.samples.count)))
            let level = Double(rms)
            let frequency = level > 0.003
                ? TunerPitchAnalyzer.detectFrequency(
                    in: reduced.samples,
                    sampleRate: reduced.sampleRate
                )
                : nil
            completion(
                TunerAnalysisResult(
                    samples: samples,
                    hostSeconds: hostSeconds,
                    level: level,
                    frequency: frequency
                )
            )
            self.finishAnalysis()
        }
    }

    nonisolated func reset() {
        lock.lock()
        gate = TunerAnalysisGate(minimumInterval: 0.1)
        lock.unlock()
    }

    private nonisolated func finishAnalysis() {
        lock.lock()
        analysisInFlight = false
        lock.unlock()
    }

    private nonisolated static func downsample(
        _ samples: [Float],
        sourceSampleRate: Double
    ) -> (samples: [Float], sampleRate: Double) {
        let factor = max(1, Int(sourceSampleRate / 12_000))
        guard factor > 1 else { return (samples, sourceSampleRate) }

        var reduced: [Float] = []
        reduced.reserveCapacity(samples.count / factor)
        var start = 0
        while start + factor <= samples.count {
            let end = start + factor
            var sum: Float = 0
            for index in start..<end { sum += samples[index] }
            reduced.append(sum / Float(factor))
            start = end
        }
        return (reduced, sourceSampleRate / Double(factor))
    }
}

@MainActor
final class TunerEngine: ObservableObject {
    enum MicPermissionState: Equatable {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var permissionState: MicPermissionState = .unknown
    @Published private(set) var isListening: Bool = false
    @Published private(set) var isReferenceTonePlaying: Bool = false
    @Published private(set) var detectedFrequency: Double?
    @Published private(set) var detectedNoteName: String = "--"
    @Published private(set) var detectedCents: Double = 0
    @Published private(set) var inputLevel: Double = 0
    @Published var statusMessage: String?

    /// Optional observer for features that need the same microphone frames as
    /// the tuner. Duel capture uses this to derive rhythm from one shared input
    /// tap instead of starting a competing AVAudioEngine.
    var onInputSamples: (([Float], TimeInterval) -> Void)?

    private let inputEngine = AVAudioEngine()
    private let toneEngine = AVAudioEngine()
    private var toneNode: AVAudioSourceNode?
    private var tonePhase: Double = 0
    private var toneFrequency: Double = 440
    private let audioAnalyzer = TunerAudioAnalyzer()
    private let managesAudioSession: Bool
    private var referenceFrequency = 440.0

    init(managesAudioSession: Bool = true) {
        self.managesAudioSession = managesAudioSession
    }

    func toggleReferenceTone(frequency: Double) {
        if isReferenceTonePlaying {
            stopReferenceTone()
        } else {
            startReferenceTone(frequency: frequency)
        }
    }

    func setReferenceFrequency(_ frequency: Double) {
        referenceFrequency = min(max(frequency, 415), 466)
    }

    @discardableResult
    func startReferenceTone(frequency: Double) -> Bool {
        toneFrequency = frequency
        setReferenceFrequency(frequency)
        if managesAudioSession {
            configureAudioSession()
        }

        if toneNode == nil {
            let format = toneEngine.outputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                statusMessage = "The current audio route cannot play a reference tone."
                return false
            }
            toneNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let sampleRate = format.sampleRate
                let amp = Float(0.18)
                let twoPi = 2.0 * Double.pi

                for frame in 0..<Int(frameCount) {
                    let sample = Float(sin(self.tonePhase) * Double(amp))
                    self.tonePhase += twoPi * self.toneFrequency / sampleRate
                    if self.tonePhase >= twoPi { self.tonePhase -= twoPi }

                    for buffer in abl {
                        let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
                        ptr?[frame] = sample
                    }
                }
                return noErr
            }

            if let toneNode {
                toneEngine.attach(toneNode)
                toneEngine.connect(toneNode, to: toneEngine.mainMixerNode, format: format)
            }
        }

        do {
            if !toneEngine.isRunning {
                try toneEngine.start()
            }
            isReferenceTonePlaying = true
            statusMessage = "Playing A tone."
            return true
        } catch {
            statusMessage = L10n.f("Reference tone failed: %@", error.localizedDescription)
            return false
        }
    }

    func stopReferenceTone() {
        toneEngine.stop()
        isReferenceTonePlaying = false
    }

    func requestMicPermissionAndStart() {
        let session = AVAudioSession.sharedInstance()
        let handlePermissionResult: (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.permissionState = granted ? .granted : .denied
                if granted {
                    self.startListening()
                } else {
                    self.statusMessage = "Microphone permission is required for tuning."
                }
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                handlePermissionResult(granted)
            }
        } else {
            session.requestRecordPermission { granted in
                handlePermissionResult(granted)
            }
        }
    }

    @discardableResult
    func startListening() -> Bool {
        if managesAudioSession {
            configureAudioSession()
        }

        do {
            let input = inputEngine.inputNode
            let format = input.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                statusMessage = "The current audio input is unavailable."
                isListening = false
                return false
            }

            audioAnalyzer.reset()
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
                guard let self else { return }
                self.audioAnalyzer.submit(
                    buffer: buffer,
                    sampleRate: format.sampleRate,
                    hostSeconds: AVAudioTime.seconds(forHostTime: time.hostTime)
                ) { [weak self] result in
                    Task { @MainActor [weak self] in
                        self?.applyAnalysisResult(result)
                    }
                }
            }

            if !inputEngine.isRunning {
                try inputEngine.start()
            }
            isListening = true
            permissionState = .granted
            statusMessage = "Listening…"
            return true
        } catch {
            statusMessage = L10n.f("Tuner failed to start: %@", error.localizedDescription)
            isListening = false
            return false
        }
    }

    func stopListening() {
        inputEngine.inputNode.removeTap(onBus: 0)
        inputEngine.stop()
        audioAnalyzer.reset()
        isListening = false
        detectedFrequency = nil
        detectedNoteName = "--"
        detectedCents = 0
        inputLevel = 0
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            requestMicPermissionAndStart()
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true, options: [])
        } catch {
            statusMessage = L10n.f("Audio setup failed: %@", error.localizedDescription)
        }
    }

    private func applyAnalysisResult(_ result: TunerAnalysisResult) {
        guard isListening else { return }
        if let onInputSamples {
            onInputSamples(result.samples, result.hostSeconds)
        }
        inputLevel = result.level
        guard let frequency = result.frequency else {
            detectedFrequency = nil
            detectedNoteName = "--"
            detectedCents = 0
            return
        }
        let tuning = noteAndCents(for: frequency)
        detectedFrequency = frequency
        detectedNoteName = tuning.name
        detectedCents = tuning.cents
    }

    private func noteAndCents(for frequency: Double) -> (name: String, cents: Double) {
        let midi = 69.0 + 12.0 * log2(frequency / referenceFrequency)
        let nearest = round(midi)
        let nearestFreq = referenceFrequency * pow(2.0, (nearest - 69.0) / 12.0)
        let cents = 1200.0 * log2(frequency / nearestFreq)

        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = Int((nearest.truncatingRemainder(dividingBy: 12) + 12).truncatingRemainder(dividingBy: 12))
        let octave = Int(nearest / 12.0) - 1
        let name = "\(noteNames[noteIndex])\(octave)"

        return (name, cents)
    }

    #if DEBUG
    func applyStudioQuestFixture(
        isListening: Bool,
        noteName: String = "A4",
        cents: Double = 3
    ) {
        self.isListening = isListening
        detectedFrequency = isListening ? referenceFrequency : nil
        detectedNoteName = isListening ? noteName : "--"
        detectedCents = isListening ? cents : 0
        inputLevel = isListening ? 0.02 : 0
        permissionState = isListening ? .granted : .unknown
    }
    #endif
}
