import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class WarmupOfWeekManager: ObservableObject {
    @Published private(set) var warmup: StudioWarmupOfWeek?
    @Published private(set) var statusMessage: String?

    private let repository: FirebaseStudiosRepository
    private var userListener: ListenerRegistration?
    private var warmupListener: ListenerRegistration?
    private var individualWarmupListener: ListenerRegistration?
    private var studioWarmup: StudioWarmupOfWeek?
    private var individualWarmup: StudioWarmupOfWeek?
    private var currentUID: String?
    private var currentStudioID: String?
    private var currentAccountType: PBAccountType = .student
    private var currentIsPro: Bool = false

    init(repository: FirebaseStudiosRepository? = nil) {
        self.repository = repository ?? FirebaseStudiosRepository()
    }

    func start(uid: String?, accountType: PBAccountType, isPro: Bool) {
        if currentUID == uid, currentAccountType == accountType, currentIsPro == isPro, userListener != nil { return }
        stop()
        currentUID = uid
        currentAccountType = accountType
        currentIsPro = isPro
        guard let uid else { return }

        userListener = repository.listenToUserDocument(uid: uid) { [weak self] data in
            guard let self else { return }
            let key = accountType == .teacher ? "teacherStudioId" : "studentStudioId"
            let raw = (data?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sid = (raw?.isEmpty == false) ? raw : nil
            self.attachWarmup(studioID: sid)
        }
    }

    func stop() {
        userListener?.remove()
        warmupListener?.remove()
        individualWarmupListener?.remove()
        userListener = nil
        warmupListener = nil
        individualWarmupListener = nil
        studioWarmup = nil
        individualWarmup = nil
        warmup = nil
        statusMessage = nil
        currentUID = nil
        currentStudioID = nil
    }

    func pauseRealtime() {
        userListener?.remove()
        warmupListener?.remove()
        individualWarmupListener?.remove()
        userListener = nil
        warmupListener = nil
        individualWarmupListener = nil
    }

    func pushWarmupOfWeek(
        title: String,
        instrument: String,
        focus: String,
        totalMinutes: Int,
        steps: [String]
    ) async {
        guard currentIsPro, currentAccountType == .teacher else {
            statusMessage = "Warm-up push is available for Pro Teacher accounts."
            return
        }
        guard let uid = currentUID, let studioID = currentStudioID else {
            statusMessage = "No studio found."
            return
        }
        do {
            try await repository.saveWarmupOfWeek(
                studioID: studioID,
                teacherUID: uid,
                title: title,
                instrument: instrument,
                focus: focus,
                totalMinutes: totalMinutes,
                steps: steps
            )
            statusMessage = "Warm-up of the week published."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func attachWarmup(studioID: String?) {
        warmupListener?.remove()
        individualWarmupListener?.remove()
        warmupListener = nil
        individualWarmupListener = nil
        studioWarmup = nil
        individualWarmup = nil
        warmup = nil
        currentStudioID = studioID
        guard let studioID else { return }

        warmupListener = repository.listenToWarmupOfWeek(studioID: studioID) { [weak self] warmup in
            guard let self else { return }
            self.studioWarmup = warmup
            self.resolveWarmupSelection()
        }

        if currentAccountType == .student, let uid = currentUID {
            let docID = "individual_\(uid)"
            individualWarmupListener = repository.listenToWarmupDocument(studioID: studioID, documentID: docID) { [weak self] warmup in
                guard let self else { return }
                self.individualWarmup = warmup
                self.resolveWarmupSelection()
            }
        }
    }

    private func resolveWarmupSelection() {
        if currentAccountType == .student {
            warmup = individualWarmup ?? studioWarmup
        } else {
            warmup = studioWarmup
        }
    }
}
