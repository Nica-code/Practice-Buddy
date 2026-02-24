import Foundation
import Combine
import FirebaseFirestore

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
    let isOwned: Bool
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

@MainActor
final class JourneyProgressManager: ObservableObject {
    private enum Keys {
        static let seeded = "pb.journey.seeded"
        static let totalXP = "pb.journey.totalXP"
        static let processedSessionIDs = "pb.journey.processedSessionIDs"
        static let xpLedgerByDay = "pb.journey.xpLedgerByDay"
        static let tokenBalance = "pb.journey.tokenBalance"
        static let claimedQuestRewardKeys = "pb.journey.claimedQuestRewardKeys"
        static let ownedRewardIDs = "pb.journey.ownedRewardIDs"
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
    @Published private(set) var rewards: [JourneyRewardItem] = []

    private var processedSessionIDs: Set<UUID> = []
    private var xpLedgerByDay: [String: Int] = [:]
    private var claimedQuestRewardKeys: Set<String> = []
    private var ownedRewardIDs: Set<String> = []
    private let defaults = UserDefaults.standard
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
        loadOwnedRewards()
        tokenBalance = max(0, defaults.integer(forKey: Keys.tokenBalance))
        recalculateLevel()
        todayXP = xpLedgerByDay[dayKey(for: Date())] ?? 0
        refreshRewards()
    }

    func handleSessionSnapshot(_ sessions: [PracticeSessionModel]) {
        if !defaults.bool(forKey: Keys.seeded) {
            seedFromExistingSessions(sessions)
            defaults.set(true, forKey: Keys.seeded)
        } else {
            awardXPForNewSessions(sessions)
        }
        updateQuestProgress(from: sessions)
    }

    func questRewardStatus(for quest: JourneyQuestRow, period: JourneyQuestPeriod) -> JourneyQuestRewardStatus {
        guard quest.isCompleted else { return .locked }
        if claimedQuestRewardKeys.contains(questRewardClaimKey(for: quest.id, period: period, at: Date())) {
            return .claimed
        }
        return .claimable
    }

    @discardableResult
    func claimQuestReward(for quest: JourneyQuestRow, period: JourneyQuestPeriod) -> Bool {
        guard questRewardStatus(for: quest, period: period) == .claimable else { return false }
        claimedQuestRewardKeys.insert(questRewardClaimKey(for: quest.id, period: period, at: Date()))
        tokenBalance += max(0, quest.rewardTokens)
        persistAll()
        return true
    }

    @discardableResult
    func claimRewardItem(id: String) -> Bool {
        guard !ownedRewardIDs.contains(id),
              let item = baseRewards.first(where: { $0.id == id }),
              tokenBalance >= item.costTokens else {
            return false
        }

        tokenBalance -= item.costTokens
        ownedRewardIDs.insert(id)
        refreshRewards()
        persistAll()
        return true
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
        let cal = Calendar.current
        let now = Date()
        let todayInterval = cal.dateInterval(of: .day, for: now)
        let weekInterval = cal.dateInterval(of: .weekOfYear, for: now)

        let todaySessions = sessions.filter { s in
            guard let it = todayInterval else { return false }
            return s.date >= it.start && s.date < it.end
        }
        let weekSessions = sessions.filter { s in
            guard let it = weekInterval else { return false }
            return s.date >= it.start && s.date < it.end
        }

        let todayMinutes = todaySessions.reduce(0) { $0 + practiceMinutes(for: $1) }
        let todayReflectiveSessions = todaySessions.filter(hasReflectionContent).count
        let todayCount = todaySessions.count

        let weekMinutes = weekSessions.reduce(0) { $0 + practiceMinutes(for: $1) }
        let activeDays = Set(weekSessions.map { cal.startOfDay(for: $0.date) }).count

        dailyQuests = [
            JourneyQuestRow(
                id: "dq_minutes",
                title: "Daily Time Builder",
                progress: todayMinutes,
                target: 25,
                rewardTokens: 15,
                subtitle: "Practice 25 minutes today"
            ),
            JourneyQuestRow(
                id: "dq_sessions",
                title: "Two Session Day",
                progress: todayCount,
                target: 2,
                rewardTokens: 12,
                subtitle: "Complete 2 sessions today"
            ),
            JourneyQuestRow(
                id: "dq_reflect",
                title: "Reflect & Improve",
                progress: todayReflectiveSessions,
                target: 1,
                rewardTokens: 10,
                subtitle: "Save 1 session with notes/reflection"
            )
        ]

        weeklyQuests = [
            JourneyQuestRow(
                id: "wq_minutes",
                title: "Weekly Volume",
                progress: weekMinutes,
                target: 180,
                rewardTokens: 50,
                subtitle: "Reach 180 minutes this week"
            ),
            JourneyQuestRow(
                id: "wq_days",
                title: "Consistency Week",
                progress: activeDays,
                target: 5,
                rewardTokens: 40,
                subtitle: "Practice on 5 different days"
            )
        ]
    }

    private func hasReflectionContent(_ session: PracticeSessionModel) -> Bool {
        if !session.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !session.noteFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !session.noteStructuredJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
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

        level = currentLevel
        xpIntoLevel = remaining
        xpForNextLevel = xpCostToAdvance(from: currentLevel)
        xpToNextLevel = max(0, xpForNextLevel - xpIntoLevel)
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
        saveOwnedRewards()
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
                id: "reward_confetti",
                title: "Confetti Burst",
                subtitle: "Unlock a new celebration style for level-up moments.",
                costTokens: 40,
                isOwned: false
            ),
            JourneyRewardItem(
                id: "reward_profile_frame",
                title: "Studio Profile Frame",
                subtitle: "Special profile frame for studio and buddies surfaces.",
                costTokens: 60,
                isOwned: false
            ),
            JourneyRewardItem(
                id: "reward_theme_badge",
                title: "Theme Collector Badge",
                subtitle: "Exclusive badge for your Journey profile.",
                costTokens: 80,
                isOwned: false
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
                isOwned: ownedRewardIDs.contains(item.id)
            )
        }
    }
}

enum DuelLeagueTier: String, CaseIterable {
    case bronze
    case silver
    case gold

    var title: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }

    var minRating: Int {
        switch self {
        case .bronze: return 1000
        case .silver: return 1150
        case .gold: return 1300
        }
    }

    var next: DuelLeagueTier? {
        switch self {
        case .bronze: return .silver
        case .silver: return .gold
        case .gold: return nil
        }
    }

    static func forRating(_ rating: Int) -> DuelLeagueTier {
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
    case studio

    var title: String {
        switch self {
        case .friend: return "Friend"
        case .studio: return "Studio"
        }
    }
}

struct DuelTargetCandidate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let source: DuelInviteSource
    let subtitle: String
}

enum DuelLeaderboardScope: String, CaseIterable, Identifiable {
    case global = "Global"
    case friends = "Friends"
    case studio = "Studio"

    var id: String { rawValue }
}

struct DuelLeaderboardRow: Identifiable, Equatable {
    let id: String
    let displayName: String
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

    var derivedScore: Int {
        let weighted = (Double(intonationScore) * 0.5) + (Double(rhythmScore) * 0.35) + (Double(consistencyScore) * 0.15)
        return min(max(Int(weighted.rounded()), 0), 100)
    }
}

struct DuelChallenge: Identifiable, Equatable {
    let id: String
    let createdByUID: String
    let opponentUID: String?
    let participants: [String]
    let status: DuelChallengeStatus
    let queueType: DuelChallengeQueueType
    let objective: String
    let createdAt: Date
    let startedAt: Date?
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

@MainActor
final class DuelLeagueManager: ObservableObject {
    @Published private(set) var myOpenChallenge: DuelChallenge?
    @Published private(set) var incomingInvites: [DuelChallenge] = []
    @Published private(set) var outgoingInvites: [DuelChallenge] = []
    @Published private(set) var activeChallenges: [DuelChallenge] = []
    @Published private(set) var recentCompleted: [DuelChallenge] = []
    @Published private(set) var friendCandidates: [DuelTargetCandidate] = []
    @Published private(set) var studioCandidates: [DuelTargetCandidate] = []
    @Published private(set) var seasonKey: String = ""
    @Published private(set) var seasonPoints: Int = 0
    @Published private(set) var seasonMatches: Int = 0
    @Published private(set) var seasonWins: Int = 0
    @Published private(set) var leaderboardRows: [DuelLeaderboardRow] = []
    @Published private(set) var duelRating: Int = 1000
    @Published private(set) var duelWins: Int = 0
    @Published private(set) var duelLosses: Int = 0
    @Published private(set) var duelDraws: Int = 0
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?

    var leagueTier: DuelLeagueTier { DuelLeagueTier.forRating(duelRating) }

    private var db: Firestore { Firestore.firestore() }
    private var listeners: [ListenerRegistration] = []
    private var configuredUID: String?
    private var lastTargetCandidatesRefreshAt: Date?
    private var friendCandidatesCache: [DuelTargetCandidate] = []
    private var studioCandidatesCache: [DuelTargetCandidate] = []
    private var leaderboardCache: [DuelLeaderboardScope: (seasonKey: String, rows: [DuelLeaderboardRow], fetchedAt: Date)] = [:]
    private let targetCandidatesRefreshCooldown: TimeInterval = 30
    private let leaderboardRefreshCooldown: TimeInterval = 30

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
        friendCandidates = []
        studioCandidates = []
        seasonKey = ""
        seasonPoints = 0
        seasonMatches = 0
        seasonWins = 0
        leaderboardRows = []
        duelRating = 1000
        duelWins = 0
        duelLosses = 0
        duelDraws = 0
        isLoading = false
        statusMessage = nil
        lastTargetCandidatesRefreshAt = nil
        friendCandidatesCache = []
        studioCandidatesCache = []
        leaderboardCache = [:]
    }

    func queueAsyncScaleDuel() async {
        guard let uid = configuredUID else { return }
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
            if try await tryJoinOpenChallenge(uid: uid) {
                statusMessage = "Matched. Submit your score when done."
                return
            }

            let ref = db.collection("duelChallenges").document()
            try await ref.setData([
                "createdByUid": uid,
                "opponentUid": NSNull(),
                "participants": [uid],
                "status": DuelChallengeStatus.open.rawValue,
                "queueType": DuelChallengeQueueType.open.rawValue,
                "objective": "Random scale challenge",
                "creatorScore": NSNull(),
                "opponentScore": NSNull(),
                "winnerUid": NSNull(),
                "creatorRatingDelta": 0,
                "opponentRatingDelta": 0,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "startedAt": NSNull(),
                "completedAt": NSNull()
            ])
            // Optimistic local state so the UI flips to "Cancel" immediately
            // instead of waiting for listener round-trip.
            myOpenChallenge = DuelChallenge(
                id: ref.documentID,
                createdByUID: uid,
                opponentUID: nil,
                participants: [uid],
                status: .open,
                queueType: .open,
                objective: "Random scale challenge",
                createdAt: Date(),
                startedAt: nil,
                completedAt: nil,
                creatorScore: nil,
                opponentScore: nil,
                winnerUID: nil,
                creatorRatingDelta: 0,
                opponentRatingDelta: 0
            )
            statusMessage = "Queued. Waiting for another player."
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
            studioCandidates = studioCandidatesCache
            return
        }
        async let friends = fetchFriendCandidates(for: uid)
        async let studio = fetchStudioCandidates(for: uid)
        do {
            let (friendRows, studioRows) = try await (friends, studio)
            let sortedFriends = friendRows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            let sortedStudio = studioRows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            friendCandidates = sortedFriends
            studioCandidates = sortedStudio
            friendCandidatesCache = sortedFriends
            studioCandidatesCache = sortedStudio
            lastTargetCandidatesRefreshAt = Date()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func inviteTargetedDuel(targetUID: String, source: DuelInviteSource) async {
        guard let uid = configuredUID, uid != targetUID else { return }
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
            let ref = db.collection("duelChallenges").document()
            try await ref.setData([
                "createdByUid": uid,
                "opponentUid": targetUID,
                "participants": [uid, targetUID],
                "status": DuelChallengeStatus.invited.rawValue,
                "queueType": source.rawValue,
                "objective": "Random scale challenge",
                "creatorScore": NSNull(),
                "opponentScore": NSNull(),
                "winnerUid": NSNull(),
                "creatorRatingDelta": 0,
                "opponentRatingDelta": 0,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "startedAt": NSNull(),
                "completedAt": NSNull()
            ])
            statusMessage = "\(source.title) duel invitation sent."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func cancelOpenChallenge() async {
        guard let uid = configuredUID, let open = myOpenChallenge, open.createdByUID == uid else { return }
        let previousOpen = open
        myOpenChallenge = nil
        do {
            try await db.collection("duelChallenges").document(open.id).setData([
                "status": DuelChallengeStatus.canceled.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            statusMessage = "Open duel canceled."
        } catch {
            myOpenChallenge = previousOpen
            statusMessage = error.localizedDescription
        }
    }

    func cancelInvite(challengeID: String) async {
        guard configuredUID != nil else { return }
        do {
            try await db.collection("duelChallenges").document(challengeID).setData([
                "status": DuelChallengeStatus.canceled.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            statusMessage = "Invite canceled."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func acceptInvite(challengeID: String) async {
        guard configuredUID != nil else { return }
        do {
            try await db.collection("duelChallenges").document(challengeID).setData([
                "status": DuelChallengeStatus.active.rawValue,
                "startedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            statusMessage = "Duel accepted."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func declineInvite(challengeID: String) async {
        guard configuredUID != nil else { return }
        do {
            try await db.collection("duelChallenges").document(challengeID).setData([
                "status": DuelChallengeStatus.canceled.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            statusMessage = "Invite declined."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func submitDerivedAttempt(challengeID: String, metrics: DuelDerivedMetrics) async {
        guard let uid = configuredUID else { return }
        let challengeRef = db.collection("duelChallenges").document(challengeID)
        let derivedScore = metrics.derivedScore
        guard metrics.noteCount > 0, metrics.beatsAnalyzed > 0 else {
            statusMessage = "Metrics are incomplete."
            return
        }

        do {
            _ = try await runTransaction { txn in
                let challengeSnap = try txn.getDocument(challengeRef)
                guard let data = challengeSnap.data(),
                      let statusRaw = data["status"] as? String,
                      statusRaw == DuelChallengeStatus.active.rawValue,
                      let createdByUID = data["createdByUid"] as? String,
                      let participants = data["participants"] as? [String],
                      participants.contains(uid),
                      participants.count == 2 else {
                    return false
                }

                let opponentUID = participants.first(where: { $0 != uid }) ?? ""
                guard !opponentUID.isEmpty else { return false }

                let attemptRef = challengeRef.collection("attempts").document(uid)
                txn.setData([
                    "uid": uid,
                    "intonationScore": metrics.intonationScore,
                    "rhythmScore": metrics.rhythmScore,
                    "consistencyScore": metrics.consistencyScore,
                    "noteCount": metrics.noteCount,
                    "beatsAnalyzed": metrics.beatsAnalyzed,
                    "derivedScore": derivedScore,
                    "submittedAt": FieldValue.serverTimestamp()
                ], forDocument: attemptRef, merge: true)

                var creatorScore = data["creatorScore"] as? Int
                var opponentScore = data["opponentScore"] as? Int
                if uid == createdByUID {
                    creatorScore = derivedScore
                    txn.updateData(["creatorScore": derivedScore], forDocument: challengeRef)
                } else {
                    opponentScore = derivedScore
                    txn.updateData(["opponentScore": derivedScore], forDocument: challengeRef)
                }

                guard let finalCreator = creatorScore, let finalOpponent = opponentScore else {
                    txn.updateData(["updatedAt": FieldValue.serverTimestamp()], forDocument: challengeRef)
                    return true
                }

                let creatorUserRef = self.db.collection("users").document(createdByUID)
                let opponentUserRef = self.db.collection("users").document(opponentUID)
                let creatorSnap = try txn.getDocument(creatorUserRef)
                let opponentSnap = try txn.getDocument(opponentUserRef)

                let creatorRating = max(800, (creatorSnap.data()?["duelRating"] as? Int) ?? 1000)
                let opponentRating = max(800, (opponentSnap.data()?["duelRating"] as? Int) ?? 1000)

                let (creatorOutcome, opponentOutcome): (Double, Double)
                let winnerUID: String?
                if finalCreator > finalOpponent {
                    creatorOutcome = 1
                    opponentOutcome = 0
                    winnerUID = createdByUID
                } else if finalCreator < finalOpponent {
                    creatorOutcome = 0
                    opponentOutcome = 1
                    winnerUID = opponentUID
                } else {
                    creatorOutcome = 0.5
                    opponentOutcome = 0.5
                    winnerUID = nil
                }

                let creatorExpected = 1 / (1 + pow(10, Double(opponentRating - creatorRating) / 400))
                let opponentExpected = 1 / (1 + pow(10, Double(creatorRating - opponentRating) / 400))
                let k = 24.0
                let creatorDelta = Int((k * (creatorOutcome - creatorExpected)).rounded())
                let opponentDelta = Int((k * (opponentOutcome - opponentExpected)).rounded())
                let creatorNewRating = max(800, creatorRating + creatorDelta)
                let opponentNewRating = max(800, opponentRating + opponentDelta)
                let season = self.currentSeasonKey()

                txn.updateData([
                    "status": DuelChallengeStatus.completed.rawValue,
                    "winnerUid": winnerUID as Any,
                    "creatorScore": finalCreator,
                    "opponentScore": finalOpponent,
                    "creatorRatingDelta": creatorDelta,
                    "opponentRatingDelta": opponentDelta,
                    "completedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: challengeRef)

                self.applyUserResult(
                    txn: txn,
                    ref: creatorUserRef,
                    current: creatorSnap.data() ?? [:],
                    outcome: creatorOutcome,
                    newRating: creatorNewRating,
                    ratingDelta: creatorDelta,
                    seasonKey: season
                )
                self.applyUserResult(
                    txn: txn,
                    ref: opponentUserRef,
                    current: opponentSnap.data() ?? [:],
                    outcome: opponentOutcome,
                    newRating: opponentNewRating,
                    ratingDelta: opponentDelta,
                    seasonKey: season
                )
                return true
            }
            statusMessage = "Attempt submitted."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func attachRealtime(for uid: String) {
        let userListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snap, _ in
            guard let self else { return }
            Task { @MainActor in
                let data = snap?.data() ?? [:]
                self.duelRating = max(800, (data["duelRating"] as? Int) ?? 1000)
                self.duelWins = max(0, (data["duelWins"] as? Int) ?? 0)
                self.duelLosses = max(0, (data["duelLosses"] as? Int) ?? 0)
                self.duelDraws = max(0, (data["duelDraws"] as? Int) ?? 0)
                self.seasonKey = (data["duelSeasonKey"] as? String) ?? self.currentSeasonKey()
                self.seasonPoints = max(0, (data["duelSeasonPoints"] as? Int) ?? 0)
                self.seasonMatches = max(0, (data["duelSeasonMatches"] as? Int) ?? 0)
                self.seasonWins = max(0, (data["duelSeasonWins"] as? Int) ?? 0)
                self.leaderboardCache = self.leaderboardCache.filter { _, cached in
                    cached.seasonKey == self.seasonKey
                }
            }
        }

        let challengeListener = db.collection("duelChallenges")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                Task { @MainActor in
                    let rows = (snap?.documents ?? [])
                        .compactMap(self.parseChallenge)
                        .sorted { lhs, rhs in
                            let l = lhs.completedAt ?? lhs.startedAt ?? lhs.createdAt
                            let r = rhs.completedAt ?? rhs.startedAt ?? rhs.createdAt
                            return l > r
                        }

                    self.myOpenChallenge = rows.first {
                        $0.status == .open && $0.createdByUID == uid
                    }
                    self.incomingInvites = rows.filter {
                        $0.status == .invited && $0.opponentUID == uid
                    }
                    self.outgoingInvites = rows.filter {
                        $0.status == .invited && $0.createdByUID == uid
                    }
                    self.activeChallenges = rows.filter { $0.status == .active }
                    self.recentCompleted = rows.filter { $0.status == .completed }.prefix(8).map { $0 }
                }
            }

        listeners = [userListener, challengeListener]
    }

    private func ensureProfileDefaults(uid: String) async {
        let key = currentSeasonKey()
        do {
            try await db.collection("users").document(uid).setData([
                "duelRating": 1000,
                "duelLeague": DuelLeagueTier.bronze.rawValue,
                "duelWins": 0,
                "duelLosses": 0,
                "duelDraws": 0,
                "duelSeasonKey": key,
                "duelSeasonPoints": 0,
                "duelSeasonMatches": 0,
                "duelSeasonWins": 0,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func tryJoinOpenChallenge(uid: String) async throws -> Bool {
        let openRows = try await db.collection("duelChallenges")
            .whereField("status", isEqualTo: DuelChallengeStatus.open.rawValue)
            .limit(to: 40)
            .getDocuments()

        let candidates = openRows.documents.filter { doc in
            let creator = (doc.data()["createdByUid"] as? String) ?? ""
            return !creator.isEmpty && creator != uid
        }
        guard !candidates.isEmpty else { return false }

        let creatorUIDs = Array(Set(candidates.compactMap { $0.data()["createdByUid"] as? String }))
        let ratings = try await fetchUserRatings(uids: creatorUIDs + [uid])
        let myRating = ratings[uid] ?? duelRating
        let myTier = DuelLeagueTier.forRating(myRating)

        let ordered = candidates.sorted { lhs, rhs in
            let lUid = (lhs.data()["createdByUid"] as? String) ?? ""
            let rUid = (rhs.data()["createdByUid"] as? String) ?? ""
            let lRating = ratings[lUid] ?? 1000
            let rRating = ratings[rUid] ?? 1000
            let lTier = DuelLeagueTier.forRating(lRating)
            let rTier = DuelLeagueTier.forRating(rRating)
            let lPenalty = (lTier == myTier) ? 0 : 1000
            let rPenalty = (rTier == myTier) ? 0 : 1000
            let lDiff = abs(lRating - myRating)
            let rDiff = abs(rRating - myRating)
            return (lPenalty + lDiff) < (rPenalty + rDiff)
        }

        for candidate in ordered {
            let joined = try await runTransaction { txn in
                let ref = self.db.collection("duelChallenges").document(candidate.documentID)
                let snap = try txn.getDocument(ref)
                guard let data = snap.data(),
                      (data["status"] as? String) == DuelChallengeStatus.open.rawValue,
                      let creatorUID = data["createdByUid"] as? String,
                      creatorUID != uid else {
                    return false
                }

                txn.updateData([
                    "status": DuelChallengeStatus.active.rawValue,
                    "opponentUid": uid,
                    "participants": [creatorUID, uid],
                    "startedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: ref)
                return true
            }
            if joined { return true }
        }

        return false
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

    private func fetchStudioCandidates(for uid: String) async throws -> [DuelTargetCandidate] {
        let userSnap = try await db.collection("users").document(uid).getDocument()
        let data = userSnap.data() ?? [:]
        let teacherStudioID = (data["teacherStudioId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let studentStudioID = (data["studentStudioId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let studioIDs = Array(Set([teacherStudioID, studentStudioID].filter { !$0.isEmpty }))
        guard !studioIDs.isEmpty else { return [] }

        var map: [String: DuelTargetCandidate] = [:]
        for studioID in studioIDs {
            let members = try await db.collection("studios")
                .document(studioID)
                .collection("members")
                .getDocuments()

            for doc in members.documents where doc.documentID != uid {
                let memberData = doc.data()
                let name = ((memberData["displayName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                map[doc.documentID] = DuelTargetCandidate(
                    id: doc.documentID,
                    displayName: name,
                    source: .studio,
                    subtitle: "Studio"
                )
            }
        }

        return Array(map.values)
    }

    func refreshSeasonLeaderboard(scope: DuelLeaderboardScope, force: Bool = false) async {
        guard let uid = configuredUID else { return }
        let key = currentSeasonKey()
        if !force,
           let cached = leaderboardCache[scope],
           cached.seasonKey == key,
           Date().timeIntervalSince(cached.fetchedAt) < leaderboardRefreshCooldown {
            leaderboardRows = cached.rows
            return
        }
        do {
            var rows: [DuelLeaderboardRow] = []
            switch scope {
            case .global:
                // Keep this index-free for launch stability: fetch current season users and sort client-side.
                let snap = try await db.collection("users")
                    .whereField("duelSeasonKey", isEqualTo: key)
                    .limit(to: 200)
                    .getDocuments()
                rows = snap.documents
                    .compactMap(parseLeaderboardRow)
                    .sorted(by: leaderboardSort)
                    .prefix(20)
                    .map { $0 }
            case .friends:
                let ids = try await friendIDs(for: uid) + [uid]
                rows = try await fetchLeaderboardRows(uids: ids, seasonKey: key)
                    .sorted(by: leaderboardSort)
                    .prefix(20)
                    .map { $0 }
            case .studio:
                let ids = try await studioMemberIDs(for: uid)
                rows = try await fetchLeaderboardRows(uids: ids, seasonKey: key)
                    .sorted(by: leaderboardSort)
                    .prefix(20)
                    .map { $0 }
            }
            leaderboardRows = rows
            leaderboardCache[scope] = (seasonKey: key, rows: rows, fetchedAt: Date())
        } catch {
            statusMessage = error.localizedDescription
            leaderboardRows = []
        }
    }

    private func friendIDs(for uid: String) async throws -> [String] {
        let snap = try await db.collection("friendships")
            .document(uid)
            .collection("buddies")
            .getDocuments()
        return snap.documents.map(\.documentID)
    }

    private func studioMemberIDs(for uid: String) async throws -> [String] {
        let userSnap = try await db.collection("users").document(uid).getDocument()
        let data = userSnap.data() ?? [:]
        let teacherStudioID = (data["teacherStudioId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let studentStudioID = (data["studentStudioId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let studioIDs = Array(Set([teacherStudioID, studentStudioID].filter { !$0.isEmpty }))
        guard !studioIDs.isEmpty else { return [uid] }

        var ids: Set<String> = [uid]
        for studioID in studioIDs {
            let snap = try await db.collection("studios").document(studioID).collection("members").getDocuments()
            for doc in snap.documents { ids.insert(doc.documentID) }
        }
        return Array(ids)
    }

    private func fetchLeaderboardRows(uids: [String], seasonKey: String) async throws -> [DuelLeaderboardRow] {
        let unique = Array(Set(uids))
        guard !unique.isEmpty else { return [] }
        var rows: [DuelLeaderboardRow] = []

        for chunk in unique.chunked(into: 10) {
            let snap = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for doc in snap.documents {
                guard let row = parseLeaderboardRow(doc), rowSeasonKey(doc.data()) == seasonKey else { continue }
                rows.append(row)
            }
        }
        return rows
    }

    private func rowSeasonKey(_ data: [String: Any]) -> String {
        (data["duelSeasonKey"] as? String) ?? ""
    }

    private func parseLeaderboardRow(_ doc: QueryDocumentSnapshot) -> DuelLeaderboardRow? {
        parseLeaderboardRow(documentID: doc.documentID, data: doc.data())
    }

    private func parseLeaderboardRow(documentID: String, data: [String: Any]) -> DuelLeaderboardRow? {
        let displayName = ((data["displayName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return nil }
        return DuelLeaderboardRow(
            id: documentID,
            displayName: displayName,
            points: max(0, (data["duelSeasonPoints"] as? Int) ?? 0),
            rating: max(800, (data["duelRating"] as? Int) ?? 1000),
            wins: max(0, (data["duelSeasonWins"] as? Int) ?? 0),
            matches: max(0, (data["duelSeasonMatches"] as? Int) ?? 0)
        )
    }

    private func leaderboardSort(_ lhs: DuelLeaderboardRow, _ rhs: DuelLeaderboardRow) -> Bool {
        if lhs.points != rhs.points { return lhs.points > rhs.points }
        if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
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
                output[doc.documentID] = max(800, (doc.data()["duelRating"] as? Int) ?? 1000)
            }
        }
        return output
    }

    private func currentSeasonKey() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let year = calendar.component(.yearForWeekOfYear, from: now)
        let week = calendar.component(.weekOfYear, from: now)
        return "\(year)-W\(week)"
    }

    private func applyUserResult(
        txn: Transaction,
        ref: DocumentReference,
        current: [String: Any],
        outcome: Double,
        newRating: Int,
        ratingDelta: Int,
        seasonKey: String
    ) {
        let wins = max(0, (current["duelWins"] as? Int) ?? 0) + (outcome == 1 ? 1 : 0)
        let losses = max(0, (current["duelLosses"] as? Int) ?? 0) + (outcome == 0 ? 1 : 0)
        let draws = max(0, (current["duelDraws"] as? Int) ?? 0) + (outcome == 0.5 ? 1 : 0)

        let currentSeason = (current["duelSeasonKey"] as? String) ?? ""
        let reset = currentSeason != seasonKey
        let oldPoints = reset ? 0 : max(0, (current["duelSeasonPoints"] as? Int) ?? 0)
        let oldMatches = reset ? 0 : max(0, (current["duelSeasonMatches"] as? Int) ?? 0)
        let oldSeasonWins = reset ? 0 : max(0, (current["duelSeasonWins"] as? Int) ?? 0)
        let oldSeasonDelta = reset ? 0 : ((current["duelSeasonRatingDelta"] as? Int) ?? 0)

        txn.setData([
            "duelRating": newRating,
            "duelLeague": DuelLeagueTier.forRating(newRating).rawValue,
            "duelWins": wins,
            "duelLosses": losses,
            "duelDraws": draws,
            "duelSeasonKey": seasonKey,
            "duelSeasonPoints": oldPoints + (outcome == 1 ? 3 : (outcome == 0.5 ? 1 : 0)),
            "duelSeasonMatches": oldMatches + 1,
            "duelSeasonWins": oldSeasonWins + (outcome == 1 ? 1 : 0),
            "duelSeasonRatingDelta": oldSeasonDelta + ratingDelta,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: ref, merge: true)
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
        let startedAt = (data["startedAt"] as? Timestamp)?.dateValue()
        let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()

        return DuelChallenge(
            id: doc.documentID,
            createdByUID: createdByUID,
            opponentUID: data["opponentUid"] as? String,
            participants: participants,
            status: status,
            queueType: queueType,
            objective: (data["objective"] as? String) ?? "Random scale challenge",
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            creatorScore: data["creatorScore"] as? Int,
            opponentScore: data["opponentScore"] as? Int,
            winnerUID: data["winnerUid"] as? String,
            creatorRatingDelta: data["creatorRatingDelta"] as? Int ?? 0,
            opponentRatingDelta: data["opponentRatingDelta"] as? Int ?? 0
        )
    }

    private func runTransaction<T>(
        _ body: @escaping (Transaction) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ txn, errorPointer in
                do {
                    return try body(txn)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let typed = value as? T else {
                    continuation.resume(throwing: NSError(
                        domain: "PracticeBuddy.DuelLeagueManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Transaction returned invalid value."]
                    ))
                    return
                }
                continuation.resume(returning: typed)
            }
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
