import SwiftUI
import Combine

enum AppDestination: Int, CaseIterable, Identifiable, Codable {
    case today = 0
    case quest = 1
    case community = 2
    case you = 3

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .quest: "Quest"
        case .community: "Community"
        case .you: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "house"
        case .quest: "medal"
        case .community: "person.2"
        case .you: "person"
        }
    }

    static func migrated(fromLegacyTab value: Int) -> AppDestination {
        switch value {
        case 1: .quest
        case 2: .community
        case 3, 4: .you
        default: .today
        }
    }
}

indirect enum AppRoute: Hashable {
    case practiceStudio
    case practiceSetup(preset: PracticePreset?)
    case practiceLibrary
    case metronome
    case tuner
    case smartLoop
    case warmUp
    case planExecuteReflect
    case rhythm
    case intonation
    case runThrough
    case history
    case achievements
    case sessionDetail(sessionID: UUID)
    case goals
    case notifications
    case settings(section: StudioQuestSettingsSection?)
    case profile(userID: String?)
    case publicProfile(userID: String)
    case profileUpgrade
    case pro(source: StudioQuestProSource)
    case avatarStudio(section: AvatarStudioSection)
    case inventory
    case duelArena(challengeID: String?)
    case questDetail(QuestPresentation)
    case smartCoach
    case communityFeed
    case communityConnections(section: CommunityConnectionsSection)
    case peopleSearch(query: String?)
    case practiceMoment(momentID: String)
    case practiceMomentComposer(sessionID: UUID)
    case shareCard(sessionID: UUID)
    case communityFriends
    case communityMessages(friendUID: String?, threadID: String?)
    case communityRequests
}

enum CommunityConnectionsSection: String, Hashable, Codable, CaseIterable {
    case friends
    case following
    case followers
    case requests
}

enum AvatarStudioSection: String, Hashable, Codable, CaseIterable {
    case customize
    case collection
    case shop
    case room
}

enum StudioQuestProSource: String, Hashable, Codable {
    case you
    case smartCoach
    case historyExport
    case savedPlans
    case avatarShop
}

struct PracticePreset: Hashable, Codable {
    var piece: String
    var task: String
    var durationMinutes: Int
    var verified: Bool
    var launchContext: PracticeLaunchContext?
    var tasks: [PracticePlanTask] = []

    init(
        piece: String,
        task: String,
        durationMinutes: Int,
        verified: Bool,
        launchContext: PracticeLaunchContext? = nil,
        tasks: [PracticePlanTask] = []
    ) {
        self.piece = piece
        self.task = task
        self.durationMinutes = durationMinutes
        self.verified = verified
        self.launchContext = launchContext
        self.tasks = tasks
    }
}

struct PracticeLaunchContext: Hashable, Codable {
    var source: String
    var questID: String?
    var smartCoachPlanID: String?
    var sessionID: UUID?

    init(
        source: String,
        questID: String? = nil,
        smartCoachPlanID: String? = nil,
        sessionID: UUID? = nil
    ) {
        self.source = source
        self.questID = questID
        self.smartCoachPlanID = smartCoachPlanID
        self.sessionID = sessionID
    }
}

enum StudioQuestSettingsSection: String, Hashable, Codable {
    case appearance
    case language
    case notifications
    case privacy
    case history
    case pro
    case account
}

enum QuestAction: Hashable {
    case route(AppRoute)
    case practice(PracticePreset)
}

struct QuestPresentation: Identifiable, Hashable {
    enum Period: String, Hashable {
        case featured
        case daily
        case weekly
    }

    let id: String
    let title: String
    let subtitle: String
    let progress: Int
    let target: Int
    let rewardTokens: Int
    let systemImage: String
    let period: Period
    let action: QuestAction

    var isComplete: Bool { progress >= target }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedDestination: AppDestination
    @Published private var paths: [AppDestination: [AppRoute]]

    init(selectedDestination: AppDestination = .today) {
        self.selectedDestination = selectedDestination
        self.paths = Dictionary(uniqueKeysWithValues: AppDestination.allCases.map { ($0, []) })
    }

    func pathBinding(for destination: AppDestination) -> Binding<[AppRoute]> {
        Binding(
            get: { self.paths[destination, default: []] },
            set: { self.paths[destination] = $0 }
        )
    }

    func navigate(to route: AppRoute, in destination: AppDestination? = nil) {
        let target = destination ?? selectedDestination
        selectedDestination = target
        paths[target, default: []].append(route)
        PracticeAnalytics.record(.routeOpened(depth: paths[target, default: []].count))
    }

    func replacePath(with route: AppRoute?, in destination: AppDestination) {
        selectedDestination = destination
        paths[destination] = route.map { [$0] } ?? []
        if route != nil {
            PracticeAnalytics.record(.routeOpened(depth: 1))
        }
    }

    func popToRoot(in destination: AppDestination? = nil) {
        paths[destination ?? selectedDestination] = []
    }
}

enum PracticeDockState: Equatable {
    case idle
    case planned(title: String, durationMinutes: Int)
    case running(elapsedSeconds: Int, task: String, isVerified: Bool)
    case paused(elapsedSeconds: Int, task: String)
}

struct PracticeLibraryItem: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case timing = "Timing"
        case listening = "Listening"
        case planning = "Planning"
        case performance = "Performance"
    }

    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let category: Category
    let tags: [String]
    let route: AppRoute
    let supportsActiveSession: Bool
}

struct AvatarLoadout: Codable, Equatable, Hashable {
    static let currentVersion = 2

    var version: Int = currentVersion
    var baseID: String
    var skinToneID: String
    var hairID: String
    var outfitID: String
    var instrumentID: String
    var accessoryID: String?
    var poseID: String
    var roomID: String
    /// The room background stays empty. Placements belong to the loadout so
    /// they travel safely between local storage and cloud inventory without
    /// ever becoming part of the room art asset.
    var roomLayouts: [String: StudioQuestRoomLayout]

    init(
        version: Int = AvatarLoadout.currentVersion,
        baseID: String,
        skinToneID: String,
        hairID: String,
        outfitID: String,
        instrumentID: String,
        accessoryID: String?,
        poseID: String,
        roomID: String,
        roomLayouts: [String: StudioQuestRoomLayout] = [:]
    ) {
        self.version = version
        self.baseID = baseID
        self.skinToneID = skinToneID
        self.hairID = hairID
        self.outfitID = outfitID
        self.instrumentID = instrumentID
        self.accessoryID = accessoryID
        self.poseID = poseID
        self.roomID = roomID
        self.roomLayouts = roomLayouts
    }

    static func starter(for legacyAvatarID: String?) -> AvatarLoadout {
        let normalized = legacyAvatarID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = normalized?.isEmpty == false ? normalized! : "avatar_01"
        return AvatarLoadout(
            baseID: preset,
            skinToneID: "skin_04",
            hairID: "hair_curl_01",
            outfitID: "outfit_contemporary_01",
            instrumentID: "instrument_piano",
            accessoryID: nil,
            poseID: "pose_idle",
            roomID: "room_daylight_studio",
            roomLayouts: [:]
        )
    }

    func layout(for roomID: String? = nil) -> StudioQuestRoomLayout {
        let id = roomID ?? self.roomID
        return roomLayouts[id] ?? StudioQuestRoomLayout(roomID: id)
    }

    mutating func setLayout(_ layout: StudioQuestRoomLayout) {
        roomLayouts[layout.roomID] = layout
        version = AvatarLoadout.currentVersion
    }

    private enum CodingKeys: String, CodingKey {
        case version, baseID, skinToneID, hairID, outfitID, instrumentID
        case accessoryID, poseID, roomID, roomLayouts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        baseID = try values.decodeIfPresent(String.self, forKey: .baseID) ?? "avatar_note"
        skinToneID = try values.decodeIfPresent(String.self, forKey: .skinToneID) ?? "skin_04"
        hairID = try values.decodeIfPresent(String.self, forKey: .hairID) ?? "hair_curl_01"
        outfitID = try values.decodeIfPresent(String.self, forKey: .outfitID) ?? "outfit_contemporary_01"
        instrumentID = try values.decodeIfPresent(String.self, forKey: .instrumentID) ?? "instrument_piano"
        accessoryID = try values.decodeIfPresent(String.self, forKey: .accessoryID)
        poseID = try values.decodeIfPresent(String.self, forKey: .poseID) ?? "pose_idle"
        roomID = try values.decodeIfPresent(String.self, forKey: .roomID) ?? "room_daylight_studio"
        roomLayouts = try values.decodeIfPresent([String: StudioQuestRoomLayout].self, forKey: .roomLayouts) ?? [:]
    }
}

enum PractiQuestV2Migration {
    static func run(defaults: UserDefaults = .standard) {
        let shellKey = "practiquest.v2.shell.migrated"
        guard !defaults.bool(forKey: shellKey) else { return }

        let legacyTab = defaults.integer(forKey: "pb.tab.selection")
        defaults.set(AppDestination.migrated(fromLegacyTab: legacyTab).rawValue, forKey: "practiquest.v2.destination")

        if defaults.data(forKey: "practiquest.avatar.loadout") == nil {
            let legacyAvatarID = defaults.string(forKey: "pb.profile.avatarID")
                ?? defaults.string(forKey: "pb.avatar.selected")
            let loadout = AvatarLoadout.starter(for: legacyAvatarID)
            if let data = try? JSONEncoder().encode(loadout) {
                defaults.set(data, forKey: "practiquest.avatar.loadout")
            }
        }

        defaults.set(true, forKey: shellKey)
    }
}
