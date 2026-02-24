import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class StudioChatViewModel: ObservableObject {
    @Published private(set) var studio: StudioInfo?
    @Published private(set) var messages: [StudioChatMessage] = []
    @Published private(set) var isLoading: Bool = false
    @Published var statusMessage: String?
    @Published var draftMessage: String = ""

    private let repository: FirebaseStudiosRepository
    private var userListener: ListenerRegistration?
    private var studioListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private var currentUID: String?
    private var currentRole: PBAccountType = .student
    private var currentDisplayName: String = ""
    private var currentAvatarID: String = "avatar_note"
    private var currentLevel: Int = 1

    init(repository: FirebaseStudiosRepository? = nil) {
        self.repository = repository ?? FirebaseStudiosRepository()
    }

    deinit {
        userListener?.remove()
        studioListener?.remove()
        messagesListener?.remove()
    }

    func start(uid: String, role: PBAccountType) {
        if currentUID == uid && currentRole == role { return }
        stop()

        currentUID = uid
        currentRole = role
        isLoading = true
        statusMessage = nil

        userListener = repository.listenToUserDocument(uid: uid) { [weak self] data in
            guard let self else { return }
            if let raw = data?["displayName"] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { self.currentDisplayName = trimmed }
            }
            if let avatar = data?["avatarID"] as? String, !avatar.isEmpty {
                self.currentAvatarID = avatar
            }
            if let level = data?["publicLevel"] as? Int {
                self.currentLevel = max(1, level)
            }

            if role == .student {
                let studioID = (data?["studentStudioId"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.attachStudioListener(studioID: studioID?.isEmpty == false ? studioID : nil)
            }
        }

        if role == .teacher {
            studioListener = repository.listenToOwnedStudio(ownerUID: uid) { [weak self] studio in
                guard let self else { return }
                self.attachStudio(studio)
            }
        }
    }

    func stop() {
        userListener?.remove()
        studioListener?.remove()
        messagesListener?.remove()
        userListener = nil
        studioListener = nil
        messagesListener = nil
        studio = nil
        messages = []
        statusMessage = nil
        draftMessage = ""
        isLoading = false
        currentUID = nil
        currentDisplayName = ""
        currentAvatarID = "avatar_note"
        currentLevel = 1
        currentRole = .student
    }

    func sendMessage() async {
        guard let uid = currentUID else { return }
        guard let studioID = studio?.id else {
            statusMessage = "Join or create a studio first."
            return
        }

        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let fallbackName = "Player \(uid.prefix(4).uppercased())"
        let senderName = currentDisplayName.isEmpty ? fallbackName : currentDisplayName

        do {
            try await repository.sendStudioMessage(
                studioID: studioID,
                senderUID: uid,
                senderName: senderName,
                senderAvatarID: currentAvatarID,
                senderLevel: currentLevel,
                rawText: text
            )
            draftMessage = ""
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func attachStudioListener(studioID: String?) {
        studioListener?.remove()
        studioListener = nil

        guard let studioID, !studioID.isEmpty else {
            attachStudio(nil)
            return
        }

        studioListener = repository.listenToStudioDocument(studioID: studioID) { [weak self] studio in
            guard let self else { return }
            self.attachStudio(studio)
        }
    }

    private func attachStudio(_ studio: StudioInfo?) {
        self.studio = studio
        self.isLoading = false

        messagesListener?.remove()
        messagesListener = nil
        messages = []

        guard let studioID = studio?.id else { return }
        messagesListener = repository.listenToStudioMessages(studioID: studioID) { [weak self] rows in
            guard let self else { return }
            self.messages = rows
        }
    }
}
