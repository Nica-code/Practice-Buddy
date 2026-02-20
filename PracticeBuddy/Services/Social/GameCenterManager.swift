import Foundation
import GameKit
import Combine
import UIKit

@MainActor
final class GameCenterManager: ObservableObject {

    struct AuthSheet: Identifiable {
        let id = UUID()
        let viewController: UIViewController
    }

    // MARK: Leaderboard IDs (must match App Store Connect)
    enum PracticeLeaderboards {
        static let weeklyMinutesID = "pb.practice.weekly_minutes"
        static let monthlyMinutesID = "pb.practice.monthly_minutes"
    }

    // MARK: Preview row model (for in-app Top 5 list)
    struct LeaderboardRow: Identifiable, Equatable {
        let id: String
        let rank: Int
        let name: String
        let minutes: Int
    }

    @Published var isAuthenticated: Bool = false
    @Published var displayName: String?
    @Published var statusMessage: String?

    @Published var authSheet: AuthSheet?

    // MARK: In-app leaderboard preview state
    @Published var previewRows: [LeaderboardRow] = []
    @Published var previewIsLoading: Bool = false
    @Published var previewErrorMessage: String?
    @Published var previewLastUpdated: Date?

    private var didConfigure = false

    // MARK: - Submit caching (avoid spamming Game Center)
    private let kWeekStart = "pb.gc.submit.week.startEpoch"
    private let kWeekMinutes = "pb.gc.submit.week.minutes"
    private let kMonthStart = "pb.gc.submit.month.startEpoch"
    private let kMonthMinutes = "pb.gc.submit.month.minutes"

    func configure() {
        guard !didConfigure else {
            refreshStatus()
            return
        }
        didConfigure = true

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }

            if let viewController {
                self.authSheet = AuthSheet(viewController: viewController)
                return
            }

            if let error {
                self.statusMessage = error.localizedDescription
            } else {
                self.statusMessage = nil
            }

            self.refreshStatus()
        }

        refreshStatus()
    }

    func authenticate() {
        refreshStatus()
        if !GKLocalPlayer.local.isAuthenticated {
            statusMessage = "Opening Game Center sign-in…"
        }
    }

    func refreshStatus() {
        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        displayName = isAuthenticated ? GKLocalPlayer.local.displayName : nil
        if isAuthenticated {
            statusMessage = nil
        }
    }

    // MARK: - Friends list
    func openFriendsList() {
        if !isAuthenticated {
            authenticate()
            return
        }

        GKAccessPoint.shared.trigger(state: .localPlayerFriendsList) {
            // no-op
        }
    }

    // MARK: - Leaderboards UI
    func openWeeklyLeaderboard(friendsOnly: Bool = true) {
        openLeaderboard(
            leaderboardID: PracticeLeaderboards.weeklyMinutesID,
            friendsOnly: friendsOnly
        )
    }

    func openMonthlyLeaderboard(friendsOnly: Bool = true) {
        openLeaderboard(
            leaderboardID: PracticeLeaderboards.monthlyMinutesID,
            friendsOnly: friendsOnly
        )
    }

    private func openLeaderboard(leaderboardID: String, friendsOnly: Bool) {
        if !isAuthenticated {
            authenticate()
            return
        }

        let scope: GKLeaderboard.PlayerScope = friendsOnly ? .friendsOnly : .global
        let timeScope: GKLeaderboard.TimeScope = .allTime

        GKAccessPoint.shared.trigger(
            leaderboardID: leaderboardID,
            playerScope: scope,
            timeScope: timeScope
        ) {
            // no-op
        }
    }

    // MARK: - Submit scores
    func submitPracticeTotals(weekMinutes: Int, monthMinutes: Int) {
        guard isAuthenticated else { return }

        submitIfNeeded(
            period: .week,
            minutes: weekMinutes,
            leaderboardID: PracticeLeaderboards.weeklyMinutesID
        )

        submitIfNeeded(
            period: .month,
            minutes: monthMinutes,
            leaderboardID: PracticeLeaderboards.monthlyMinutesID
        )
    }

    func forceSubmitPracticeTotals(weekMinutes: Int, monthMinutes: Int) {
        guard isAuthenticated else { return }

        submitScore(minutes: weekMinutes, leaderboardID: PracticeLeaderboards.weeklyMinutesID)
        submitScore(minutes: monthMinutes, leaderboardID: PracticeLeaderboards.monthlyMinutesID)
    }

    private enum Period { case week, month }

    private func submitIfNeeded(period: Period, minutes: Int, leaderboardID: String) {
        let cal = Calendar.current
        let now = Date()

        let currentStart: Date = {
            switch period {
            case .week:
                return (cal.dateInterval(of: .weekOfYear, for: now)?.start) ?? cal.startOfDay(for: now)
            case .month:
                return (cal.dateInterval(of: .month, for: now)?.start) ?? cal.startOfDay(for: now)
            }
        }()

        let (startKey, minutesKey): (String, String) = {
            switch period {
            case .week:  return (kWeekStart,  kWeekMinutes)
            case .month: return (kMonthStart, kMonthMinutes)
            }
        }()

        let storedStartEpoch = UserDefaults.standard.double(forKey: startKey)
        let storedStart = storedStartEpoch > 0 ? Date(timeIntervalSince1970: storedStartEpoch) : nil

        let needsReset: Bool = {
            guard let storedStart else { return true }
            return !cal.isDate(storedStart, inSameDayAs: currentStart)
        }()

        if needsReset {
            UserDefaults.standard.set(currentStart.timeIntervalSince1970, forKey: startKey)
            UserDefaults.standard.set(-1, forKey: minutesKey)
        }

        let lastSubmitted = UserDefaults.standard.integer(forKey: minutesKey)
        guard minutes > lastSubmitted else { return }

        submitScore(minutes: minutes, leaderboardID: leaderboardID)
        UserDefaults.standard.set(minutes, forKey: minutesKey)
    }

    private func submitScore(minutes: Int, leaderboardID: String) {
        let clamped = max(0, minutes)

        GKLeaderboard.submitScore(
            clamped,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.statusMessage = "Leaderboard submit failed: \(error.localizedDescription)"
                } else {
                    self.statusMessage = "Submitted \(clamped) min to leaderboard."
                }
            }
        }
    }

    // MARK: - In-app Top 5 preview

    /// Loads the top entries for a leaderboard and updates `previewRows`.
    func loadLeaderboardPreview(leaderboardID: String, friendsOnly: Bool, limit: Int = 5) async {
        guard isAuthenticated else {
            previewRows = []
            previewErrorMessage = "Sign in to view leaderboard preview."
            previewLastUpdated = nil
            return
        }

        previewIsLoading = true
        previewErrorMessage = nil

        do {
            let leaderboard = try await loadLeaderboardObject(id: leaderboardID)
            let entries = try await loadTopEntries(leaderboard: leaderboard, friendsOnly: friendsOnly, limit: limit)

            let rows: [LeaderboardRow] = entries.map { entry in
                let playerID = entry.player.gamePlayerID
                let name = entry.player.displayName
                let minutes = max(0, Int(entry.score)) // we submit minutes as the score
                return LeaderboardRow(id: playerID, rank: entry.rank, name: name, minutes: minutes)
            }

            previewRows = rows
            previewLastUpdated = Date()
            previewErrorMessage = nil
        } catch {
            previewRows = []
            previewLastUpdated = nil
            previewErrorMessage = error.localizedDescription
        }

        previewIsLoading = false
    }

    private func loadLeaderboardObject(id: String) async throws -> GKLeaderboard {
        try await withCheckedThrowingContinuation { cont in
            GKLeaderboard.loadLeaderboards(IDs: [id]) { leaderboards, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let lb = leaderboards?.first else {
                    cont.resume(throwing: NSError(
                        domain: "PracticeBuddy.GameCenter",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Leaderboard not found. Check the ID in App Store Connect."]
                    ))
                    return
                }
                cont.resume(returning: lb)
            }
        }
    }

    private func loadTopEntries(leaderboard: GKLeaderboard, friendsOnly: Bool, limit: Int) async throws -> [GKLeaderboard.Entry] {
        let scope: GKLeaderboard.PlayerScope = friendsOnly ? .friendsOnly : .global
        let timeScope: GKLeaderboard.TimeScope = .allTime
        let range = NSRange(location: 1, length: max(1, limit))

        return try await withCheckedThrowingContinuation { cont in
            leaderboard.loadEntries(for: scope, timeScope: timeScope, range: range) { _, entries, _, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: entries ?? [])
            }
        }
    }
}
