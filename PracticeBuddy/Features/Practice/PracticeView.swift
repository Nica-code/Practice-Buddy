import SwiftUI
import Combine

struct PracticeView: View {
    @EnvironmentObject private var store: SessionStore

    // Persisted state so you can leave and come back ("resume where you left off")
    @AppStorage("pb.practice.accumulatedSeconds") private var accumulatedSeconds: Int = 0
    @AppStorage("pb.practice.startEpoch") private var startEpoch: Double = 0
    @AppStorage("pb.practice.isRunning") private var isRunning: Bool = false

    @State private var now = Date()
    @State private var timerCancellable: AnyCancellable? = nil

    @State private var showSaveSheet = false
    @State private var notes: String = ""
    @State private var showSavedAlert = false

    private enum Constants {
        static let tickSeconds: TimeInterval = 1
    }

    private var startDate: Date? {
        startEpoch > 0 ? Date(timeIntervalSince1970: startEpoch) : nil
    }

    private var currentElapsedSeconds: Int {
        if isRunning, let startDate {
            let running = Int(now.timeIntervalSince(startDate))
            return accumulatedSeconds + max(0, running)
        } else {
            return accumulatedSeconds
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(DurationFormatter.string(from: currentElapsedSeconds))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 12) {
                Button(isRunning ? "Pause" : (currentElapsedSeconds == 0 ? "Start" : "Resume")) {
                    toggleStartPause()
                }
                .buttonStyle(.borderedProminent)

                Button("Stop") {
                    stopTapped()
                }
                .buttonStyle(.bordered)
                .disabled(currentElapsedSeconds == 0)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Practice")
        .onAppear {
            if isRunning { startTicker() }
        }
        .onChange(of: isRunning) { _, running in
            if running {
                now = Date()
                startTicker()
            } else {
                stopTicker()
            }
        }
        .onDisappear {
            stopTicker()
        }
        .sheet(isPresented: $showSaveSheet) {
            saveSheet
        }
        .alert("Saved!", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your practice session was added to History.")
        }
    }

    // MARK: - Ticker control

    private func startTicker() {
        guard timerCancellable == nil else { return }
        timerCancellable = Timer.publish(every: Constants.tickSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                now = Date()
            }
    }

    private func stopTicker() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private var saveSheet: some View {
        PracticeSaveSheetView(
            currentElapsedSeconds: currentElapsedSeconds,
            notes: $notes,
            onDiscard: {
                resetSession()
                showSaveSheet = false
            },
            onSave: {
                store.addSession(
                    date: Date(),
                    durationSeconds: currentElapsedSeconds,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                resetSession()
                showSaveSheet = false
                showSavedAlert = true
            }
        )
    }

    private func toggleStartPause() {
        if isRunning {
            accumulatedSeconds = currentElapsedSeconds
            isRunning = false
            startEpoch = 0
        } else {
            startEpoch = Date().timeIntervalSince1970
            isRunning = true
        }
    }

    private func stopTapped() {
        if isRunning {
            accumulatedSeconds = currentElapsedSeconds
            isRunning = false
            startEpoch = 0
        }
        showSaveSheet = true
    }

    private func resetSession() {
        accumulatedSeconds = 0
        startEpoch = 0
        isRunning = false
        notes = ""
    }
}
