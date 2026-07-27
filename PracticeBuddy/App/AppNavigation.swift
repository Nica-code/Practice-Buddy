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

enum StudioQuestQAToolState: String, Equatable {
    case setup
    case running
    case paused
    case completed
    case permissionDenied
    case saveError
    case recovered
}

private struct StudioQuestQAToolStateKey: EnvironmentKey {
    static let defaultValue: StudioQuestQAToolState? = nil
}

extension EnvironmentValues {
    var studioQuestQAToolState: StudioQuestQAToolState? {
        get { self[StudioQuestQAToolStateKey.self] }
        set { self[StudioQuestQAToolStateKey.self] = newValue }
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
    case shop
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

/// The shop was previously a fourth segment here. It is now `AppRoute.shop`,
/// a destination of its own, so it is reachable from the token chip rather than
/// only from inside Avatar Studio.
enum AvatarStudioSection: String, Hashable, Codable, CaseIterable {
    case customize
    case collection
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
    var sourceKind: PracticeLaunchSource
    var toolID: PracticeToolID?
    var questID: String?
    var smartCoachPlanID: String?
    var sessionID: UUID?

    init(
        source: String,
        toolID: PracticeToolID? = nil,
        questID: String? = nil,
        smartCoachPlanID: String? = nil,
        sessionID: UUID? = nil
    ) {
        self.source = source
        self.sourceKind = PracticeLaunchSource(legacyValue: source)
        self.toolID = toolID
        self.questID = questID
        self.smartCoachPlanID = smartCoachPlanID
        self.sessionID = sessionID
    }

    init(
        source: PracticeLaunchSource,
        toolID: PracticeToolID? = nil,
        questID: String? = nil,
        smartCoachPlanID: String? = nil,
        sessionID: UUID? = nil
    ) {
        self.source = source.rawValue
        self.sourceKind = source
        self.toolID = toolID
        self.questID = questID
        self.smartCoachPlanID = smartCoachPlanID
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey {
        case source, sourceKind, toolID, questID, smartCoachPlanID, sessionID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "legacy"
        sourceKind = try values.decodeIfPresent(PracticeLaunchSource.self, forKey: .sourceKind)
            ?? PracticeLaunchSource(legacyValue: source)
        toolID = try values.decodeIfPresent(PracticeToolID.self, forKey: .toolID)
        questID = try values.decodeIfPresent(String.self, forKey: .questID)
        smartCoachPlanID = try values.decodeIfPresent(String.self, forKey: .smartCoachPlanID)
        sessionID = try values.decodeIfPresent(UUID.self, forKey: .sessionID)
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
    /// The studio editor is presented over the whole shell rather than pushed,
    /// so it escapes the tab bar *and* the practice dock, which is a
    /// `tabViewBottomAccessory` and survives `.toolbar(.hidden, for: .tabBar)`.
    @Published var roomEditorPresented = false
    @Published private var paths: [AppDestination: [AppRoute]]

    init(
        selectedDestination: AppDestination = .today,
        initialRoute: AppRoute? = nil,
        roomEditorPresented: Bool = false
    ) {
        self.selectedDestination = selectedDestination
        self.paths = Dictionary(uniqueKeysWithValues: AppDestination.allCases.map { ($0, []) })
        if let initialRoute {
            self.paths[selectedDestination] = [initialRoute]
        }
        self.roomEditorPresented = roomEditorPresented
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

/// A single, immutable snapshot of everything that can influence the app's
/// initial UI. Parsing this before SwiftUI creates the navigation stacks keeps
/// persisted state, UI-test overrides, and exact routes from racing in
/// `onAppear`.
@MainActor
struct AppLaunchConfiguration: Equatable {
    enum FixtureSet: String, Equatable {
        case none
        case populated
        case community
        case complete

        var includesPracticeHistory: Bool {
            self == .populated || self == .complete
        }

        var includesCommunity: Bool {
            self == .community || self == .complete
        }
    }

    enum Appearance: String, Equatable {
        case system
        case light
        case dark
    }

    enum PracticeState: String, Equatable {
        case idle
        case planned
        case running
        case paused
    }

    let initialDestination: AppDestination
    let initialRoute: AppRoute?
    let skipOnboarding: Bool
    let skipVersionGate: Bool
    let fixtureSet: FixtureSet
    let appearance: Appearance?
    let qaState: String?
    let toolState: StudioQuestQAToolState?
    let practiceState: PracticeState
    let roomEditorPresented: Bool
    let isQA: Bool

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) -> AppLaunchConfiguration {
        PractiQuestV2Migration.run(defaults: defaults)
        #if DEBUG
        return AppLaunchConfiguration(
            arguments: arguments,
            defaults: defaults,
            qaOverridesEnabled: true
        )
        #else
        return AppLaunchConfiguration(
            arguments: arguments,
            defaults: defaults,
            qaOverridesEnabled: false
        )
        #endif
    }

    init(
        arguments: [String],
        defaults: UserDefaults,
        qaOverridesEnabled: Bool
    ) {
        let persistedDestination = AppDestination(
            rawValue: defaults.integer(forKey: "practiquest.v2.destination")
        ) ?? .today

        guard qaOverridesEnabled else {
            initialDestination = persistedDestination
            initialRoute = nil
            skipOnboarding = false
            skipVersionGate = false
            fixtureSet = .none
            appearance = nil
            qaState = nil
            toolState = nil
            practiceState = .idle
            roomEditorPresented = false
            isQA = false
            return
        }

        let requestedDestination = Self.value(after: "--qa-destination", in: arguments)
            .flatMap(Int.init)
            .flatMap(AppDestination.init(rawValue:))
            ?? persistedDestination
        let requestedRoute = Self.value(after: "--qa-route", in: arguments)
            .flatMap(Self.route(named:))

        initialDestination = requestedRoute?.destination ?? requestedDestination
        initialRoute = requestedRoute?.route
        skipOnboarding = arguments.contains("--qa-skip-onboarding")
        skipVersionGate = arguments.contains("--qa-skip-version-gate")
        appearance = Self.value(after: "--qa-appearance", in: arguments)
            .flatMap(Appearance.init(rawValue:))
        qaState = Self.value(after: "--qa-state", in: arguments)
        toolState = Self.value(after: "--qa-tool-state", in: arguments)
            .flatMap(StudioQuestQAToolState.init(rawValue:))
        practiceState = Self.value(after: "--qa-practice-state", in: arguments)
            .flatMap(PracticeState.init(rawValue:))
            ?? (arguments.contains("--qa-open-studio") ? .running : .idle)
        roomEditorPresented = requestedRoute?.opensRoomEditor == true
        isQA = arguments.contains(where: { $0.hasPrefix("--qa-") })

        if arguments.contains("--qa-community-populated"),
           arguments.contains("--qa-populated") {
            fixtureSet = .complete
        } else if arguments.contains("--qa-community-populated") {
            fixtureSet = .community
        } else if arguments.contains("--qa-populated") {
            fixtureSet = .populated
        } else {
            fixtureSet = .none
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private struct RouteRequest {
        let destination: AppDestination
        let route: AppRoute?
        let opensRoomEditor: Bool
    }

    private static func route(named name: String) -> RouteRequest? {
        switch name {
        case "goals":
            RouteRequest(destination: .today, route: .goals, opensRoomEditor: false)
        case "history":
            RouteRequest(destination: .you, route: .history, opensRoomEditor: false)
        case "profile":
            RouteRequest(destination: .you, route: .profile(userID: nil), opensRoomEditor: false)
        case "settings":
            RouteRequest(destination: .you, route: .settings(section: nil), opensRoomEditor: false)
        case "duel":
            RouteRequest(destination: .quest, route: .duelArena(challengeID: nil), opensRoomEditor: false)
        case "avatar":
            RouteRequest(destination: .you, route: .avatarStudio(section: .customize), opensRoomEditor: false)
        case "shop":
            RouteRequest(destination: .today, route: .shop, opensRoomEditor: false)
        case "communityFriends":
            RouteRequest(destination: .community, route: .communityFriends, opensRoomEditor: false)
        case "warmUp":
            RouteRequest(destination: .today, route: .warmUp, opensRoomEditor: false)
        case "rhythm":
            RouteRequest(destination: .today, route: .rhythm, opensRoomEditor: false)
        case "intonation":
            RouteRequest(destination: .today, route: .intonation, opensRoomEditor: false)
        case "smartLoop":
            RouteRequest(destination: .today, route: .smartLoop, opensRoomEditor: false)
        case "runThrough":
            RouteRequest(destination: .today, route: .runThrough, opensRoomEditor: false)
        case "planExecuteReflect":
            RouteRequest(destination: .today, route: .planExecuteReflect, opensRoomEditor: false)
        case "roomEditor":
            RouteRequest(destination: .you, route: nil, opensRoomEditor: true)
        case "library":
            RouteRequest(destination: .today, route: .practiceLibrary, opensRoomEditor: false)
        case "notifications":
            RouteRequest(destination: .today, route: .notifications, opensRoomEditor: false)
        case "chat":
            RouteRequest(
                destination: .community,
                route: .communityMessages(
                    friendUID: "fixture-aya",
                    threadID: "fixture-thread-aya"
                ),
                opensRoomEditor: false
            )
        default:
            nil
        }
    }
}

enum PracticeDockState: Equatable {
    case idle
    case planned(title: String, durationMinutes: Int)
    case running(elapsedSeconds: Int, task: String, isVerified: Bool)
    case paused(elapsedSeconds: Int, task: String)
    case focusedToolRunning(tool: PracticeToolID, elapsedSeconds: Int)
    case focusedToolPaused(tool: PracticeToolID, elapsedSeconds: Int)
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
    let toolID: PracticeToolID?
    let capabilities: PracticeToolCapability
    var isFavorite: Bool
    var lastUsedAt: Date?

    init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        category: Category,
        tags: [String],
        route: AppRoute,
        supportsActiveSession: Bool,
        toolID: PracticeToolID? = nil,
        capabilities: PracticeToolCapability = [],
        isFavorite: Bool = false,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.category = category
        self.tags = tags
        self.route = route
        self.supportsActiveSession = supportsActiveSession
        self.toolID = toolID
        self.capabilities = capabilities
        self.isFavorite = isFavorite
        self.lastUsedAt = lastUsedAt
    }
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
