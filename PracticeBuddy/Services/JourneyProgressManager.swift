import Foundation
import Combine
import os
import FirebaseFirestore
import FirebaseAuth

struct JourneyQuestRow: Identifiable, Equatable {
    let id: String
    let title: String
    let progress: Int
    let target: Int
    let rewardTokens: Int
    let subtitle: String

    var isCompleted: Bool { progress >= target }
}

struct JourneyRewardItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let costTokens: Int
    let category: JourneyRewardCategory
    let slot: JourneyRewardSlot
    let isOwned: Bool
    let isEquipped: Bool
}

enum JourneyRewardCategory: String, CaseIterable, Identifiable {
    case cosmetics
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cosmetics: return "Cosmetics"
        case .tools: return "Tools"
        }
    }
}

enum JourneyRewardSlot: String, CaseIterable {
    case profileFrame = "profile_frame"
    case profileBanner = "profile_banner"
    case profileGlow = "profile_glow"
    case confettiStyle = "confetti_style"
    case duelIntroCard = "duel_intro_card"
    case duelFinisherFX = "duel_finisher_fx"
    case sessionCardSkin = "session_card_skin"
    case metronomePack = "metronome_pack"
    case studioDecoration = "studio_decoration"
}

enum JourneyQuestPeriod: String {
    case daily
    case weekly
}

enum JourneyQuestRewardStatus: Equatable {
    case locked
    case claimable
    case claimed
}

enum DuelQuestEvent: String, CaseIterable {
    case queueJoined = "queue_joined"
    case inviteSent = "invite_sent"
    case acceptEntered = "accept_entered"
    case takeSubmitted = "take_submitted"
    case highScoreSubmission = "high_score_submission"
    case tempoQualifiedSubmission = "tempo_qualified_submission"
}

private enum DuelQuestNotification {
    static let telemetryDidChange = Notification.Name("pb.duelQuestTelemetryDidChange")
}

private struct QuestDefinition: Equatable {
    enum Metric: Equatable {
        case dailyEvent(DuelQuestEvent)
        case weeklyEvent(DuelQuestEvent)
        case weeklyAnyEvent([DuelQuestEvent])
        case dailyWins
        case weeklyWins
        case weeklyRatingGain
        case weeklyLeagueUps
    }

    let id: String
    let title: String
    let subtitle: String
    let target: Int
    let rewardTokens: Int
    let metric: Metric
    let category: String
}

private struct QuestContext {
    let dayKey: String
    let weekKey: String
    let dailyEventCounts: [DuelQuestEvent: Int]
    let weeklyEventCounts: [DuelQuestEvent: Int]
    let dailyWins: Int
    let weeklyWins: Int
    let weeklyRatingGain: Int
    let weeklyLeagueUps: Int
}

private struct WeeklyQuestPlan: Codable {
    let weekKey: String
    let questIDs: [String]
}

private final class DuelQuestTelemetryStore {
    static let shared = DuelQuestTelemetryStore()

    private enum Keys {
        static let dayCounters = "pb.journey.duelTelemetry.dayCounters"
        static let weekCounters = "pb.journey.duelTelemetry.weekCounters"
    }

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    func record(_ event: DuelQuestEvent, on dayKey: String, weekKey: String) {
        lock.lock()
        var dayMap = readMap(for: Keys.dayCounters)
        let dayCounterKey = "\(dayKey)|\(event.rawValue)"
        dayMap[dayCounterKey, default: 0] += 1
        writeMap(dayMap, for: Keys.dayCounters)

        var weekMap = readMap(for: Keys.weekCounters)
        let weekCounterKey = "\(weekKey)|\(event.rawValue)"
        weekMap[weekCounterKey, default: 0] += 1
        writeMap(weekMap, for: Keys.weekCounters)
        lock.unlock()

        NotificationCenter.default.post(name: DuelQuestNotification.telemetryDidChange, object: nil)
    }

    func dailyCount(for event: DuelQuestEvent, dayKey: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let map = readMap(for: Keys.dayCounters)
        return max(0, map["\(dayKey)|\(event.rawValue)"] ?? 0)
    }

    func weeklyCount(for event: DuelQuestEvent, weekKey: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let map = readMap(for: Keys.weekCounters)
        return max(0, map["\(weekKey)|\(event.rawValue)"] ?? 0)
    }

    private func readMap(for key: String) -> [String: Int] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func writeMap(_ map: [String: Int], for key: String) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class JourneyProgressManager: ObservableObject {
    private static let starterRoomDecorationIDs: Set<String> = [
        "room_decoration_plant"
    ]

    private enum Keys {
        static let seeded = "pb.journey.seeded"
        static let totalXP = "pb.journey.totalXP"
        static let processedSessionIDs = "pb.journey.processedSessionIDs"
        static let xpLedgerByDay = "pb.journey.xpLedgerByDay"
        static let tokenBalance = "pb.journey.tokenBalance"
        static let ownedAvatarIDs = "pb.journey.ownedAvatarIDs"
        static let claimedQuestRewardKeys = "pb.journey.claimedQuestRewardKeys"
        static let ownedRewardIDs = "pb.journey.ownedRewardIDs"
        static let equippedRewardBySlot = "pb.journey.equippedRewardBySlot"
        static let weeklyQuestPlan = "pb.journey.weeklyQuestPlan"
        static let questSeedSalt = "pb.journey.questSeedSalt"
        static let duelDailyBaselineDay = "pb.journey.duelBaseline.day.key"
        static let duelDailyBaselineWins = "pb.journey.duelBaseline.day.wins"
        static let duelDailyBaselineRating = "pb.journey.duelBaseline.day.rating"
        static let duelWeeklyBaselineWeek = "pb.journey.duelBaseline.week.key"
        static let duelWeeklyBaselineWins = "pb.journey.duelBaseline.week.wins"
        static let duelWeeklyBaselineRating = "pb.journey.duelBaseline.week.rating"
        static let duelWeeklyBaselineLeagueRank = "pb.journey.duelBaseline.week.leagueRank"
    }

    private enum InventoryKeys {
        static let metronomeSoundStyleOverride = "pb.inventory.metronome.soundStyleOverride"
        static let confettiStyle = "pb.inventory.confetti.style"
        static let cloudOwnedRewardIDs = "inventoryOwnedRewardIDs"
        static let cloudEquippedRewardBySlot = "inventoryEquippedRewardBySlot"
        static let cloudUpdatedAt = "inventoryUpdatedAt"
        static let cloudTokenBalance = "journeyTokenBalance"
        static let cloudOwnedAvatarIDs = "inventoryOwnedAvatarIDs"
        static let cloudClaimedQuestRewardKeys = "journeyClaimedQuestRewardKeys"
    }

    @Published private(set) var totalXP: Int
    @Published private(set) var level: Int = 1
    @Published private(set) var xpIntoLevel: Int = 0
    @Published private(set) var xpForNextLevel: Int = 60
    @Published private(set) var xpToNextLevel: Int = 60
    @Published private(set) var todayXP: Int = 0
    @Published private(set) var dailyQuests: [JourneyQuestRow] = []
    @Published private(set) var weeklyQuests: [JourneyQuestRow] = []
    @Published private(set) var tokenBalance: Int = 0
    @Published private(set) var ownedAvatarIDs: Set<String> = []
    @Published private(set) var rewards: [JourneyRewardItem] = []
    @Published private(set) var isEconomyOperationInProgress: Bool = false

    private var processedSessionIDs: Set<UUID> = []
    private var xpLedgerByDay: [String: Int] = [:]
    private var claimedQuestRewardKeys: Set<String> = []
    private var ownedRewardIDs: Set<String> = []
    private var equippedRewardBySlot: [String: String] = [:]
    private var lastSessions: [PracticeSessionModel] = []
    private var latestDuelRating: Int = 0
    private var latestDuelWins: Int = 0
    private var latestDuelLosses: Int = 0
    private var latestDuelDraws: Int = 0
    private var telemetryCancellable: AnyCancellable?
    private var inventoryListener: ListenerRegistration?
    private var inventoryLinkedUID: String?
    private var isApplyingRemoteInventory = false
    private var economyOperationKeysInFlight: Set<String> = []
    private let defaults = UserDefaults.standard
    private let db = Firestore.firestore()
    private let isoDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    init() {
        totalXP = defaults.integer(forKey: Keys.totalXP)
        loadProcessedIDs()
        loadLedger()
        loadClaimedQuestRewards()
        loadOwnedAvatars()
        loadOwnedRewards()
        loadEquippedRewards()
        tokenBalance = max(0, defaults.integer(forKey: Keys.tokenBalance))
        recalculateLevel()
        todayXP = xpLedgerByDay[dayKey(for: Date())] ?? 0
        refreshRewards()
        telemetryCancellable = NotificationCenter.default.publisher(for: DuelQuestNotification.telemetryDidChange)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateQuestProgress(from: self.lastSessions)
            }
        updateQuestProgress(from: [])
    }

    deinit {
        inventoryListener?.remove()
        telemetryCancellable?.cancel()
    }

    func handleSessionSnapshot(_ sessions: [PracticeSessionModel]) {
        lastSessions = sessions
        if !defaults.bool(forKey: Keys.seeded) {
            seedFromExistingSessions(sessions)
            defaults.set(true, forKey: Keys.seeded)
        } else {
            awardXPForNewSessions(sessions)
        }
        updateQuestProgress(from: sessions)
    }

    func handleDuelSnapshot(rating: Int, wins: Int, losses: Int, draws: Int) {
        let nextRating = max(0, rating)
        let nextWins = max(0, wins)
        let nextLosses = max(0, losses)
        let nextDraws = max(0, draws)
        let changed =
            latestDuelRating != nextRating ||
            latestDuelWins != nextWins ||
            latestDuelLosses != nextLosses ||
            latestDuelDraws != nextDraws
        guard changed else { return }

        latestDuelRating = nextRating
        latestDuelWins = nextWins
        latestDuelLosses = nextLosses
        latestDuelDraws = nextDraws
        updateQuestProgress(from: lastSessions)
    }

    func recordDuelEvent(_ event: DuelQuestEvent) {
        let now = Date()
        DuelQuestTelemetryStore.shared.record(
            event,
            on: dayKey(for: now),
            weekKey: questPeriodKey(.weekly, for: now)
        )
    }

    func questRewardStatus(for quest: JourneyQuestRow, period: JourneyQuestPeriod) -> JourneyQuestRewardStatus {
        guard quest.isCompleted else { return .locked }
        if claimedQuestRewardKeys.contains(questRewardClaimKey(for: quest.id, period: period, at: Date())) {
            return .claimed
        }
        return .claimable
    }

    func featuredQuestRewardStatus(
        questID: String,
        isComplete: Bool
    ) -> JourneyQuestRewardStatus {
        guard isComplete else { return .locked }
        return claimedQuestRewardKeys.contains("featured:\(questID)") ? .claimed : .claimable
    }

    @discardableResult
    func claimFeaturedQuestReward(questID: String, rewardTokens: Int) async -> Bool {
        let normalizedID = questID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, rewardTokens > 0 else { return false }
        let claimKey = "featured:\(normalizedID)"
        guard !claimedQuestRewardKeys.contains(claimKey) else { return false }
        guard beginEconomyOperation("featuredQuest:\(normalizedID)") else { return false }
        defer { endEconomyOperation("featuredQuest:\(normalizedID)") }

        if let uid = inventoryLinkedUID {
            return await claimQuestRewardCloud(
                uid: uid,
                claimKey: claimKey,
                rewardTokens: rewardTokens
            )
        }
        return claimQuestRewardLocal(claimKey: claimKey, rewardTokens: rewardTokens)
    }

    @discardableResult
    func claimQuestReward(for quest: JourneyQuestRow, period: JourneyQuestPeriod) async -> Bool {
        guard questRewardStatus(for: quest, period: period) == .claimable else { return false }

        let claimKey = questRewardClaimKey(for: quest.id, period: period, at: Date())
        guard beginEconomyOperation("quest:\(claimKey)") else { return false }
        defer { endEconomyOperation("quest:\(claimKey)") }
        if let uid = inventoryLinkedUID {
            let didClaim = await claimQuestRewardCloud(
                uid: uid,
                claimKey: claimKey,
                rewardTokens: max(0, quest.rewardTokens)
            )
            return didClaim
        }

        return claimQuestRewardLocal(claimKey: claimKey, rewardTokens: max(0, quest.rewardTokens))
    }

    @discardableResult
    func claimDuelAdReward(challengeID: String, rewardTokens: Int) async -> Bool {
        let normalizedID = challengeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return false }
        let normalizedReward = max(0, rewardTokens)
        guard normalizedReward > 0 else { return false }

        let claimKey = "ad:duel:\(normalizedID)"
        guard beginEconomyOperation("adReward:\(normalizedID)") else { return false }
        defer { endEconomyOperation("adReward:\(normalizedID)") }

        if let uid = inventoryLinkedUID {
            let didClaim = await claimQuestRewardCloud(
                uid: uid,
                claimKey: claimKey,
                rewardTokens: normalizedReward
            )
            return didClaim
        }

        return claimQuestRewardLocal(claimKey: claimKey, rewardTokens: normalizedReward)
    }

    @discardableResult
    func claimProDailyCosmeticAllowance(rewardTokens: Int = 5) async -> Bool {
        guard rewardTokens > 0 else { return false }
        let claimKey = "proAllowance:\(dayKey(for: Date()))"
        guard !claimedQuestRewardKeys.contains(claimKey) else { return false }
        guard beginEconomyOperation(claimKey) else { return false }
        defer { endEconomyOperation(claimKey) }

        if let uid = inventoryLinkedUID {
            return await claimQuestRewardCloud(
                uid: uid,
                claimKey: claimKey,
                rewardTokens: rewardTokens
            )
        }
        return claimQuestRewardLocal(claimKey: claimKey, rewardTokens: rewardTokens)
    }

    @discardableResult
    func claimRewardItem(id: String) async -> Bool {
        guard let item = baseRewards.first(where: { $0.id == id }) else { return false }
        guard beginEconomyOperation("claimReward:\(id)") else { return false }
        defer { endEconomyOperation("claimReward:\(id)") }

        if let uid = inventoryLinkedUID {
            let didClaim = await claimRewardItemCloud(uid: uid, item: item)
            return didClaim
        }

        return claimRewardItemLocal(id: id)
    }

    @discardableResult
    func equipRewardItem(id: String) async -> Bool {
        guard let item = baseRewards.first(where: { $0.id == id }) else {
            return false
        }
        guard beginEconomyOperation("equip:\(id)") else { return false }
        defer { endEconomyOperation("equip:\(id)") }
        if let uid = inventoryLinkedUID {
            return await equipRewardItemCloud(uid: uid, item: item)
        }
        return equipRewardItemLocal(id: id)
    }

    @discardableResult
    func unequipReward(slot: JourneyRewardSlot) async -> Bool {
        guard beginEconomyOperation("unequip:\(slot.rawValue)") else { return false }
        defer { endEconomyOperation("unequip:\(slot.rawValue)") }
        if let uid = inventoryLinkedUID {
            return await unequipRewardCloud(uid: uid, slot: slot)
        }
        return unequipRewardLocal(slot: slot)
    }

    func ownedRewards(in category: JourneyRewardCategory) -> [JourneyRewardItem] {
        rewards.filter { $0.category == category && $0.isOwned }
    }

    func isRoomDecorationOwned(id: String) -> Bool {
        Self.starterRoomDecorationIDs.contains(id) || ownedRewardIDs.contains(id)
    }

    /// Kept intentionally small for V2; the schema supports future furniture
    /// packs without coupling ownership to a room placement.
    var ownedRoomDecorationIDs: Set<String> {
        Set(
            StudioQuestRoomDecoration.catalog
                .map(\.id)
                .filter { isRoomDecorationOwned(id: $0) }
        )
    }

    func purchaseRoomDecoration(id: String) async -> Bool {
        guard baseRewards.contains(where: { $0.id == id && $0.slot == .studioDecoration }) else {
            return false
        }
        if isRoomDecorationOwned(id: id) { return true }
        return await claimRewardItem(id: id)
    }

    func equippedRewardID(for slot: JourneyRewardSlot) -> String? {
        equippedRewardBySlot[slot.rawValue]
    }

    func isAvatarUnlocked(id: String) -> Bool {
        guard let style = PBAvatarStyle.all.first(where: { $0.id == id }) else { return true }
        if style.isFree { return true }
        return ownedAvatarIDs.contains(id)
    }

    @discardableResult
    func unlockAvatar(id: String) async -> Bool {
        guard let style = PBAvatarStyle.all.first(where: { $0.id == id }),
              let costTokens = style.tokenCost else {
            return true
        }
        if ownedAvatarIDs.contains(id) { return true }
        guard beginEconomyOperation("unlockAvatar:\(id)") else { return false }
        defer { endEconomyOperation("unlockAvatar:\(id)") }

        if let uid = inventoryLinkedUID {
            return await unlockAvatarCloud(uid: uid, avatarID: id, costTokens: costTokens)
        }

        return unlockAvatarLocal(avatarID: id, costTokens: costTokens)
    }

    func linkToUser(uid: String?) {
        let normalizedUID: String? = {
            guard let uid else { return nil }
            let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        if inventoryLinkedUID == normalizedUID { return }

        inventoryListener?.remove()
        inventoryListener = nil
        inventoryLinkedUID = normalizedUID

        guard let uid = normalizedUID else { return }

        syncInventoryToCloud(uid: uid)
        Task { await bootstrapJourneyEconomyInCloud(uid: uid) }
        inventoryListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let data = snapshot?.data() else { return }
            Task { @MainActor in
                self.applyRemoteInventorySnapshot(data)
            }
        }
    }

    private func seedFromExistingSessions(_ sessions: [PracticeSessionModel]) {
        var xp = 0
        var ids: Set<UUID> = []
        var ledger = xpLedgerByDay

        for session in sessions {
            ids.insert(session.id)
            let earned = xpMinutes(for: session)
            xp += earned
            if earned > 0 {
                let key = dayKey(for: session.date)
                ledger[key, default: 0] += earned
            }
        }

        totalXP = xp
        processedSessionIDs = ids
        xpLedgerByDay = ledger
        persistAll()
        recalculateLevel()
        todayXP = xpLedgerByDay[dayKey(for: Date())] ?? 0
    }

    private func awardXPForNewSessions(_ sessions: [PracticeSessionModel]) {
        let newSessions = sessions.filter { !processedSessionIDs.contains($0.id) }
        guard !newSessions.isEmpty else { return }

        var gained = 0
        for session in newSessions {
            processedSessionIDs.insert(session.id)
            let earned = xpMinutes(for: session)
            guard earned > 0 else { continue }
            gained += earned
            let key = dayKey(for: session.date)
            xpLedgerByDay[key, default: 0] += earned
        }

        if gained > 0 {
            totalXP += gained
            recalculateLevel()
        }
        todayXP = xpLedgerByDay[dayKey(for: Date())] ?? 0
        persistAll()
    }

    private func updateQuestProgress(from sessions: [PracticeSessionModel]) {
        _ = sessions
        let now = Date()
        let dayToken = dayKey(for: now)
        let weekToken = questPeriodKey(.weekly, for: now)
        ensureDuelBaselines(dayKey: dayToken, weekKey: weekToken)

        let dailyWins = max(0, latestDuelWins - defaults.integer(forKey: Keys.duelDailyBaselineWins))
        let weeklyWins = max(0, latestDuelWins - defaults.integer(forKey: Keys.duelWeeklyBaselineWins))
        let weeklyRatingGain = max(0, latestDuelRating - defaults.integer(forKey: Keys.duelWeeklyBaselineRating))
        let weeklyLeagueUps = max(0, DuelLeagueTier.forRating(latestDuelRating).difficultyRank - defaults.integer(forKey: Keys.duelWeeklyBaselineLeagueRank))

        var dailyEventCounts: [DuelQuestEvent: Int] = [:]
        var weeklyEventCounts: [DuelQuestEvent: Int] = [:]
        DuelQuestEvent.allCases.forEach { event in
            dailyEventCounts[event] = DuelQuestTelemetryStore.shared.dailyCount(for: event, dayKey: dayToken)
            weeklyEventCounts[event] = DuelQuestTelemetryStore.shared.weeklyCount(for: event, weekKey: weekToken)
        }

        let context = QuestContext(
            dayKey: dayToken,
            weekKey: weekToken,
            dailyEventCounts: dailyEventCounts,
            weeklyEventCounts: weeklyEventCounts,
            dailyWins: dailyWins,
            weeklyWins: weeklyWins,
            weeklyRatingGain: weeklyRatingGain,
            weeklyLeagueUps: weeklyLeagueUps
        )

        let nextDailyQuests = dailyQuestDefinitions.map { definition in
            JourneyQuestRow(
                id: definition.id,
                title: definition.title,
                progress: progress(for: definition.metric, context: context),
                target: definition.target,
                rewardTokens: definition.rewardTokens,
                subtitle: definition.subtitle
            )
        }

        let nextWeeklyQuests = activeWeeklyQuestDefinitions(for: weekToken).map { definition in
            JourneyQuestRow(
                id: definition.id,
                title: definition.title,
                progress: progress(for: definition.metric, context: context),
                target: definition.target,
                rewardTokens: definition.rewardTokens,
                subtitle: definition.subtitle
            )
        }

        if dailyQuests != nextDailyQuests {
            dailyQuests = nextDailyQuests
        }
        if weeklyQuests != nextWeeklyQuests {
            weeklyQuests = nextWeeklyQuests
        }
    }

    private func ensureDuelBaselines(dayKey: String, weekKey: String) {
        if defaults.string(forKey: Keys.duelDailyBaselineDay) != dayKey {
            defaults.set(dayKey, forKey: Keys.duelDailyBaselineDay)
            defaults.set(latestDuelWins, forKey: Keys.duelDailyBaselineWins)
            defaults.set(latestDuelRating, forKey: Keys.duelDailyBaselineRating)
        }
        if defaults.string(forKey: Keys.duelWeeklyBaselineWeek) != weekKey {
            defaults.set(weekKey, forKey: Keys.duelWeeklyBaselineWeek)
            defaults.set(latestDuelWins, forKey: Keys.duelWeeklyBaselineWins)
            defaults.set(latestDuelRating, forKey: Keys.duelWeeklyBaselineRating)
            defaults.set(DuelLeagueTier.forRating(latestDuelRating).difficultyRank, forKey: Keys.duelWeeklyBaselineLeagueRank)
        }
    }

    private var dailyQuestDefinitions: [QuestDefinition] {
        [
            QuestDefinition(
                id: "dq_queue_once",
                title: "Queue Up",
                subtitle: "Join duel queue once today",
                target: 1,
                rewardTokens: 4,
                metric: .dailyEvent(.queueJoined),
                category: "engagement"
            ),
            QuestDefinition(
                id: "dq_invite_once",
                title: "Challenger",
                subtitle: "Send 1 duel challenge",
                target: 1,
                rewardTokens: 5,
                metric: .dailyEvent(.inviteSent),
                category: "engagement"
            ),
            QuestDefinition(
                id: "dq_accept_enter",
                title: "Accept & Enter",
                subtitle: "Accept 1 duel and enter the match flow",
                target: 1,
                rewardTokens: 6,
                metric: .dailyEvent(.acceptEntered),
                category: "engagement"
            ),
            QuestDefinition(
                id: "dq_submit_take",
                title: "Record Take",
                subtitle: "Submit 1 duel take",
                target: 1,
                rewardTokens: 8,
                metric: .dailyEvent(.takeSubmitted),
                category: "core"
            ),
            QuestDefinition(
                id: "dq_win_today",
                title: "Win Today",
                subtitle: "Win 1 duel today",
                target: 1,
                rewardTokens: 10,
                metric: .dailyWins,
                category: "competitive"
            ),
            QuestDefinition(
                id: "dq_clutch_80",
                title: "Clutch Performer",
                subtitle: "Submit a duel take with 80+ derived score",
                target: 1,
                rewardTokens: 7,
                metric: .dailyEvent(.highScoreSubmission),
                category: "quality"
            ),
            QuestDefinition(
                id: "dq_tempo_clean",
                title: "Clean Tempo Run",
                subtitle: "Submit 1 duel take meeting tempo requirement",
                target: 1,
                rewardTokens: 6,
                metric: .dailyEvent(.tempoQualifiedSubmission),
                category: "quality"
            )
        ]
    }

    private var weeklyQuestPool: [QuestDefinition] {
        [
            QuestDefinition(
                id: "wq_duel_volume",
                title: "Duel Volume",
                subtitle: "Submit 5 duel takes this week",
                target: 5,
                rewardTokens: 22,
                metric: .weeklyEvent(.takeSubmitted),
                category: "core"
            ),
            QuestDefinition(
                id: "wq_win_3",
                title: "Win Streak",
                subtitle: "Win 3 duels this week",
                target: 3,
                rewardTokens: 26,
                metric: .weeklyWins,
                category: "competitive"
            ),
            QuestDefinition(
                id: "wq_rating_push",
                title: "Rank Push",
                subtitle: "Gain 40 duel rating this week",
                target: 40,
                rewardTokens: 24,
                metric: .weeklyRatingGain,
                category: "progression"
            ),
            QuestDefinition(
                id: "wq_reliable_challenger",
                title: "Reliable Challenger",
                subtitle: "Queue or send invites 6 times this week",
                target: 6,
                rewardTokens: 18,
                metric: .weeklyAnyEvent([.queueJoined, .inviteSent]),
                category: "engagement"
            ),
            QuestDefinition(
                id: "wq_high_accuracy",
                title: "High Accuracy Week",
                subtitle: "Record 3 takes with 80+ derived score",
                target: 3,
                rewardTokens: 20,
                metric: .weeklyEvent(.highScoreSubmission),
                category: "quality"
            ),
            QuestDefinition(
                id: "wq_league_climber",
                title: "League Climber",
                subtitle: "Climb at least one league this week",
                target: 1,
                rewardTokens: 30,
                metric: .weeklyLeagueUps,
                category: "progression"
            )
        ]
    }

    private func activeWeeklyQuestDefinitions(for weekKey: String) -> [QuestDefinition] {
        if let data = defaults.data(forKey: Keys.weeklyQuestPlan),
           let plan = try? JSONDecoder().decode(WeeklyQuestPlan.self, from: data),
           plan.weekKey == weekKey {
            let map = weeklyQuestPool.reduce(into: [String: QuestDefinition]()) { $0[$1.id] = $1 }
            let existing = plan.questIDs.compactMap { map[$0] }
            if existing.count == plan.questIDs.count {
                return existing
            }
        }

        var selected: [QuestDefinition] = []
        let categories = ["core", "competitive", "engagement", "quality", "progression"]
        for category in categories {
            let quest = weeklyQuestPool
                .filter { $0.category == category }
                .min { deterministicQuestOrderValue($0.id, weekKey: weekKey) < deterministicQuestOrderValue($1.id, weekKey: weekKey) }
            if let quest, !selected.contains(where: { $0.id == quest.id }) {
                selected.append(quest)
            }
            if selected.count >= 4 { break }
        }

        if selected.count < 4 {
            let remaining = weeklyQuestPool
                .filter { candidate in !selected.contains(where: { $0.id == candidate.id }) }
                .sorted { deterministicQuestOrderValue($0.id, weekKey: weekKey) < deterministicQuestOrderValue($1.id, weekKey: weekKey) }
            selected.append(contentsOf: remaining.prefix(4 - selected.count))
        }

        let finalSelection = Array(selected.prefix(4))
        let plan = WeeklyQuestPlan(weekKey: weekKey, questIDs: finalSelection.map(\.id))
        if let encoded = try? JSONEncoder().encode(plan) {
            defaults.set(encoded, forKey: Keys.weeklyQuestPlan)
        }
        return finalSelection
    }

    private func deterministicQuestOrderValue(_ questID: String, weekKey: String) -> UInt64 {
        let salt = questSeedSalt()
        return stableHash64("\(weekKey)|\(salt)|\(questID)")
    }

    private func questSeedSalt() -> String {
        if let existing = defaults.string(forKey: Keys.questSeedSalt), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        defaults.set(created, forKey: Keys.questSeedSalt)
        return created
    }

    private func stableHash64(_ value: String) -> UInt64 {
        let prime: UInt64 = 1099511628211
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    private func progress(for metric: QuestDefinition.Metric, context: QuestContext) -> Int {
        switch metric {
        case .dailyEvent(let event):
            return max(0, context.dailyEventCounts[event] ?? 0)
        case .weeklyEvent(let event):
            return max(0, context.weeklyEventCounts[event] ?? 0)
        case .weeklyAnyEvent(let events):
            return max(0, events.reduce(0) { partial, event in
                partial + max(0, context.weeklyEventCounts[event] ?? 0)
            })
        case .dailyWins:
            return max(0, context.dailyWins)
        case .weeklyWins:
            return max(0, context.weeklyWins)
        case .weeklyRatingGain:
            return max(0, context.weeklyRatingGain)
        case .weeklyLeagueUps:
            return max(0, context.weeklyLeagueUps)
        }
    }

    private func practiceMinutes(for session: PracticeSessionModel) -> Int {
        max(0, practiceSeconds(for: session) / 60)
    }

    private func xpMinutes(for session: PracticeSessionModel) -> Int {
        practiceMinutes(for: session)
    }

    private func practiceSeconds(for session: PracticeSessionModel) -> Int {
        if session.hasVerificationData {
            return max(0, session.verifiedSeconds)
        }
        return max(0, session.durationSeconds)
    }

    private func recalculateLevel() {
        var remaining = max(0, totalXP)
        var currentLevel = 1

        while true {
            let nextCost = xpCostToAdvance(from: currentLevel)
            if remaining < nextCost { break }
            remaining -= nextCost
            currentLevel += 1
        }

        let nextXpForLevel = xpCostToAdvance(from: currentLevel)
        let nextXpToLevel = max(0, nextXpForLevel - remaining)

        if level != currentLevel { level = currentLevel }
        if xpIntoLevel != remaining { xpIntoLevel = remaining }
        if xpForNextLevel != nextXpForLevel { xpForNextLevel = nextXpForLevel }
        if xpToNextLevel != nextXpToLevel { xpToNextLevel = nextXpToLevel }
    }

    private func xpCostToAdvance(from level: Int) -> Int {
        let base = 50
        let growth = 10
        return base + growth * level * level
    }

    private func dayKey(for date: Date) -> String {
        isoDayFormatter.string(from: date)
    }

    private func persistAll() {
        defaults.set(totalXP, forKey: Keys.totalXP)
        defaults.set(max(0, tokenBalance), forKey: Keys.tokenBalance)
        saveProcessedIDs()
        saveLedger()
        saveClaimedQuestRewards()
        saveOwnedAvatars()
        saveOwnedRewards()
        saveEquippedRewards()
        if let uid = inventoryLinkedUID {
            syncInventoryToCloud(uid: uid)
        }
    }

    private func loadProcessedIDs() {
        guard let raw = defaults.array(forKey: Keys.processedSessionIDs) as? [String] else {
            processedSessionIDs = []
            return
        }
        processedSessionIDs = Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func saveProcessedIDs() {
        let raw = processedSessionIDs.map(\.uuidString)
        defaults.set(raw, forKey: Keys.processedSessionIDs)
    }

    private func loadLedger() {
        guard let data = defaults.data(forKey: Keys.xpLedgerByDay),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            xpLedgerByDay = [:]
            return
        }
        xpLedgerByDay = decoded
    }

    private func saveLedger() {
        guard let data = try? JSONEncoder().encode(xpLedgerByDay) else { return }
        defaults.set(data, forKey: Keys.xpLedgerByDay)
    }

    private func loadClaimedQuestRewards() {
        guard let raw = defaults.array(forKey: Keys.claimedQuestRewardKeys) as? [String] else {
            claimedQuestRewardKeys = []
            return
        }
        claimedQuestRewardKeys = Set(raw)
    }

    private func saveClaimedQuestRewards() {
        defaults.set(Array(claimedQuestRewardKeys), forKey: Keys.claimedQuestRewardKeys)
    }

    private func loadOwnedAvatars() {
        guard let raw = defaults.array(forKey: Keys.ownedAvatarIDs) as? [String] else {
            ownedAvatarIDs = []
            return
        }
        ownedAvatarIDs = Set(raw.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private func saveOwnedAvatars() {
        defaults.set(Array(ownedAvatarIDs).sorted(), forKey: Keys.ownedAvatarIDs)
    }

    private func loadOwnedRewards() {
        guard let raw = defaults.array(forKey: Keys.ownedRewardIDs) as? [String] else {
            ownedRewardIDs = []
            return
        }
        ownedRewardIDs = Set(raw)
    }

    private func saveOwnedRewards() {
        defaults.set(Array(ownedRewardIDs), forKey: Keys.ownedRewardIDs)
    }

    private func loadEquippedRewards() {
        guard let data = defaults.data(forKey: Keys.equippedRewardBySlot),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            equippedRewardBySlot = [:]
            applyEquippedSideEffects()
            return
        }
        equippedRewardBySlot = decoded
        applyEquippedSideEffects()
    }

    private func saveEquippedRewards() {
        guard let data = try? JSONEncoder().encode(equippedRewardBySlot) else { return }
        defaults.set(data, forKey: Keys.equippedRewardBySlot)
    }

    private func questRewardClaimKey(for questID: String, period: JourneyQuestPeriod, at date: Date) -> String {
        "\(period.rawValue):\(questPeriodKey(period, for: date)):\(questID)"
    }

    private func questPeriodKey(_ period: JourneyQuestPeriod, for date: Date) -> String {
        switch period {
        case .daily:
            return dayKey(for: date)
        case .weekly:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let year = calendar.component(.yearForWeekOfYear, from: date)
            let week = calendar.component(.weekOfYear, from: date)
            return "\(year)-W\(week)"
        }
    }

    private var baseRewards: [JourneyRewardItem] {
        [
            JourneyRewardItem(
                id: "room_decoration_plant",
                title: "Cobalt Plant",
                subtitle: "A starter floor decoration for your studio.",
                costTokens: 0,
                category: .cosmetics,
                slot: .studioDecoration,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "room_decoration_rug",
                title: "Practice Rug",
                subtitle: "A woven floor layer for your focused space.",
                costTokens: 35,
                category: .cosmetics,
                slot: .studioDecoration,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "room_decoration_lamp",
                title: "Violet Floor Lamp",
                subtitle: "A warm after-hours studio light.",
                costTokens: 65,
                category: .cosmetics,
                slot: .studioDecoration,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "room_decoration_art",
                title: "Motion Study",
                subtitle: "A framed cobalt path for your studio wall.",
                costTokens: 55,
                category: .cosmetics,
                slot: .studioDecoration,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "room_decoration_shelf",
                title: "Open Shelf",
                subtitle: "A quiet wall piece for future collections.",
                costTokens: 80,
                category: .cosmetics,
                slot: .studioDecoration,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_profile_frame_studio",
                title: "Studio Frame",
                subtitle: "A clean rounded profile frame for your card.",
                costTokens: 60,
                category: .cosmetics,
                slot: .profileFrame,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_profile_banner_concert",
                title: "Concert Banner",
                subtitle: "Warm concert banner behind your top profile card.",
                costTokens: 120,
                category: .cosmetics,
                slot: .profileBanner,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_profile_glow_soft",
                title: "Soft Profile Glow",
                subtitle: "Subtle accent glow around your profile card.",
                costTokens: 90,
                category: .cosmetics,
                slot: .profileGlow,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_confetti_classic",
                title: "Classic Confetti",
                subtitle: "Celebration burst with classic accents.",
                costTokens: 70,
                category: .cosmetics,
                slot: .confettiStyle,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_confetti_spark",
                title: "Spark Confetti",
                subtitle: "Brighter confetti palette for reward celebrations.",
                costTokens: 140,
                category: .cosmetics,
                slot: .confettiStyle,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_duel_intro_card_spotlight",
                title: "Duel Intro Card: Spotlight",
                subtitle: "Adds a featured intro style to the duel entry header.",
                costTokens: 180,
                category: .cosmetics,
                slot: .duelIntroCard,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_duel_finisher_fx_resonance",
                title: "Duel Finisher FX: Resonance",
                subtitle: "Plays a finish overlay when a duel result is finalized.",
                costTokens: 210,
                category: .cosmetics,
                slot: .duelFinisherFX,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_session_card_skin_aurora",
                title: "Session Card Skin: Aurora",
                subtitle: "Applies an aurora-styled skin to Play reward/result cards.",
                costTokens: 160,
                category: .cosmetics,
                slot: .sessionCardSkin,
                isOwned: false,
                isEquipped: false
            ),
            JourneyRewardItem(
                id: "reward_metronome_pack_studio",
                title: "Metronome Pack: Studio",
                subtitle: "Switches metronome to Studio wood-click sound.",
                costTokens: 160,
                category: .tools,
                slot: .metronomePack,
                isOwned: false,
                isEquipped: false
            )
        ]
    }

    private func refreshRewards() {
        rewards = baseRewards.map { item in
            JourneyRewardItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                costTokens: item.costTokens,
                category: item.category,
                slot: item.slot,
                isOwned: isRoomDecorationOwned(id: item.id) || ownedRewardIDs.contains(item.id),
                isEquipped: item.slot != .studioDecoration && equippedRewardBySlot[item.slot.rawValue] == item.id
            )
        }
    }

    private func applyEquippedSideEffects() {
        if equippedRewardBySlot[JourneyRewardSlot.metronomePack.rawValue] == "reward_metronome_pack_studio" {
            defaults.set("wood", forKey: InventoryKeys.metronomeSoundStyleOverride)
        } else {
            defaults.removeObject(forKey: InventoryKeys.metronomeSoundStyleOverride)
        }

        let confettiID = equippedRewardBySlot[JourneyRewardSlot.confettiStyle.rawValue] ?? "default"
        defaults.set(confettiID, forKey: InventoryKeys.confettiStyle)
    }

    private func applyRemoteInventorySnapshot(_ data: [String: Any]) {
        if isApplyingRemoteInventory { return }

        let remoteOwned = Set((data[InventoryKeys.cloudOwnedRewardIDs] as? [String] ?? []).filter { !$0.isEmpty })
        let remoteOwnedAvatars = Set((data[InventoryKeys.cloudOwnedAvatarIDs] as? [String] ?? []).filter { !$0.isEmpty })
        let rawEquipped = (data[InventoryKeys.cloudEquippedRewardBySlot] as? [String: String]) ?? [:]
        let remoteClaimedQuestKeys = Set((data[InventoryKeys.cloudClaimedQuestRewardKeys] as? [String] ?? []).filter { !$0.isEmpty })
        let hasRemoteTokenBalance = data[InventoryKeys.cloudTokenBalance] != nil
        let remoteTokenBalance = max(0, (data[InventoryKeys.cloudTokenBalance] as? Int) ?? 0)
        let normalizedRemoteEquipped = rawEquipped.reduce(into: [String: String]()) { partial, pair in
            let slot = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let rewardID = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slot.isEmpty, !rewardID.isEmpty else { return }
            partial[slot] = rewardID
        }

        var mergedOwned = ownedRewardIDs
        mergedOwned.formUnion(remoteOwned)
        let mergedOwnedAvatars = ownedAvatarIDs.union(remoteOwnedAvatars)

        var mergedEquipped = normalizedRemoteEquipped.filter { mergedOwned.contains($0.value) }
        for (slot, rewardID) in equippedRewardBySlot where mergedEquipped[slot] == nil && mergedOwned.contains(rewardID) {
            mergedEquipped[slot] = rewardID
        }
        let mergedClaimedQuestKeys = claimedQuestRewardKeys.union(remoteClaimedQuestKeys)

        let ownedChanged = mergedOwned != ownedRewardIDs
        let avatarsChanged = mergedOwnedAvatars != ownedAvatarIDs
        let equippedChanged = mergedEquipped != equippedRewardBySlot
        let claimedChanged = mergedClaimedQuestKeys != claimedQuestRewardKeys
        let tokenChanged = hasRemoteTokenBalance && remoteTokenBalance != tokenBalance
        guard ownedChanged || avatarsChanged || equippedChanged || claimedChanged || tokenChanged else { return }

        isApplyingRemoteInventory = true
        ownedRewardIDs = mergedOwned
        ownedAvatarIDs = mergedOwnedAvatars
        equippedRewardBySlot = mergedEquipped
        claimedQuestRewardKeys = mergedClaimedQuestKeys
        if hasRemoteTokenBalance {
            tokenBalance = remoteTokenBalance
        }
        applyEquippedSideEffects()
        refreshRewards()
        defaults.set(max(0, tokenBalance), forKey: Keys.tokenBalance)
        saveClaimedQuestRewards()
        saveOwnedAvatars()
        saveOwnedRewards()
        saveEquippedRewards()
        isApplyingRemoteInventory = false
    }

    private func syncInventoryToCloud(uid: String) {
        guard !isApplyingRemoteInventory else { return }

        let payload: [String: Any] = [
            InventoryKeys.cloudOwnedRewardIDs: Array(ownedRewardIDs).sorted(),
            InventoryKeys.cloudOwnedAvatarIDs: Array(ownedAvatarIDs).sorted(),
            InventoryKeys.cloudEquippedRewardBySlot: equippedRewardBySlot,
            InventoryKeys.cloudUpdatedAt: FieldValue.serverTimestamp()
        ]

        Task {
            do {
                try await db.collection("users").document(uid).setData(payload, merge: true)
            } catch {
                PBLog.firebase.error("Inventory cloud sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func claimQuestRewardLocal(claimKey: String, rewardTokens: Int) -> Bool {
        guard !claimedQuestRewardKeys.contains(claimKey) else { return false }
        claimedQuestRewardKeys.insert(claimKey)
        tokenBalance += max(0, rewardTokens)
        persistAll()
        return true
    }

    private func claimRewardItemLocal(id: String) -> Bool {
        guard !ownedRewardIDs.contains(id),
              let item = baseRewards.first(where: { $0.id == id }),
              tokenBalance >= item.costTokens else {
            return false
        }

        tokenBalance -= item.costTokens
        ownedRewardIDs.insert(id)
        if item.slot != .studioDecoration && equippedRewardBySlot[item.slot.rawValue] == nil {
            equippedRewardBySlot[item.slot.rawValue] = item.id
        }
        applyEquippedSideEffects()
        refreshRewards()
        persistAll()
        return true
    }

    private func equipRewardItemLocal(id: String) -> Bool {
        guard ownedRewardIDs.contains(id),
              let item = baseRewards.first(where: { $0.id == id }) else {
            return false
        }
        equippedRewardBySlot[item.slot.rawValue] = item.id
        applyEquippedSideEffects()
        refreshRewards()
        persistAll()
        return true
    }

    private func unequipRewardLocal(slot: JourneyRewardSlot) -> Bool {
        guard equippedRewardBySlot[slot.rawValue] != nil else { return false }
        equippedRewardBySlot.removeValue(forKey: slot.rawValue)
        applyEquippedSideEffects()
        refreshRewards()
        persistAll()
        return true
    }

    private func unlockAvatarLocal(avatarID: String, costTokens: Int) -> Bool {
        let normalizedID = avatarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return false }
        if ownedAvatarIDs.contains(normalizedID) { return true }
        guard tokenBalance >= max(0, costTokens) else { return false }

        tokenBalance -= max(0, costTokens)
        ownedAvatarIDs.insert(normalizedID)
        persistAll()
        return true
    }

    private func claimQuestRewardCloud(uid: String, claimKey: String, rewardTokens: Int) async -> Bool {
        do {
            let result = try await runCloudTransaction { transaction, errorPointer in
                let userRef = self.db.collection("users").document(uid)
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data() ?? [:]
                var cloudClaimed = Set((data[InventoryKeys.cloudClaimedQuestRewardKeys] as? [String] ?? []).filter { !$0.isEmpty })
                var cloudTokens = max(0, (data[InventoryKeys.cloudTokenBalance] as? Int) ?? self.tokenBalance)
                if cloudClaimed.contains(claimKey) {
                    return [
                        "success": false,
                        "tokenBalance": cloudTokens,
                        "claimedQuestRewardKeys": Array(cloudClaimed)
                    ]
                }

                cloudClaimed.insert(claimKey)
                cloudTokens += max(0, rewardTokens)

                transaction.setData([
                    InventoryKeys.cloudTokenBalance: cloudTokens,
                    InventoryKeys.cloudClaimedQuestRewardKeys: Array(cloudClaimed).sorted(),
                    InventoryKeys.cloudUpdatedAt: FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)

                return [
                    "success": true,
                    "tokenBalance": cloudTokens,
                    "claimedQuestRewardKeys": Array(cloudClaimed)
                ]
            }

            guard let dict = result as? [String: Any] else { return false }
            let didClaim = (dict["success"] as? Bool) ?? false
            let claimed = Set((dict["claimedQuestRewardKeys"] as? [String] ?? []).filter { !$0.isEmpty })
            let tokens = max(0, (dict["tokenBalance"] as? Int) ?? tokenBalance)

            claimedQuestRewardKeys = claimed
            tokenBalance = tokens
            defaults.set(max(0, tokenBalance), forKey: Keys.tokenBalance)
            saveClaimedQuestRewards()
            return didClaim
        } catch {
            return claimQuestRewardLocal(claimKey: claimKey, rewardTokens: rewardTokens)
        }
    }

    private func claimRewardItemCloud(uid: String, item: JourneyRewardItem) async -> Bool {
        do {
            let result = try await runCloudTransaction { transaction, errorPointer in
                let userRef = self.db.collection("users").document(uid)
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data() ?? [:]
                var cloudOwned = Set((data[InventoryKeys.cloudOwnedRewardIDs] as? [String] ?? []).filter { !$0.isEmpty })
                var cloudEquipped = (data[InventoryKeys.cloudEquippedRewardBySlot] as? [String: String]) ?? [:]
                var cloudTokens = max(0, (data[InventoryKeys.cloudTokenBalance] as? Int) ?? self.tokenBalance)

                if cloudOwned.contains(item.id) {
                    return [
                        "success": false,
                        "tokenBalance": cloudTokens,
                        "ownedRewardIDs": Array(cloudOwned),
                        "equippedRewardBySlot": cloudEquipped
                    ]
                }

                guard cloudTokens >= item.costTokens else {
                    return [
                        "success": false,
                        "tokenBalance": cloudTokens,
                        "ownedRewardIDs": Array(cloudOwned),
                        "equippedRewardBySlot": cloudEquipped
                    ]
                }

                cloudTokens -= item.costTokens
                cloudOwned.insert(item.id)
                if item.slot != .studioDecoration && cloudEquipped[item.slot.rawValue] == nil {
                    cloudEquipped[item.slot.rawValue] = item.id
                }

                transaction.setData([
                    InventoryKeys.cloudTokenBalance: cloudTokens,
                    InventoryKeys.cloudOwnedRewardIDs: Array(cloudOwned).sorted(),
                    InventoryKeys.cloudEquippedRewardBySlot: cloudEquipped,
                    InventoryKeys.cloudUpdatedAt: FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)

                return [
                    "success": true,
                    "tokenBalance": cloudTokens,
                    "ownedRewardIDs": Array(cloudOwned),
                    "equippedRewardBySlot": cloudEquipped
                ]
            }

            guard let dict = result as? [String: Any] else { return false }
            let didClaim = (dict["success"] as? Bool) ?? false
            let cloudTokens = max(0, (dict["tokenBalance"] as? Int) ?? tokenBalance)
            let cloudOwned = Set((dict["ownedRewardIDs"] as? [String] ?? []).filter { !$0.isEmpty })
            let cloudEquipped = (dict["equippedRewardBySlot"] as? [String: String]) ?? [:]

            tokenBalance = cloudTokens
            ownedRewardIDs = cloudOwned.union(ownedRewardIDs)
            equippedRewardBySlot = cloudEquipped.filter { ownedRewardIDs.contains($0.value) }
            applyEquippedSideEffects()
            refreshRewards()
            defaults.set(max(0, tokenBalance), forKey: Keys.tokenBalance)
            saveOwnedRewards()
            saveEquippedRewards()
            return didClaim
        } catch {
            return claimRewardItemLocal(id: item.id)
        }
    }

    private func equipRewardItemCloud(uid: String, item: JourneyRewardItem) async -> Bool {
        do {
            let result = try await runCloudTransaction { transaction, errorPointer in
                let userRef = self.db.collection("users").document(uid)
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data() ?? [:]
                let cloudOwned = Set((data[InventoryKeys.cloudOwnedRewardIDs] as? [String] ?? []).filter { !$0.isEmpty })
                var cloudEquipped = (data[InventoryKeys.cloudEquippedRewardBySlot] as? [String: String]) ?? [:]
                let mergedOwned = cloudOwned.union(self.ownedRewardIDs)

                guard mergedOwned.contains(item.id) else {
                    return [
                        "success": false,
                        "ownedRewardIDs": Array(cloudOwned),
                        "equippedRewardBySlot": cloudEquipped
                    ]
                }

                cloudEquipped[item.slot.rawValue] = item.id
                transaction.setData([
                    InventoryKeys.cloudOwnedRewardIDs: Array(mergedOwned).sorted(),
                    InventoryKeys.cloudEquippedRewardBySlot: cloudEquipped,
                    InventoryKeys.cloudUpdatedAt: FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)

                return [
                    "success": true,
                    "ownedRewardIDs": Array(mergedOwned),
                    "equippedRewardBySlot": cloudEquipped
                ]
            }

            guard let dict = result as? [String: Any] else { return false }
            let didEquip = (dict["success"] as? Bool) ?? false
            let cloudOwned = Set((dict["ownedRewardIDs"] as? [String] ?? []).filter { !$0.isEmpty })
            let cloudEquipped = (dict["equippedRewardBySlot"] as? [String: String]) ?? [:]

            ownedRewardIDs = cloudOwned.union(ownedRewardIDs)
            equippedRewardBySlot = cloudEquipped.filter { ownedRewardIDs.contains($0.value) }
            applyEquippedSideEffects()
            refreshRewards()
            saveOwnedRewards()
            saveEquippedRewards()
            return didEquip
        } catch {
            return equipRewardItemLocal(id: item.id)
        }
    }

    private func unequipRewardCloud(uid: String, slot: JourneyRewardSlot) async -> Bool {
        do {
            let result = try await runCloudTransaction { transaction, errorPointer in
                let userRef = self.db.collection("users").document(uid)
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data() ?? [:]
                let cloudOwned = Set((data[InventoryKeys.cloudOwnedRewardIDs] as? [String] ?? []).filter { !$0.isEmpty })
                var cloudEquipped = (data[InventoryKeys.cloudEquippedRewardBySlot] as? [String: String]) ?? [:]
                guard cloudEquipped[slot.rawValue] != nil else {
                    return [
                        "success": false,
                        "ownedRewardIDs": Array(cloudOwned),
                        "equippedRewardBySlot": cloudEquipped
                    ]
                }

                cloudEquipped.removeValue(forKey: slot.rawValue)
                transaction.setData([
                    InventoryKeys.cloudOwnedRewardIDs: Array(cloudOwned.union(self.ownedRewardIDs)).sorted(),
                    InventoryKeys.cloudEquippedRewardBySlot: cloudEquipped,
                    InventoryKeys.cloudUpdatedAt: FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)

                return [
                    "success": true,
                    "ownedRewardIDs": Array(cloudOwned),
                    "equippedRewardBySlot": cloudEquipped
                ]
            }

            guard let dict = result as? [String: Any] else { return false }
            let didUnequip = (dict["success"] as? Bool) ?? false
            let cloudOwned = Set((dict["ownedRewardIDs"] as? [String] ?? []).filter { !$0.isEmpty })
            let cloudEquipped = (dict["equippedRewardBySlot"] as? [String: String]) ?? [:]

            ownedRewardIDs = cloudOwned.union(ownedRewardIDs)
            equippedRewardBySlot = cloudEquipped.filter { ownedRewardIDs.contains($0.value) }
            applyEquippedSideEffects()
            refreshRewards()
            saveOwnedRewards()
            saveEquippedRewards()
            return didUnequip
        } catch {
            return unequipRewardLocal(slot: slot)
        }
    }

    private func unlockAvatarCloud(uid: String, avatarID: String, costTokens: Int) async -> Bool {
        do {
            let result = try await runCloudTransaction { transaction, errorPointer in
                let userRef = self.db.collection("users").document(uid)
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data() ?? [:]
                var cloudOwnedAvatars = Set((data[InventoryKeys.cloudOwnedAvatarIDs] as? [String] ?? []).filter { !$0.isEmpty })
                var cloudTokens = max(0, (data[InventoryKeys.cloudTokenBalance] as? Int) ?? self.tokenBalance)

                if cloudOwnedAvatars.contains(avatarID) {
                    return [
                        "success": true,
                        "tokenBalance": cloudTokens,
                        "ownedAvatarIDs": Array(cloudOwnedAvatars)
                    ]
                }

                let normalizedCost = max(0, costTokens)
                guard cloudTokens >= normalizedCost else {
                    return [
                        "success": false,
                        "tokenBalance": cloudTokens,
                        "ownedAvatarIDs": Array(cloudOwnedAvatars)
                    ]
                }

                cloudTokens -= normalizedCost
                cloudOwnedAvatars.insert(avatarID)

                transaction.setData([
                    InventoryKeys.cloudTokenBalance: cloudTokens,
                    InventoryKeys.cloudOwnedAvatarIDs: Array(cloudOwnedAvatars).sorted(),
                    InventoryKeys.cloudUpdatedAt: FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)

                return [
                    "success": true,
                    "tokenBalance": cloudTokens,
                    "ownedAvatarIDs": Array(cloudOwnedAvatars)
                ]
            }

            guard let dict = result as? [String: Any] else { return false }
            let didUnlock = (dict["success"] as? Bool) ?? false
            let cloudTokens = max(0, (dict["tokenBalance"] as? Int) ?? tokenBalance)
            let cloudOwnedAvatars = Set((dict["ownedAvatarIDs"] as? [String] ?? []).filter { !$0.isEmpty })

            tokenBalance = cloudTokens
            ownedAvatarIDs = cloudOwnedAvatars.union(ownedAvatarIDs)
            defaults.set(max(0, tokenBalance), forKey: Keys.tokenBalance)
            saveOwnedAvatars()
            return didUnlock
        } catch {
            return unlockAvatarLocal(avatarID: avatarID, costTokens: costTokens)
        }
    }

    private func bootstrapJourneyEconomyInCloud(uid: String) async {
        do {
            _ = try await runCloudTransaction { transaction, errorPointer in
                let userRef = self.db.collection("users").document(uid)
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data() ?? [:]
                let hasCloudToken = data[InventoryKeys.cloudTokenBalance] != nil
                let hasCloudClaimed = data[InventoryKeys.cloudClaimedQuestRewardKeys] != nil
                let hasCloudOwnedAvatars = data[InventoryKeys.cloudOwnedAvatarIDs] != nil
                if hasCloudToken && hasCloudClaimed && hasCloudOwnedAvatars { return ["bootstrapped": false] }

                transaction.setData([
                    InventoryKeys.cloudTokenBalance: max(0, self.tokenBalance),
                    InventoryKeys.cloudClaimedQuestRewardKeys: Array(self.claimedQuestRewardKeys).sorted(),
                    InventoryKeys.cloudOwnedAvatarIDs: Array(self.ownedAvatarIDs).sorted(),
                    InventoryKeys.cloudUpdatedAt: FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)
                return ["bootstrapped": true]
            }
        } catch {
            // Non-fatal; local state still works and future operations will retry cloud sync.
        }
    }

    private func runCloudTransaction(
        _ updateBlock: @escaping (Transaction, NSErrorPointer) -> Any?
    ) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            db.runTransaction(updateBlock) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: NSError(
                        domain: "PracticeBuddy.Journey",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Cloud transaction returned no result."]
                    ))
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func beginEconomyOperation(_ key: String) -> Bool {
        guard !economyOperationKeysInFlight.contains(key) else { return false }
        guard economyOperationKeysInFlight.isEmpty else { return false }
        economyOperationKeysInFlight.insert(key)
        isEconomyOperationInProgress = !economyOperationKeysInFlight.isEmpty
        return true
    }

    private func endEconomyOperation(_ key: String) {
        economyOperationKeysInFlight.remove(key)
        isEconomyOperationInProgress = !economyOperationKeysInFlight.isEmpty
    }

    static func preferredMetronomeSoundStyleRaw() -> String? {
        UserDefaults.standard.string(forKey: InventoryKeys.metronomeSoundStyleOverride)
    }

    static func activeConfettiStyleID() -> String {
        UserDefaults.standard.string(forKey: InventoryKeys.confettiStyle) ?? "default"
    }
}

struct DuelLeagueRequirement: Equatable {
    let league: DuelLeagueTier
    let octaves: DuelOctaveCount
    let minimumTempoBPM: Int

    var summary: String {
        if minimumTempoBPM > 0 {
            return "\(octaves.title) • \(minimumTempoBPM)+ BPM"
        }
        return octaves.title
    }
}

enum DuelLeagueTier: String, CaseIterable {
    case bronze
    case silver
    case gold
    case platinum
    case emerald
    case diamond
    case master
    case grandmaster

    var title: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        case .emerald: return "Emerald"
        case .diamond: return "Diamond"
        case .master: return "Master"
        case .grandmaster: return "Grandmaster"
        }
    }

    var minRating: Int {
        switch self {
        case .bronze: return 0
        case .silver: return 200
        case .gold: return 450
        case .platinum: return 700
        case .emerald: return 950
        case .diamond: return 1250
        case .master: return 1600
        case .grandmaster: return 2000
        }
    }

    var difficultyRank: Int {
        switch self {
        case .bronze: return 0
        case .silver: return 1
        case .gold: return 2
        case .platinum: return 3
        case .emerald: return 4
        case .diamond: return 5
        case .master: return 6
        case .grandmaster: return 7
        }
    }

    var requirement: DuelLeagueRequirement {
        switch self {
        case .bronze:
            return DuelLeagueRequirement(league: self, octaves: .one, minimumTempoBPM: 0)
        case .silver:
            return DuelLeagueRequirement(league: self, octaves: .two, minimumTempoBPM: 0)
        case .gold:
            return DuelLeagueRequirement(league: self, octaves: .three, minimumTempoBPM: 0)
        case .platinum:
            return DuelLeagueRequirement(league: self, octaves: .three, minimumTempoBPM: 88)
        case .emerald:
            return DuelLeagueRequirement(league: self, octaves: .three, minimumTempoBPM: 104)
        case .diamond:
            return DuelLeagueRequirement(league: self, octaves: .three, minimumTempoBPM: 116)
        case .master:
            return DuelLeagueRequirement(league: self, octaves: .three, minimumTempoBPM: 126)
        case .grandmaster:
            return DuelLeagueRequirement(league: self, octaves: .three, minimumTempoBPM: 136)
        }
    }

    var next: DuelLeagueTier? {
        switch self {
        case .bronze: return .silver
        case .silver: return .gold
        case .gold: return .platinum
        case .platinum: return .emerald
        case .emerald: return .diamond
        case .diamond: return .master
        case .master: return .grandmaster
        case .grandmaster: return nil
        }
    }

    static func forRating(_ rating: Int) -> DuelLeagueTier {
        if rating >= DuelLeagueTier.grandmaster.minRating { return .grandmaster }
        if rating >= DuelLeagueTier.master.minRating { return .master }
        if rating >= DuelLeagueTier.diamond.minRating { return .diamond }
        if rating >= DuelLeagueTier.emerald.minRating { return .emerald }
        if rating >= DuelLeagueTier.platinum.minRating { return .platinum }
        if rating >= DuelLeagueTier.gold.minRating { return .gold }
        if rating >= DuelLeagueTier.silver.minRating { return .silver }
        return .bronze
    }
}

enum DuelChallengeStatus: String {
    case open
    case invited
    case active
    case completed
    case canceled
}

enum DuelChallengeQueueType: String {
    case open
    case friend
    case studio
}

enum DuelInviteSource: String {
    case friend

    var title: String {
        switch self {
        case .friend: return "Friend"
        }
    }
}

struct DuelTargetCandidate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let source: DuelInviteSource
    let subtitle: String
}

enum DuelOctaveCount: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }
    var title: String { "\(rawValue) octave\(rawValue == 1 ? "" : "s")" }
}

enum DuelLeaderboardScope: String, CaseIterable, Identifiable {
    case global = "Global"
    case friends = "Friends"

    var id: String { rawValue }
}

struct DuelLeaderboardRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let avatarID: String
    let profilePhotoURL: String
    let publicLevel: Int
    let points: Int
    let rating: Int
    let wins: Int
    let matches: Int
}

struct DuelDerivedMetrics {
    let intonationScore: Int
    let rhythmScore: Int
    let consistencyScore: Int
    let noteCount: Int
    let beatsAnalyzed: Int
    let tempoBPM: Int

    var derivedScore: Int {
        let weighted = (Double(intonationScore) * 0.5) + (Double(rhythmScore) * 0.35) + (Double(consistencyScore) * 0.15)
        return min(max(Int(weighted.rounded()), 0), 100)
    }
}

struct DuelParticipantCard: Identifiable, Equatable {
    let id: String
    let displayName: String
    let publicLevel: Int
    let duelRating: Int
}

struct DuelChallenge: Identifiable, Equatable {
    let id: String
    let createdByUID: String
    let opponentUID: String?
    let participants: [String]
    let status: DuelChallengeStatus
    let queueType: DuelChallengeQueueType
    let objective: String
    let scaleName: String?
    let octaveCount: Int
    let requiredLeague: String?
    let requiredMinTempoBPM: Int
    let creatorAccepted: Bool
    let opponentAccepted: Bool
    let opponentRequestedOctaves: Int?
    let createdAt: Date
    let acceptByAt: Date?
    let startedAt: Date?
    let submissionDeadlineAt: Date?
    let completedAt: Date?
    let creatorScore: Int?
    let opponentScore: Int?
    let winnerUID: String?
    let creatorRatingDelta: Int
    let opponentRatingDelta: Int

    func myScore(for uid: String) -> Int? {
        uid == createdByUID ? creatorScore : opponentScore
    }

    func opponentScore(for uid: String) -> Int? {
        uid == createdByUID ? opponentScore : creatorScore
    }

    func myRatingDelta(for uid: String) -> Int {
        uid == createdByUID ? creatorRatingDelta : opponentRatingDelta
    }

    func otherParticipant(for uid: String) -> String? {
        participants.first(where: { $0 != uid })
    }
}

struct DuelRecoverableActionError: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let retryTitle: String
}

@MainActor
final class DuelLeagueManager: ObservableObject {
    @Published private(set) var myOpenChallenge: DuelChallenge?
    @Published private(set) var incomingInvites: [DuelChallenge] = []
    @Published private(set) var outgoingInvites: [DuelChallenge] = []
    @Published private(set) var activeChallenges: [DuelChallenge] = []
    @Published private(set) var recentCompleted: [DuelChallenge] = []
    @Published private(set) var matchHistory: [DuelChallenge] = []
    @Published private(set) var userDisplayNames: [String: String] = [:]
    @Published private(set) var friendCandidates: [DuelTargetCandidate] = []
    @Published private(set) var seasonKey: String = ""
    @Published private(set) var seasonPoints: Int = 0
    @Published private(set) var seasonMatches: Int = 0
    @Published private(set) var seasonWins: Int = 0
    @Published private(set) var leaderboardRows: [DuelLeaderboardRow] = []
    @Published private(set) var duelRating: Int = 0
    @Published private(set) var duelWins: Int = 0
    @Published private(set) var duelLosses: Int = 0
    @Published private(set) var duelDraws: Int = 0
    @Published private(set) var readyChallengeID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isActionBusy = false
    @Published private(set) var recoverableActionError: DuelRecoverableActionError?
    @Published var statusMessage: String?

    var leagueTier: DuelLeagueTier { DuelLeagueTier.forRating(duelRating) }
    var activeLeagueRequirement: DuelLeagueRequirement { leagueTier.requirement }

    private var db: Firestore { Firestore.firestore() }
    private var listeners: [ListenerRegistration] = []
    private var configuredUID: String?
    private var lastTargetCandidatesRefreshAt: Date?
    private var friendCandidatesCache: [DuelTargetCandidate] = []
    private var leaderboardCache: [DuelLeaderboardScope: (seasonKey: String, rows: [DuelLeaderboardRow], fetchedAt: Date)] = [:]
    private let targetCandidatesRefreshCooldown: TimeInterval = 30
    private let leaderboardRefreshCooldown: TimeInterval = 60 * 60 * 24
    private let urlSession = URLSession.shared
    private var didReceiveInitialChallengeSnapshot = false
    private var priorChallengeStatusByID: [String: DuelChallengeStatus] = [:]
    private var inFlightActionKeys: Set<String> = []
    private var pendingRetryAction: DuelPendingRetryAction?
    private var isPrefetchingDisplayNames = false
    private var pendingDisplayNameUIDs: Set<String> = []
    private let telemetryDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private enum DuelPendingRetryAction {
        case acceptInvite(challengeID: String)
        case cancelInvite(challengeID: String)
        case cancelQueue
        case submitAttempt(challengeID: String, metrics: DuelDerivedMetrics, requiredMinTempoBPM: Int)
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    func start(uid: String?) {
        guard let uid, !uid.isEmpty else {
            stop()
            return
        }
        if configuredUID == uid { return }
        stop()
        configuredUID = uid
        attachRealtime(for: uid)
        Task { await ensureProfileDefaults(uid: uid) }
    }

    func pauseRealtime() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    func stop() {
        pauseRealtime()
        configuredUID = nil
        myOpenChallenge = nil
        incomingInvites = []
        outgoingInvites = []
        activeChallenges = []
        recentCompleted = []
        matchHistory = []
        userDisplayNames = [:]
        friendCandidates = []
        seasonKey = ""
        seasonPoints = 0
        seasonMatches = 0
        seasonWins = 0
        leaderboardRows = []
        duelRating = 0
        duelWins = 0
        duelLosses = 0
        duelDraws = 0
        readyChallengeID = nil
        isLoading = false
        statusMessage = nil
        lastTargetCandidatesRefreshAt = nil
        friendCandidatesCache = []
        leaderboardCache = [:]
        didReceiveInitialChallengeSnapshot = false
        priorChallengeStatusByID = [:]
        inFlightActionKeys = []
        pendingRetryAction = nil
        isActionBusy = false
        recoverableActionError = nil
    }

    func isActionInFlight(for key: String) -> Bool {
        inFlightActionKeys.contains(key)
    }

    func rememberDisplayName(uid: String, name: String) {
        let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty, !normalizedName.isEmpty else { return }
        if userDisplayNames[normalizedUID] != normalizedName {
            userDisplayNames[normalizedUID] = normalizedName
        }
    }

    func clearRecoverableActionError() {
        recoverableActionError = nil
        pendingRetryAction = nil
    }

    func retryRecoverableAction() async {
        guard let action = pendingRetryAction else { return }
        clearRecoverableActionError()
        switch action {
        case .acceptInvite(let challengeID):
            await acceptInvite(challengeID: challengeID)
        case .cancelInvite(let challengeID):
            await cancelInvite(challengeID: challengeID)
        case .cancelQueue:
            await cancelOpenChallenge()
        case .submitAttempt(let challengeID, let metrics, let requiredMinTempoBPM):
            await submitDerivedAttempt(
                challengeID: challengeID,
                metrics: metrics,
                requiredMinTempoBPM: requiredMinTempoBPM
            )
        }
    }

    func queueAsyncScaleDuel(octaves: DuelOctaveCount = .one) async {
        guard let uid = configuredUID else { return }
        let required = activeLeagueRequirement
        let requestedOctaves = max(octaves.rawValue, required.octaves.rawValue)
        let normalizedOctaves = DuelOctaveCount(rawValue: requestedOctaves) ?? required.octaves
        if myOpenChallenge != nil {
            statusMessage = "You already have an open duel request."
            return
        }
        if activeChallenges.contains(where: { $0.myScore(for: uid) == nil }) {
            statusMessage = "Finish your active duel before queueing a new one."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            PBLog.firebase.info("Duel queue join start uid=\(uid, privacy: .private) octaves=\(normalizedOctaves.rawValue, privacy: .public)")
            let response = try await callDuelEndpoint(
                name: "duelQueueJoin",
                body: ["octaves": normalizedOctaves.rawValue]
            )
            let status = (response["status"] as? String) ?? ""
            let challengeID = (response["challengeId"] as? String) ?? UUID().uuidString
            let serverOctaves = DuelOctaveCount(rawValue: (response["octaves"] as? Int) ?? normalizedOctaves.rawValue) ?? normalizedOctaves
            let requirementSummary = required.summary
            switch status {
            case "already_queued", "queued":
                DuelQuestTelemetryStore.shared.record(
                    .queueJoined,
                    on: telemetryDayKey(for: Date()),
                    weekKey: telemetryWeekKey(for: Date())
                )
                myOpenChallenge = DuelChallenge(
                    id: challengeID,
                    createdByUID: uid,
                    opponentUID: nil,
                    participants: [uid],
                    status: .open,
                    queueType: .open,
                    objective: "Queued • \(serverOctaves.title)",
                    scaleName: nil,
                    octaveCount: serverOctaves.rawValue,
                    requiredLeague: required.league.rawValue,
                    requiredMinTempoBPM: required.minimumTempoBPM,
                    creatorAccepted: true,
                    opponentAccepted: false,
                    opponentRequestedOctaves: nil,
                    createdAt: Date(),
                    acceptByAt: nil,
                    startedAt: nil,
                    submissionDeadlineAt: nil,
                    completedAt: nil,
                    creatorScore: nil,
                    opponentScore: nil,
                    winnerUID: nil,
                    creatorRatingDelta: 0,
                    opponentRatingDelta: 0
                )
                statusMessage = "Queued for \(requirementSummary). Waiting for another player."
            case "matched_pending_accept":
                myOpenChallenge = nil
                statusMessage = "Match found. Waiting for acceptance."
            case "blocked_active_duel":
                statusMessage = "Finish your active duel before queueing a new one."
            default:
                statusMessage = "Queue updated."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshTargetCandidates(force: Bool = false) async {
        guard let uid = configuredUID else { return }
        if !force,
           let lastTargetCandidatesRefreshAt,
           Date().timeIntervalSince(lastTargetCandidatesRefreshAt) < targetCandidatesRefreshCooldown {
            friendCandidates = friendCandidatesCache
            return
        }
        do {
            let friendRows = try await fetchFriendCandidates(for: uid)
            let sortedFriends = friendRows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            if friendCandidates != sortedFriends {
                friendCandidates = sortedFriends
            }
            friendCandidatesCache = sortedFriends
            lastTargetCandidatesRefreshAt = Date()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func inviteTargetedDuel(targetUID: String, source: DuelInviteSource, octaves: DuelOctaveCount = .one) async {
        guard let uid = configuredUID, uid != targetUID else { return }
        if userDisplayNames[targetUID] == nil {
            let knownName =
                friendCandidates.first(where: { $0.id == targetUID })?.displayName ??
                friendCandidatesCache.first(where: { $0.id == targetUID })?.displayName
            if let knownName, !knownName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userDisplayNames[targetUID] = knownName
            }
        }
        let required = activeLeagueRequirement
        let requestedOctaves = max(octaves.rawValue, required.octaves.rawValue)
        let normalizedOctaves = DuelOctaveCount(rawValue: requestedOctaves) ?? required.octaves
        if activeChallenges.contains(where: { $0.myScore(for: uid) == nil }) {
            statusMessage = "Finish your active duel before sending a new invitation."
            return
        }
        if outgoingInvites.contains(where: { $0.otherParticipant(for: uid) == targetUID }) {
            statusMessage = "You already sent an invite to this player."
            return
        }
        if incomingInvites.contains(where: { $0.otherParticipant(for: uid) == targetUID }) {
            statusMessage = "You have an incoming invite from this player."
            return
        }

        do {
            PBLog.firebase.info("Duel invite start uid=\(uid, privacy: .private) target=\(targetUID, privacy: .private) source=\(source.rawValue, privacy: .public)")
            _ = try await callDuelEndpoint(
                name: "duelInvite",
                body: [
                    "targetUID": targetUID,
                    "source": source.rawValue,
                    "octaves": normalizedOctaves.rawValue
                ]
            )
            DuelQuestTelemetryStore.shared.record(
                .inviteSent,
                on: telemetryDayKey(for: Date()),
                weekKey: telemetryWeekKey(for: Date())
            )
            statusMessage = "\(source.title) duel invitation sent (\(required.summary))."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func cancelOpenChallenge() async {
        guard configuredUID != nil else { return }
        let actionKey = "cancelOpenQueue"
        guard beginAction(key: actionKey) else { return }
        defer { endAction(key: actionKey) }
        let previousOpen = myOpenChallenge
        myOpenChallenge = nil
        do {
            _ = try await callDuelEndpoint(name: "duelQueueCancel", body: [:])
            PBLog.firebase.info("Duel queue cancel success")
            statusMessage = "Open duel canceled."
            clearRecoverableActionError()
        } catch {
            myOpenChallenge = previousOpen
            handleActionFailure(
                error,
                fallbackMessage: "Could not cancel queue right now.",
                retryTitle: "Retry Cancel",
                retryAction: .cancelQueue
            )
        }
    }

    func cancelInvite(challengeID: String) async {
        guard configuredUID != nil else { return }
        let actionKey = "cancelInvite:\(challengeID)"
        guard beginAction(key: actionKey) else { return }
        defer { endAction(key: actionKey) }
        let priorOutgoing = outgoingInvites
        outgoingInvites.removeAll { $0.id == challengeID }
        do {
            _ = try await callDuelEndpoint(
                name: "duelRespond",
                body: ["challengeId": challengeID, "accept": false]
            )
            PBLog.firebase.info("Duel invite cancel success challenge=\(challengeID, privacy: .public)")
            statusMessage = "Invite canceled."
            clearRecoverableActionError()
        } catch {
            outgoingInvites = priorOutgoing
            handleActionFailure(
                error,
                fallbackMessage: "Could not cancel invite right now.",
                retryTitle: "Retry Cancel",
                retryAction: .cancelInvite(challengeID: challengeID)
            )
        }
    }

    func acceptInvite(challengeID: String) async {
        guard configuredUID != nil else { return }
        let actionKey = "acceptInvite:\(challengeID)"
        guard beginAction(key: actionKey) else { return }
        defer { endAction(key: actionKey) }
        do {
            let result = try await callDuelEndpoint(
                name: "duelRespond",
                body: ["challengeId": challengeID, "accept": true]
            )
            PBLog.firebase.info("Duel invite accept success challenge=\(challengeID, privacy: .public)")
            let status = (result["status"] as? String) ?? ""
            DuelQuestTelemetryStore.shared.record(
                .acceptEntered,
                on: telemetryDayKey(for: Date()),
                weekKey: telemetryWeekKey(for: Date())
            )
            statusMessage = status == "activated" ? "Duel accepted. Match started." : "Duel accepted."
            clearRecoverableActionError()
        } catch {
            handleActionFailure(
                error,
                fallbackMessage: "Could not accept invite right now.",
                retryTitle: "Retry Accept",
                retryAction: .acceptInvite(challengeID: challengeID)
            )
        }
    }

    func declineInvite(challengeID: String) async {
        guard configuredUID != nil else { return }
        let actionKey = "declineInvite:\(challengeID)"
        guard beginAction(key: actionKey) else { return }
        defer { endAction(key: actionKey) }
        do {
            let result = try await callDuelEndpoint(
                name: "duelRespond",
                body: ["challengeId": challengeID, "accept": false]
            )
            PBLog.firebase.info("Duel invite decline success challenge=\(challengeID, privacy: .public)")
            let status = (result["status"] as? String) ?? ""
            statusMessage = status == "requeued_both" ? "Match declined. Searching new opponent." : "Invite declined."
            clearRecoverableActionError()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func submitDerivedAttempt(challengeID: String, metrics: DuelDerivedMetrics, requiredMinTempoBPM: Int = 0) async {
        guard configuredUID != nil else { return }
        let actionKey = "submitAttempt:\(challengeID)"
        guard beginAction(key: actionKey) else { return }
        defer { endAction(key: actionKey) }
        guard metrics.noteCount > 0, metrics.beatsAnalyzed > 0 else {
            statusMessage = "Metrics are incomplete."
            return
        }

        do {
            _ = try await callDuelEndpoint(
                name: "duelSubmitAttempt",
                body: [
                    "challengeId": challengeID,
                    "metrics": [
                        "intonationScore": metrics.intonationScore,
                        "rhythmScore": metrics.rhythmScore,
                        "consistencyScore": metrics.consistencyScore,
                        "noteCount": metrics.noteCount,
                        "beatsAnalyzed": metrics.beatsAnalyzed,
                        "tempoBPM": metrics.tempoBPM
                    ]
                ]
            )
            PBLog.firebase.info("Duel submit success challenge=\(challengeID, privacy: .public)")
            let now = Date()
            DuelQuestTelemetryStore.shared.record(
                .takeSubmitted,
                on: telemetryDayKey(for: now),
                weekKey: telemetryWeekKey(for: now)
            )
            if metrics.derivedScore >= 80 {
                DuelQuestTelemetryStore.shared.record(
                    .highScoreSubmission,
                    on: telemetryDayKey(for: now),
                    weekKey: telemetryWeekKey(for: now)
                )
            }
            if requiredMinTempoBPM > 0 && metrics.tempoBPM >= requiredMinTempoBPM {
                DuelQuestTelemetryStore.shared.record(
                    .tempoQualifiedSubmission,
                    on: telemetryDayKey(for: now),
                    weekKey: telemetryWeekKey(for: now)
                )
            }
            statusMessage = "Attempt submitted."
            clearRecoverableActionError()
        } catch {
            handleActionFailure(
                error,
                fallbackMessage: "Could not submit take right now.",
                retryTitle: "Retry Submit",
                retryAction: .submitAttempt(
                    challengeID: challengeID,
                    metrics: metrics,
                    requiredMinTempoBPM: requiredMinTempoBPM
                )
            )
        }
    }

    func fetchParticipantCards(for challenge: DuelChallenge) async -> [String: DuelParticipantCard] {
        let unique = Array(Set(challenge.participants))
        guard !unique.isEmpty else { return [:] }
        var output: [String: DuelParticipantCard] = [:]
        for chunk in unique.chunked(into: 10) {
            do {
                let snap = try await db.collection("users")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                for doc in snap.documents {
                    let data = doc.data()
                    let displayName = ((data["displayName"] as? String) ?? "Player")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let lifetimeMatches = max(0, (data["duelWins"] as? Int) ?? 0)
                        + max(0, (data["duelLosses"] as? Int) ?? 0)
                        + max(0, (data["duelDraws"] as? Int) ?? 0)
                    let rating = lifetimeMatches > 0 ? max(0, (data["duelRating"] as? Int) ?? 0) : 0
                    output[doc.documentID] = DuelParticipantCard(
                        id: doc.documentID,
                        displayName: displayName.isEmpty ? "Player" : displayName,
                        publicLevel: max(1, (data["publicLevel"] as? Int) ?? 1),
                        duelRating: rating
                    )
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
        return output
    }

    func clearReadyChallenge() {
        readyChallengeID = nil
    }

    private func attachRealtime(for uid: String) {
        let userListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snap, _ in
            guard let self else { return }
            Task { @MainActor in
                let data = snap?.data() ?? [:]
                let previousRating = self.duelRating
                let previousWins = self.duelWins
                let previousLosses = self.duelLosses
                let previousDraws = self.duelDraws
                let previousSeasonKey = self.seasonKey

                let newRating = max(0, (data["duelRating"] as? Int) ?? 0)
                let newWins = max(0, (data["duelWins"] as? Int) ?? 0)
                let newLosses = max(0, (data["duelLosses"] as? Int) ?? 0)
                let newDraws = max(0, (data["duelDraws"] as? Int) ?? 0)
                let newSeasonKey = (data["duelSeasonKey"] as? String) ?? self.currentSeasonKey()
                let newSeasonPoints = max(0, (data["duelSeasonPoints"] as? Int) ?? 0)
                let newSeasonMatches = max(0, (data["duelSeasonMatches"] as? Int) ?? 0)
                let newSeasonWins = max(0, (data["duelSeasonWins"] as? Int) ?? 0)

                if self.duelRating != newRating { self.duelRating = newRating }
                if self.duelWins != newWins { self.duelWins = newWins }
                if self.duelLosses != newLosses { self.duelLosses = newLosses }
                if self.duelDraws != newDraws { self.duelDraws = newDraws }
                if self.seasonKey != newSeasonKey { self.seasonKey = newSeasonKey }
                if self.seasonPoints != newSeasonPoints { self.seasonPoints = newSeasonPoints }
                if self.seasonMatches != newSeasonMatches { self.seasonMatches = newSeasonMatches }
                if self.seasonWins != newSeasonWins { self.seasonWins = newSeasonWins }
                self.leaderboardCache = self.leaderboardCache.filter { _, cached in
                    cached.seasonKey == newSeasonKey
                }

                let duelStatsChanged = previousRating != newRating ||
                    previousWins != newWins ||
                    previousLosses != newLosses ||
                    previousDraws != newDraws ||
                    previousSeasonKey != newSeasonKey
                if duelStatsChanged {
                    self.leaderboardCache.removeAll()
                }
            }
        }

        let challengeQuery = db.collection("duelChallenges")
            .whereField("participants", arrayContains: uid)
        let challengeListener = challengeQuery.addSnapshotListener { [weak self] snap, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleChallengeSnapshot(uid: uid, snapshot: snap)
            }
        }

        listeners = [userListener, challengeListener]
    }

    private func handleChallengeSnapshot(uid: String, snapshot: QuerySnapshot?) {
        let docs = snapshot?.documents ?? []
        var inlineDisplayNames: [String: String] = [:]
        for doc in docs {
            let data = doc.data()
            let createdByUID = (data["createdByUid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let createdByName = (data["createdByDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !createdByUID.isEmpty, !createdByName.isEmpty {
                inlineDisplayNames[createdByUID] = createdByName
            }
            let opponentUID = (data["opponentUid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let opponentName = (data["opponentDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !opponentUID.isEmpty, !opponentName.isEmpty {
                inlineDisplayNames[opponentUID] = opponentName
            }
        }
        if !inlineDisplayNames.isEmpty {
            var merged = userDisplayNames
            merged.merge(inlineDisplayNames) { _, new in new }
            if merged != userDisplayNames {
                userDisplayNames = merged
            }
        }

        let rows = docs
            .compactMap(parseChallenge)
            .sorted { lhs, rhs in
                let l = lhs.completedAt ?? lhs.startedAt ?? lhs.createdAt
                let r = rhs.completedAt ?? rhs.startedAt ?? rhs.createdAt
                return l > r
            }

        prefetchDisplayNames(for: rows)

        let hasPendingActiveForMe = rows.contains {
            $0.status == .active && $0.myScore(for: uid) == nil
        }
        let nextMyOpenChallenge = hasPendingActiveForMe ? nil : rows.first {
            $0.status == .open && $0.createdByUID == uid
        }
        let nextIncomingInvites = rows.filter {
            $0.status == .invited && $0.opponentUID == uid
        }
        let nextOutgoingInvites = rows.filter {
            $0.status == .invited && $0.createdByUID == uid
        }
        let nextActiveChallenges = rows.filter { $0.status == .active }
        let completed = rows.filter { $0.status == .completed }
        let nextMatchHistory = completed
        let nextRecentCompleted = completed.prefix(8).map { $0 }

        if myOpenChallenge != nextMyOpenChallenge { myOpenChallenge = nextMyOpenChallenge }
        if incomingInvites != nextIncomingInvites { incomingInvites = nextIncomingInvites }
        if outgoingInvites != nextOutgoingInvites { outgoingInvites = nextOutgoingInvites }
        if activeChallenges != nextActiveChallenges { activeChallenges = nextActiveChallenges }
        if matchHistory != nextMatchHistory { matchHistory = nextMatchHistory }
        if recentCompleted != nextRecentCompleted { recentCompleted = nextRecentCompleted }

        let statusByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.status) })
        if didReceiveInitialChallengeSnapshot {
            let newlyIncomingInvite = rows.first {
                $0.status == .invited &&
                $0.opponentUID == uid &&
                priorChallengeStatusByID[$0.id] == nil
            }
            if let newlyIncomingInvite {
                let challengerUID = newlyIncomingInvite.createdByUID
                if let cached = resolvedDisplayName(for: challengerUID) {
                    PBNotificationCenter.maybeScheduleDuelNotification(
                        title: "Duel Challenge",
                        body: "\(cached) challenged you.",
                        challengeID: newlyIncomingInvite.id
                    )
                } else {
                    Task { [weak self] in
                        guard let self else { return }
                        let resolved = await self.fetchDisplayName(uid: challengerUID) ?? self.displayNameFallback(for: challengerUID)
                        await MainActor.run {
                            PBNotificationCenter.maybeScheduleDuelNotification(
                                title: "Duel Challenge",
                                body: "\(resolved) challenged you.",
                                challengeID: newlyIncomingInvite.id
                            )
                        }
                    }
                }
            }
            let newlyActive = rows.first {
                let previous = priorChallengeStatusByID[$0.id]
                return $0.status == .active && previous == .invited
            }
            if let newlyActive {
                readyChallengeID = newlyActive.id
                statusMessage = "Duel accepted. Tap Enter."
                PBNotificationCenter.maybeScheduleDuelNotification(
                    title: "Duel Ready",
                    body: "A duel is active. Tap to enter.",
                    challengeID: newlyActive.id
                )
            }
        }
        priorChallengeStatusByID = statusByID
        didReceiveInitialChallengeSnapshot = true
    }

    private func displayName(for uid: String) -> String {
        resolvedDisplayName(for: uid) ?? displayNameFallback(for: uid)
    }

    private func resolvedDisplayName(for uid: String) -> String? {
        let resolved = (userDisplayNames[uid] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else { return nil }
        return resolved
    }

    private func displayNameFallback(for uid: String) -> String {
        uid.count > 8 ? "Player \(uid.prefix(8))" : "Player"
    }

    private func fetchDisplayName(uid: String) async -> String? {
        let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty else { return nil }
        do {
            let doc = try await db.collection("users").document(normalizedUID).getDocument()
            let displayName = ((doc.data()?["displayName"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty else { return nil }
            userDisplayNames[normalizedUID] = displayName
            return displayName
        } catch {
            return nil
        }
    }

    private func ensureProfileDefaults(uid: String) async {
        let key = currentSeasonKey()
        do {
            let ref = db.collection("users").document(uid)
            let snap = try await ref.getDocument()
            let data = snap.data() ?? [:]

            var patch: [String: Any] = [:]
            if data["duelRating"] == nil { patch["duelRating"] = 0 }
            if data["duelLeague"] == nil { patch["duelLeague"] = DuelLeagueTier.bronze.rawValue }
            if data["duelWins"] == nil { patch["duelWins"] = 0 }
            if data["duelLosses"] == nil { patch["duelLosses"] = 0 }
            if data["duelDraws"] == nil { patch["duelDraws"] = 0 }
            if data["duelTokens"] == nil { patch["duelTokens"] = 0 }
            if data["duelSeasonKey"] == nil { patch["duelSeasonKey"] = key }
            if data["duelSeasonPoints"] == nil { patch["duelSeasonPoints"] = 0 }
            if data["duelSeasonMatches"] == nil { patch["duelSeasonMatches"] = 0 }
            if data["duelSeasonWins"] == nil { patch["duelSeasonWins"] = 0 }
            if data["duelSeasonRatingDelta"] == nil { patch["duelSeasonRatingDelta"] = 0 }

            guard !patch.isEmpty else { return }
            patch["updatedAt"] = FieldValue.serverTimestamp()
            try await ref.setData(patch, merge: true)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func fetchFriendCandidates(for uid: String) async throws -> [DuelTargetCandidate] {
        let snap = try await db.collection("friendships")
            .document(uid)
            .collection("buddies")
            .getDocuments()

        return snap.documents.compactMap { doc in
            let data = doc.data()
            let name = ((data["displayName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return DuelTargetCandidate(
                id: doc.documentID,
                displayName: name,
                source: .friend,
                subtitle: "Friend"
            )
        }
    }

    func refreshSeasonLeaderboard(scope: DuelLeaderboardScope, force: Bool = false) async {
        guard let uid = configuredUID else { return }
        let key = currentSeasonKey()
        if !force,
           let cached = leaderboardCache[scope],
           cached.seasonKey == key,
           Date().timeIntervalSince(cached.fetchedAt) < leaderboardRefreshCooldown {
            if leaderboardRows != cached.rows {
                leaderboardRows = cached.rows
            }
            return
        }
        do {
            var rows: [DuelLeaderboardRow] = []
            switch scope {
            case .global:
                // Keep this index-free for launch stability: fetch visible users and sort client-side.
                let snap = try await db.collection("users")
                    .limit(to: 200)
                    .getDocuments()
                rows = snap.documents
                    .compactMap { parseLeaderboardRow($0, currentSeasonKey: key) }
                    .sorted(by: leaderboardSort)
                    .prefix(20)
                    .map { $0 }
            case .friends:
                let ids = try await friendIDs(for: uid) + [uid]
                rows = try await fetchLeaderboardRows(uids: ids, currentSeasonKey: key)
                    .sorted(by: leaderboardSort)
                    .prefix(20)
                    .map { $0 }
            }
            if leaderboardRows != rows {
                leaderboardRows = rows
            }
            leaderboardCache[scope] = (seasonKey: key, rows: rows, fetchedAt: Date())
        } catch {
            statusMessage = error.localizedDescription
            if !leaderboardRows.isEmpty {
                leaderboardRows = []
            }
        }
    }

    private func friendIDs(for uid: String) async throws -> [String] {
        let snap = try await db.collection("friendships")
            .document(uid)
            .collection("buddies")
            .getDocuments()
        return snap.documents.map(\.documentID)
    }

    private func fetchLeaderboardRows(uids: [String], currentSeasonKey: String) async throws -> [DuelLeaderboardRow] {
        let unique = Array(Set(uids))
        guard !unique.isEmpty else { return [] }
        var rows: [DuelLeaderboardRow] = []

        for chunk in unique.chunked(into: 10) {
            let snap = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for doc in snap.documents {
                guard let row = parseLeaderboardRow(doc, currentSeasonKey: currentSeasonKey) else { continue }
                rows.append(row)
            }
        }
        return rows
    }

    private func parseLeaderboardRow(_ doc: QueryDocumentSnapshot, currentSeasonKey: String) -> DuelLeaderboardRow? {
        parseLeaderboardRow(documentID: doc.documentID, data: doc.data(), currentSeasonKey: currentSeasonKey)
    }

    private func parseLeaderboardRow(documentID: String, data: [String: Any], currentSeasonKey: String) -> DuelLeaderboardRow? {
        let displayName = ((data["displayName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return nil }
        let isCurrentSeason = ((data["duelSeasonKey"] as? String) ?? "") == currentSeasonKey
        let seasonMatches = isCurrentSeason ? max(0, (data["duelSeasonMatches"] as? Int) ?? 0) : 0
        let rating = max(0, (data["duelRating"] as? Int) ?? 0)
        return DuelLeaderboardRow(
            id: documentID,
            displayName: displayName,
            avatarID: ((data["avatarID"] as? String) ?? "avatar_note").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "avatar_note" : ((data["avatarID"] as? String) ?? "avatar_note"),
            profilePhotoURL: ((data["profilePhotoURL"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            publicLevel: max(1, (data["publicLevel"] as? Int) ?? (data["level"] as? Int) ?? 1),
            points: isCurrentSeason ? max(0, (data["duelSeasonPoints"] as? Int) ?? 0) : 0,
            rating: rating,
            wins: isCurrentSeason ? max(0, (data["duelSeasonWins"] as? Int) ?? 0) : 0,
            matches: seasonMatches
        )
    }

    private func leaderboardSort(_ lhs: DuelLeaderboardRow, _ rhs: DuelLeaderboardRow) -> Bool {
        if lhs.points != rhs.points { return lhs.points > rhs.points }
        if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
        if lhs.matches != rhs.matches { return lhs.matches > rhs.matches }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func fetchUserRatings(uids: [String]) async throws -> [String: Int] {
        let unique = Array(Set(uids))
        guard !unique.isEmpty else { return [:] }
        var output: [String: Int] = [:]
        for chunk in unique.chunked(into: 10) {
            let snap = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for doc in snap.documents {
                output[doc.documentID] = max(0, (doc.data()["duelRating"] as? Int) ?? 0)
            }
        }
        return output
    }

    private func callDuelEndpoint(name: String, body: [String: Any]) async throws -> [String: Any] {
        guard let baseURL = AppInfo.duelFunctionsBaseURL else {
            throw NSError(
                domain: "PracticeBuddy.Duel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cloud Functions URL is missing."]
            )
        }
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "PracticeBuddy.Duel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No authenticated user."]
            )
        }
        let idToken = try await user.getIDToken()
        let endpoint = baseURL.appendingPathComponent(name)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        PBLog.firebase.info("Duel endpoint request name=\(name, privacy: .public)")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "PracticeBuddy.Duel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server response."]
            )
        }

        let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        if (200..<300).contains(http.statusCode) {
            PBLog.firebase.info("Duel endpoint success name=\(name, privacy: .public) code=\(http.statusCode, privacy: .public)")
            return json ?? [:]
        }

        let errorMessage = (json?["error"] as? String) ?? "Request failed (\(http.statusCode))."
        PBLog.firebase.error("Duel endpoint failure name=\(name, privacy: .public) code=\(http.statusCode, privacy: .public) error=\(errorMessage, privacy: .public)")
        throw NSError(
            domain: "PracticeBuddy.Duel",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: errorMessage]
        )
    }

    private func currentSeasonKey() -> String {
        seasonKeyToken(for: Date())
    }

    private func telemetryDayKey(for date: Date) -> String {
        telemetryDayFormatter.string(from: date)
    }

    private func telemetryWeekKey(for date: Date) -> String {
        seasonKeyToken(for: date)
    }

    private func seasonKeyToken(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return "\(year)-W\(week)"
    }

    private func parseChallenge(_ doc: DocumentSnapshot) -> DuelChallenge? {
        guard let data = doc.data(),
              let createdByUID = data["createdByUid"] as? String,
              let statusRaw = data["status"] as? String,
              let status = DuelChallengeStatus(rawValue: statusRaw) else {
            return nil
        }
        let queueTypeRaw = (data["queueType"] as? String) ?? DuelChallengeQueueType.open.rawValue
        let queueType = DuelChallengeQueueType(rawValue: queueTypeRaw) ?? .open

        let participants = (data["participants"] as? [String]) ?? [createdByUID]
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        let acceptByAt = (data["acceptByAt"] as? Timestamp)?.dateValue()
        let startedAt = (data["startedAt"] as? Timestamp)?.dateValue()
        let deadlineAt = (data["submissionDeadlineAt"] as? Timestamp)?.dateValue()
        let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()

        return DuelChallenge(
            id: doc.documentID,
            createdByUID: createdByUID,
            opponentUID: data["opponentUid"] as? String,
            participants: participants,
            status: status,
            queueType: queueType,
            objective: (data["objective"] as? String) ?? "Random scale challenge",
            scaleName: data["scaleName"] as? String,
            octaveCount: min(max((data["octaveCount"] as? Int) ?? 1, 1), 3),
            requiredLeague: data["requiredLeague"] as? String,
            requiredMinTempoBPM: max(0, (data["requiredMinTempoBPM"] as? Int) ?? 0),
            creatorAccepted: (data["creatorAccepted"] as? Bool) ?? true,
            opponentAccepted: (data["opponentAccepted"] as? Bool) ?? false,
            opponentRequestedOctaves: data["opponentRequestedOctaves"] as? Int,
            createdAt: createdAt,
            acceptByAt: acceptByAt,
            startedAt: startedAt,
            submissionDeadlineAt: deadlineAt,
            completedAt: completedAt,
            creatorScore: data["creatorScore"] as? Int,
            opponentScore: data["opponentScore"] as? Int,
            winnerUID: data["winnerUid"] as? String,
            creatorRatingDelta: data["creatorRatingDelta"] as? Int ?? 0,
            opponentRatingDelta: data["opponentRatingDelta"] as? Int ?? 0
        )
    }

    private func prefetchDisplayNames(for rows: [DuelChallenge]) {
        let uids = Array(Set(rows.flatMap(\.participants)))
        guard !uids.isEmpty else { return }
        let missing = uids.filter { userDisplayNames[$0] == nil }
        guard !missing.isEmpty else { return }
        pendingDisplayNameUIDs.formUnion(missing)
        guard !isPrefetchingDisplayNames else { return }
        isPrefetchingDisplayNames = true
        flushDisplayNamePrefetchQueue()
    }

    private func flushDisplayNamePrefetchQueue() {
        let queued = pendingDisplayNameUIDs.filter { userDisplayNames[$0] == nil }
        guard !queued.isEmpty else {
            isPrefetchingDisplayNames = false
            return
        }
        pendingDisplayNameUIDs = []

        let ids = Array(queued)
        Task.detached(priority: .utility) { [weak self] in
            var fetched: [String: String] = [:]
            var lastErrorMessage: String?
            let store = Firestore.firestore()
            var start = 0
            while start < ids.count {
                let end = Swift.min(start + 10, ids.count)
                let chunk = Array(ids[start..<end])
                start = end
                do {
                    let snap = try await store.collection("users")
                        .whereField(FieldPath.documentID(), in: chunk)
                        .getDocuments()
                    for doc in snap.documents {
                        let displayName = ((doc.data()["displayName"] as? String) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !displayName.isEmpty {
                            fetched[doc.documentID] = displayName
                        }
                    }
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }

            guard let strongSelf = self else { return }
            let fetchedResult = fetched
            let errorMessage = lastErrorMessage
            await MainActor.run {
                if !fetchedResult.isEmpty {
                    var merged = strongSelf.userDisplayNames
                    merged.merge(fetchedResult) { _, new in new }
                    if merged != strongSelf.userDisplayNames {
                        strongSelf.userDisplayNames = merged
                    }
                }
                if let errorMessage, !errorMessage.isEmpty {
                    strongSelf.statusMessage = errorMessage
                }
                strongSelf.isPrefetchingDisplayNames = false
                strongSelf.flushDisplayNamePrefetchQueue()
            }
        }
    }

    private func beginAction(key: String) -> Bool {
        guard !inFlightActionKeys.contains(key) else { return false }
        inFlightActionKeys.insert(key)
        isActionBusy = !inFlightActionKeys.isEmpty
        return true
    }

    private func endAction(key: String) {
        inFlightActionKeys.remove(key)
        isActionBusy = !inFlightActionKeys.isEmpty
    }

    private func handleActionFailure(
        _ error: Error,
        fallbackMessage: String,
        retryTitle: String,
        retryAction: DuelPendingRetryAction
    ) {
        let nsError = error as NSError
        let raw = ((nsError.userInfo[NSLocalizedDescriptionKey] as? String) ?? error.localizedDescription)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()

        let networkCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet
        ]
        let isNetwork = nsError.domain == NSURLErrorDomain && networkCodes.contains(nsError.code)
        let isServer = nsError.code >= 500
        let retryable = isNetwork || isServer || lower.contains("request failed")

        let userMessage: String
        if lower.contains("challenge not pending") {
            userMessage = "This invite is no longer pending."
        } else if lower.contains("challenge is not active") || lower.contains("submission window is closed") {
            userMessage = "This duel is no longer active."
        } else if lower.contains("tempo too low") || lower.contains("capture too short") || lower.contains("metrics are incomplete") {
            userMessage = raw
        } else if retryable {
            userMessage = "Temporary connection issue. Try again."
        } else {
            userMessage = raw.isEmpty ? fallbackMessage : raw
        }

        statusMessage = userMessage
        if retryable {
            pendingRetryAction = retryAction
            recoverableActionError = DuelRecoverableActionError(
                message: userMessage,
                retryTitle: retryTitle
            )
        } else {
            clearRecoverableActionError()
        }
    }

}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var index = 0
        var chunks: [[Element]] = []
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
