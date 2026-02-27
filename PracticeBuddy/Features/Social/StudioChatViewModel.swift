import Foundation
import Combine
import FirebaseFirestore

enum SocialChatThreadKind: String {
    case studio
    case friend
}

struct SocialChatThread: Identifiable, Equatable {
    let id: String
    let kind: SocialChatThreadKind
    let title: String
    let subtitle: String
    let studioID: String?
    let friendUID: String?
    let lastMessageText: String
    let lastMessageAt: Date
    let lastMessageSenderUID: String
    let unreadCount: Int
}

struct SocialChatMessage: Identifiable, Equatable {
    let id: String
    let senderUID: String
    let senderName: String
    let senderAvatarID: String
    let senderLevel: Int
    let text: String
    let createdAt: Date
}

@MainActor
final class StudioChatViewModel: ObservableObject {
    @Published private(set) var threads: [SocialChatThread] = []
    @Published private(set) var selectedThreadID: String?
    @Published private(set) var messages: [SocialChatMessage] = []
    @Published private(set) var friendCandidates: [StudioMemberSummary] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published var statusMessage: String?
    @Published var draftMessage: String = ""

    private let repository: FirebaseStudiosRepository
    private var userListener: ListenerRegistration?
    private var buddiesListener: ListenerRegistration?
    private var friendThreadsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private var studioDocListeners: [String: ListenerRegistration] = [:]
    private var studioLatestListeners: [String: ListenerRegistration] = [:]
    private var currentUID: String?
    private var currentDisplayName: String = ""
    private var currentAvatarID: String = "avatar_note"
    private var currentLevel: Int = 1
    private var buddyDirectory: [String: StudioMemberSummary] = [:]
    private var studioThreadsByID: [String: SocialChatThread] = [:]
    private var friendThreadsByID: [String: SocialChatThread] = [:]
    private var lastReadAtByThreadID: [String: Date] = [:]
    private var pinnedThreadIDs: Set<String> = []
    private var mutedThreadIDs: Set<String> = []
    private var hiddenThreadIDs: Set<String> = []

    init(repository: FirebaseStudiosRepository? = nil) {
        self.repository = repository ?? FirebaseStudiosRepository()
    }

    deinit {
        userListener?.remove()
        buddiesListener?.remove()
        friendThreadsListener?.remove()
        messagesListener?.remove()
        studioDocListeners.values.forEach { $0.remove() }
        studioLatestListeners.values.forEach { $0.remove() }
    }

    func start(uid: String) {
        if currentUID == uid { return }
        stop()

        currentUID = uid
        isLoading = true
        statusMessage = nil
        loadLastReadState(uid: uid)
        loadThreadState(uid: uid)

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

            let studioIDs = self.extractStudioIDs(from: data ?? [:])
            self.attachStudioListeners(studioIDs: studioIDs)
        }

        buddiesListener = repository.listenToBuddyDirectory(uid: uid) { [weak self] buddies in
            guard let self else { return }
            self.friendCandidates = buddies
            self.buddyDirectory = Dictionary(uniqueKeysWithValues: buddies.map { ($0.id, $0) })
            self.rebuildFriendThreads()
        }

        friendThreadsListener = repository.listenToFriendChatThreads(uid: uid) { [weak self] rows in
            guard let self else { return }
            self.mergeFriendThreads(rows)
        }
    }

    func stop() {
        userListener?.remove()
        buddiesListener?.remove()
        friendThreadsListener?.remove()
        messagesListener?.remove()
        studioDocListeners.values.forEach { $0.remove() }
        studioLatestListeners.values.forEach { $0.remove() }
        userListener = nil
        buddiesListener = nil
        friendThreadsListener = nil
        messagesListener = nil
        studioDocListeners = [:]
        studioLatestListeners = [:]
        threads = []
        selectedThreadID = nil
        messages = []
        friendCandidates = []
        unreadCount = 0
        statusMessage = nil
        draftMessage = ""
        isLoading = false
        currentUID = nil
        currentDisplayName = ""
        currentAvatarID = "avatar_note"
        currentLevel = 1
        buddyDirectory = [:]
        studioThreadsByID = [:]
        friendThreadsByID = [:]
        lastReadAtByThreadID = [:]
        pinnedThreadIDs = []
        mutedThreadIDs = []
        hiddenThreadIDs = []
    }

    func selectThread(_ threadID: String) {
        guard selectedThreadID != threadID else { return }
        selectedThreadID = threadID
        attachMessagesListener()
    }

    func openFriendThread(friendUID: String) {
        guard let uid = currentUID else { return }
        let threadDocID = repository.friendThreadID(uidA: uid, uidB: friendUID)
        let threadID = friendThreadKey(threadDocID)
        hiddenThreadIDs.remove(threadID)
        persistThreadState()
        if friendThreadsByID[threadID] == nil {
            let buddy = buddyDirectory[friendUID]
            friendThreadsByID[threadID] = SocialChatThread(
                id: threadID,
                kind: .friend,
                title: buddy?.displayName ?? shortUserLabel(friendUID),
                subtitle: "Friend chat",
                studioID: nil,
                friendUID: friendUID,
                lastMessageText: "",
                lastMessageAt: .distantPast,
                lastMessageSenderUID: "",
                unreadCount: 0
            )
            rebuildThreads()
        }
        selectedThreadID = threadID
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.ensureFriendThread(currentUID: uid, friendUID: friendUID)
                await MainActor.run {
                    self.attachMessagesListener()
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func markThreadReadManually(_ threadID: String) {
        markThreadRead(threadID)
    }

    func togglePin(threadID: String) {
        if pinnedThreadIDs.contains(threadID) {
            pinnedThreadIDs.remove(threadID)
        } else {
            pinnedThreadIDs.insert(threadID)
        }
        persistThreadState()
        rebuildThreads()
    }

    func toggleMute(threadID: String) {
        if mutedThreadIDs.contains(threadID) {
            mutedThreadIDs.remove(threadID)
        } else {
            mutedThreadIDs.insert(threadID)
        }
        persistThreadState()
        rebuildThreads()
    }

    func hideThreadLocally(_ threadID: String) {
        hiddenThreadIDs.insert(threadID)
        pinnedThreadIDs.remove(threadID)
        mutedThreadIDs.remove(threadID)
        persistThreadState()
        if selectedThreadID == threadID {
            selectedThreadID = nil
            messagesListener?.remove()
            messagesListener = nil
            messages = []
        }
        rebuildThreads()
    }

    func isThreadPinned(_ threadID: String) -> Bool {
        pinnedThreadIDs.contains(threadID)
    }

    func isThreadMuted(_ threadID: String) -> Bool {
        mutedThreadIDs.contains(threadID)
    }

    func sendMessage() async {
        guard let uid = currentUID else { return }
        guard let selected = selectedThread else {
            statusMessage = "Select a conversation first."
            return
        }

        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let fallbackName = "Player \(uid.prefix(4).uppercased())"
        let senderName = currentDisplayName.isEmpty ? fallbackName : currentDisplayName

        do {
            switch selected.kind {
            case .studio:
                guard let studioID = selected.studioID else {
                    statusMessage = "Invalid studio conversation."
                    return
                }
                try await repository.sendStudioMessage(
                    studioID: studioID,
                    senderUID: uid,
                    senderName: senderName,
                    senderAvatarID: currentAvatarID,
                    senderLevel: currentLevel,
                    rawText: text
                )
            case .friend:
                guard let friendUID = selected.friendUID else {
                    statusMessage = "Invalid friend conversation."
                    return
                }
                try await repository.sendFriendMessage(
                    senderUID: uid,
                    recipientUID: friendUID,
                    senderName: senderName,
                    senderAvatarID: currentAvatarID,
                    senderLevel: currentLevel,
                    rawText: text
                )
            }
            draftMessage = ""
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var selectedThread: SocialChatThread? {
        guard let selectedThreadID else { return nil }
        return threads.first(where: { $0.id == selectedThreadID })
    }

    private func attachStudioListeners(studioIDs: [String]) {
        let fresh = Set(studioIDs.filter { !$0.isEmpty })
        let existing = Set(studioDocListeners.keys)

        let toRemove = existing.subtracting(fresh)
        for studioID in toRemove {
            studioDocListeners[studioID]?.remove()
            studioLatestListeners[studioID]?.remove()
            studioDocListeners[studioID] = nil
            studioLatestListeners[studioID] = nil
            studioThreadsByID[studioThreadKey(studioID)] = nil
        }

        let toAdd = fresh.subtracting(existing)
        for studioID in toAdd {
            studioDocListeners[studioID] = repository.listenToStudioDocument(studioID: studioID) { [weak self] studio in
                guard let self else { return }
                let threadID = self.studioThreadKey(studioID)
                let current = self.studioThreadsByID[threadID]
                let title = studio?.name ?? "Studio \(studioID.prefix(4).uppercased())"
                self.studioThreadsByID[threadID] = SocialChatThread(
                    id: threadID,
                    kind: .studio,
                    title: title,
                    subtitle: "Studio chat",
                    studioID: studioID,
                    friendUID: nil,
                    lastMessageText: current?.lastMessageText ?? "",
                    lastMessageAt: current?.lastMessageAt ?? .distantPast,
                    lastMessageSenderUID: current?.lastMessageSenderUID ?? "",
                    unreadCount: current?.unreadCount ?? 0
                )
                self.rebuildThreads()
            }

            studioLatestListeners[studioID] = repository.listenToStudioLatestMessage(studioID: studioID) { [weak self] message in
                guard let self else { return }
                let threadID = self.studioThreadKey(studioID)
                let current = self.studioThreadsByID[threadID]
                let title = current?.title ?? "Studio \(studioID.prefix(4).uppercased())"
                let lastText = message?.text ?? current?.lastMessageText ?? ""
                let lastAt = message?.createdAt ?? current?.lastMessageAt ?? .distantPast
                let senderUID = message?.senderUID ?? current?.lastMessageSenderUID ?? ""
                self.studioThreadsByID[threadID] = SocialChatThread(
                    id: threadID,
                    kind: .studio,
                    title: title,
                    subtitle: "Studio chat",
                    studioID: studioID,
                    friendUID: nil,
                    lastMessageText: lastText,
                    lastMessageAt: lastAt,
                    lastMessageSenderUID: senderUID,
                    unreadCount: 0
                )
                self.rebuildThreads()
            }
        }

        isLoading = false
        rebuildThreads()
    }

    private func mergeFriendThreads(_ rows: [FriendChatThread]) {
        var merged: [String: SocialChatThread] = friendThreadsByID
        let liveIDs = Set(rows.map { friendThreadKey($0.id) })
        for key in merged.keys where !liveIDs.contains(key) && merged[key]?.lastMessageAt != .distantPast {
            merged[key] = nil
        }
        for row in rows {
            let key = friendThreadKey(row.id)
            let friendUID = row.participants.first(where: { $0 != currentUID }) ?? ""
            let buddy = buddyDirectory[friendUID]
            merged[key] = SocialChatThread(
                id: key,
                kind: .friend,
                title: buddy?.displayName ?? shortUserLabel(friendUID),
                subtitle: "Friend chat",
                studioID: nil,
                friendUID: friendUID,
                lastMessageText: row.lastMessageText,
                lastMessageAt: row.lastMessageAt,
                lastMessageSenderUID: row.lastMessageSenderUID,
                unreadCount: 0
            )
        }
        friendThreadsByID = merged
        rebuildFriendThreads()
        rebuildThreads()
    }

    private func rebuildFriendThreads() {
        friendThreadsByID = friendThreadsByID.mapValues { thread in
            guard thread.kind == .friend,
                  let friendUID = thread.friendUID else { return thread }
            let buddy = buddyDirectory[friendUID]
            return SocialChatThread(
                id: thread.id,
                kind: .friend,
                title: buddy?.displayName ?? thread.title,
                subtitle: "Friend chat",
                studioID: nil,
                friendUID: friendUID,
                lastMessageText: thread.lastMessageText,
                lastMessageAt: thread.lastMessageAt,
                lastMessageSenderUID: thread.lastMessageSenderUID,
                unreadCount: thread.unreadCount
            )
        }
    }

    private func rebuildThreads() {
        guard currentUID != nil else { return }
        let all = Array(studioThreadsByID.values) + Array(friendThreadsByID.values)
        let withUnread = all
            .filter { !hiddenThreadIDs.contains($0.id) }
            .map { thread in
            let unread = unreadCount(for: thread)
            return SocialChatThread(
                id: thread.id,
                kind: thread.kind,
                title: thread.title,
                subtitle: thread.subtitle,
                studioID: thread.studioID,
                friendUID: thread.friendUID,
                lastMessageText: thread.lastMessageText,
                lastMessageAt: thread.lastMessageAt,
                lastMessageSenderUID: thread.lastMessageSenderUID,
                unreadCount: unread
            )
        }
        threads = withUnread.sorted { lhs, rhs in
            let leftPinned = pinnedThreadIDs.contains(lhs.id)
            let rightPinned = pinnedThreadIDs.contains(rhs.id)
            if leftPinned != rightPinned { return leftPinned && !rightPinned }
            if lhs.lastMessageAt != rhs.lastMessageAt { return lhs.lastMessageAt > rhs.lastMessageAt }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        unreadCount = threads.reduce(0) { $0 + $1.unreadCount }

        if let selectedThreadID, threads.contains(where: { $0.id == selectedThreadID }) {
            // keep selection
        } else {
            selectedThreadID = threads.first?.id
            attachMessagesListener()
        }
    }

    private func attachMessagesListener() {
        messagesListener?.remove()
        messagesListener = nil
        messages = []
        guard let selected = selectedThread else { return }

        switch selected.kind {
        case .studio:
            guard let studioID = selected.studioID else { return }
            messagesListener = repository.listenToStudioMessages(studioID: studioID) { [weak self] rows in
                guard let self else { return }
                self.messages = rows.map {
                    SocialChatMessage(
                        id: $0.id,
                        senderUID: $0.senderUID,
                        senderName: $0.senderName,
                        senderAvatarID: $0.senderAvatarID,
                        senderLevel: $0.senderLevel,
                        text: $0.text,
                        createdAt: $0.createdAt
                    )
                }
                self.markThreadRead(selected.id)
            }
        case .friend:
            guard let uid = currentUID, let friendUID = selected.friendUID else { return }
            let threadDocID = repository.friendThreadID(uidA: uid, uidB: friendUID)
            messagesListener = repository.listenToFriendMessages(threadID: threadDocID) { [weak self] rows in
                guard let self else { return }
                self.messages = rows.map {
                    SocialChatMessage(
                        id: $0.id,
                        senderUID: $0.senderUID,
                        senderName: $0.senderName,
                        senderAvatarID: $0.senderAvatarID,
                        senderLevel: $0.senderLevel,
                        text: $0.text,
                        createdAt: $0.createdAt
                    )
                }
                self.markThreadRead(selected.id)
            }
        }
    }

    private func extractStudioIDs(from data: [String: Any]) -> [String] {
        let teacherSingle = (data["teacherStudioId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let studentSingle = (data["studentStudioId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacherMany = ((data["teacherStudioIds"] as? [String]) ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let studentMany = ((data["studentStudioIds"] as? [String]) ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Array(Set(([teacherSingle, studentSingle].compactMap { $0 }) + teacherMany + studentMany).filter { !$0.isEmpty })
    }

    private func unreadCount(for thread: SocialChatThread) -> Int {
        if mutedThreadIDs.contains(thread.id) { return 0 }
        guard let uid = currentUID else { return 0 }
        guard thread.lastMessageAt > .distantPast else { return 0 }
        guard thread.lastMessageSenderUID != uid else { return 0 }
        let lastRead = lastReadAtByThreadID[thread.id] ?? .distantPast
        return thread.lastMessageAt > lastRead ? 1 : 0
    }

    private func markThreadRead(_ threadID: String) {
        lastReadAtByThreadID[threadID] = Date()
        persistLastReadState()
        rebuildThreads()
    }

    private func studioThreadKey(_ studioID: String) -> String {
        "studio:\(studioID)"
    }

    private func friendThreadKey(_ threadID: String) -> String {
        "friend:\(threadID)"
    }

    private func shortUserLabel(_ uid: String) -> String {
        guard !uid.isEmpty else { return "Friend" }
        return uid.count > 8 ? "\(uid.prefix(8))…" : uid
    }

    private func storageKey(for uid: String) -> String {
        "pb.social.chat.lastRead.\(uid)"
    }

    private func pinStorageKey(for uid: String) -> String {
        "pb.social.chat.pinned.\(uid)"
    }

    private func muteStorageKey(for uid: String) -> String {
        "pb.social.chat.muted.\(uid)"
    }

    private func hiddenStorageKey(for uid: String) -> String {
        "pb.social.chat.hidden.\(uid)"
    }

    private func loadLastReadState(uid: String) {
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: uid)),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            lastReadAtByThreadID = [:]
            return
        }
        lastReadAtByThreadID = decoded
    }

    private func persistLastReadState() {
        guard let uid = currentUID,
              let data = try? JSONEncoder().encode(lastReadAtByThreadID) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(for: uid))
    }

    private func loadThreadState(uid: String) {
        let defaults = UserDefaults.standard
        pinnedThreadIDs = Set(defaults.stringArray(forKey: pinStorageKey(for: uid)) ?? [])
        mutedThreadIDs = Set(defaults.stringArray(forKey: muteStorageKey(for: uid)) ?? [])
        hiddenThreadIDs = Set(defaults.stringArray(forKey: hiddenStorageKey(for: uid)) ?? [])
    }

    private func persistThreadState() {
        guard let uid = currentUID else { return }
        let defaults = UserDefaults.standard
        defaults.set(Array(pinnedThreadIDs), forKey: pinStorageKey(for: uid))
        defaults.set(Array(mutedThreadIDs), forKey: muteStorageKey(for: uid))
        defaults.set(Array(hiddenThreadIDs), forKey: hiddenStorageKey(for: uid))
    }
}
