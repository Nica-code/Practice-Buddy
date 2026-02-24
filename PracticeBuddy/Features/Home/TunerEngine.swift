import Foundation
import AVFoundation
import Combine

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

    private let inputEngine = AVAudioEngine()
    private let toneEngine = AVAudioEngine()
    private var toneNode: AVAudioSourceNode?
    private var tonePhase: Double = 0
    private var toneFrequency: Double = 440
    private var sampleCounter = 0

    func toggleReferenceTone(frequency: Double) {
        if isReferenceTonePlaying {
            stopReferenceTone()
        } else {
            startReferenceTone(frequency: frequency)
        }
    }

    func startReferenceTone(frequency: Double) {
        toneFrequency = frequency
        configureAudioSession()

        if toneNode == nil {
            let format = toneEngine.outputNode.outputFormat(forBus: 0)
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
        } catch {
            statusMessage = L10n.f("Reference tone failed: %@", error.localizedDescription)
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

    func startListening() {
        configureAudioSession()

        do {
            let input = inputEngine.inputNode
            let format = input.inputFormat(forBus: 0)

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.processInputBuffer(buffer, sampleRate: format.sampleRate)
            }

            if !inputEngine.isRunning {
                try inputEngine.start()
            }
            isListening = true
            permissionState = .granted
            statusMessage = "Listening…"
        } catch {
            statusMessage = L10n.f("Tuner failed to start: %@", error.localizedDescription)
            isListening = false
        }
    }

    func stopListening() {
        inputEngine.inputNode.removeTap(onBus: 0)
        inputEngine.stop()
        isListening = false
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

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let channel = channelData[0]
        let count = Int(buffer.frameLength)
        if count < 512 { return }

        sampleCounter += 1
        if sampleCounter % 2 != 0 { return } // lower CPU

        let samples = Array(UnsafeBufferPointer(start: channel, count: count))

        var rms: Float = 0
        for s in samples { rms += s * s }
        rms = sqrt(rms / Float(samples.count))
        let level = Double(rms)

        Task { @MainActor in
            self.inputLevel = level
        }

        guard level > 0.003 else {
            Task { @MainActor in
                self.detectedFrequency = nil
                self.detectedNoteName = "--"
                self.detectedCents = 0
            }
            return
        }

        guard let frequency = detectFundamentalFrequency(samples: samples, sampleRate: sampleRate) else { return }
        let tuning = noteAndCents(for: frequency)

        Task { @MainActor in
            self.detectedFrequency = frequency
            self.detectedNoteName = tuning.name
            self.detectedCents = tuning.cents
        }
    }

    private func detectFundamentalFrequency(samples: [Float], sampleRate: Double) -> Double? {
        let minFrequency = 80.0
        let maxFrequency = 1200.0
        let minLag = max(2, Int(sampleRate / maxFrequency))
        let maxLag = min(samples.count - 2, Int(sampleRate / minFrequency))
        guard minLag < maxLag else { return nil }

        var bestLag = minLag
        var bestCorr: Double = -.infinity

        for lag in minLag...maxLag {
            var sum: Double = 0
            var energyA: Double = 0
            var energyB: Double = 0
            let end = samples.count - lag
            if end <= 0 { continue }

            var i = 0
            while i < end {
                let a = Double(samples[i])
                let b = Double(samples[i + lag])
                sum += a * b
                energyA += a * a
                energyB += b * b
                i += 1
            }

            let denom = sqrt(energyA * energyB)
            if denom <= 0 { continue }
            let corr = sum / denom

            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }

        if bestCorr < 0.15 { return nil }

        let lag0 = Double(bestLag)
        let c1 = normalizedCorrelation(samples: samples, lag: bestLag - 1)
        let c2 = normalizedCorrelation(samples: samples, lag: bestLag)
        let c3 = normalizedCorrelation(samples: samples, lag: bestLag + 1)
        let denom = (c1 - 2 * c2 + c3)

        var refinedLag = lag0
        if abs(denom) > 1e-9 {
            refinedLag = lag0 + 0.5 * (c1 - c3) / denom
        }

        guard refinedLag > 0 else { return nil }
        return sampleRate / refinedLag
    }

    private func normalizedCorrelation(samples: [Float], lag: Int) -> Double {
        if lag <= 0 || lag >= samples.count { return 0 }
        let end = samples.count - lag
        if end <= 0 { return 0 }

        var sum: Double = 0
        var energyA: Double = 0
        var energyB: Double = 0
        for i in 0..<end {
            let a = Double(samples[i])
            let b = Double(samples[i + lag])
            sum += a * b
            energyA += a * a
            energyB += b * b
        }

        let denom = sqrt(energyA * energyB)
        if denom <= 0 { return 0 }
        return sum / denom
    }

    private func noteAndCents(for frequency: Double) -> (name: String, cents: Double) {
        let midi = 69.0 + 12.0 * log2(frequency / 440.0)
        let nearest = round(midi)
        let nearestFreq = 440.0 * pow(2.0, (nearest - 69.0) / 12.0)
        let cents = 1200.0 * log2(frequency / nearestFreq)

        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = Int((nearest.truncatingRemainder(dividingBy: 12) + 12).truncatingRemainder(dividingBy: 12))
        let octave = Int(nearest / 12.0) - 1
        let name = "\(noteNames[noteIndex])\(octave)"

        return (name, cents)
    }
}
