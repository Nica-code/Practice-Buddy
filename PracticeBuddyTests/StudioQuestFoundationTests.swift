import XCTest
@testable import PracticeBuddy

@MainActor
final class StudioQuestFoundationTests: XCTestCase {
    func testLaunchConfigurationUsesPersistedDestinationWithoutQAOverrides() throws {
        let suiteName = "StudioQuestFoundationTests.launch.persisted.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppDestination.community.rawValue, forKey: "practiquest.v2.destination")

        let configuration = AppLaunchConfiguration(
            arguments: ["PracticeBuddy"],
            defaults: defaults,
            qaOverridesEnabled: false
        )

        XCTAssertEqual(configuration.initialDestination, .community)
        XCTAssertNil(configuration.initialRoute)
        XCTAssertFalse(configuration.isQA)
    }

    func testLaunchConfigurationQADestinationOverridesPersistedDestination() throws {
        let suiteName = "StudioQuestFoundationTests.launch.destination.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppDestination.you.rawValue, forKey: "practiquest.v2.destination")

        let configuration = AppLaunchConfiguration(
            arguments: ["PracticeBuddy", "--qa-destination", "1"],
            defaults: defaults,
            qaOverridesEnabled: true
        )

        XCTAssertEqual(configuration.initialDestination, .quest)
        XCTAssertNil(configuration.initialRoute)
        XCTAssertTrue(configuration.isQA)
    }

    func testLaunchConfigurationExactRouteOwnsItsDestination() throws {
        let suiteName = "StudioQuestFoundationTests.launch.route.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppLaunchConfiguration(
            arguments: [
                "PracticeBuddy",
                "--qa-destination", "0",
                "--qa-route", "chat",
                "--qa-community-populated",
                "--qa-populated"
            ],
            defaults: defaults,
            qaOverridesEnabled: true
        )

        XCTAssertEqual(configuration.initialDestination, .community)
        XCTAssertEqual(
            configuration.initialRoute,
            .communityMessages(
                friendUID: "fixture-aya",
                threadID: "fixture-thread-aya"
            )
        )
        XCTAssertEqual(configuration.fixtureSet, .complete)
    }

    func testRouterStartsWithOneExactPathWithoutOnAppearMutation() throws {
        let router = AppRouter(
            selectedDestination: .you,
            initialRoute: .settings(section: .privacy)
        )

        XCTAssertEqual(router.selectedDestination, .you)
        XCTAssertEqual(
            router.pathBinding(for: .you).wrappedValue,
            [.settings(section: .privacy)]
        )
        XCTAssertTrue(router.pathBinding(for: .today).wrappedValue.isEmpty)
    }

    func testPracticeActivityStateUsesTimestampsInsteadOfTimerTicks() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = PracticeActivityState(
            sessionID: UUID(),
            kind: .focusedTool(.warmUp),
            phase: .running,
            phaseStartedAt: start,
            accumulatedSeconds: 12
        )

        XCTAssertEqual(
            state.elapsed(at: start.addingTimeInterval(8.9)),
            20
        )
    }

    func testFocusedToolOwnsThePracticeDockRuntime() throws {
        let suiteName = "StudioQuestFoundationTests.runtime.focused.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = PracticeSessionCoordinator(defaults: defaults)

        coordinator.beginFocusedTool(
            .warmUp,
            durationMinutes: 5,
            verified: false,
            source: .library
        )

        XCTAssertEqual(coordinator.activeToolID, .warmUp)
        XCTAssertTrue(coordinator.isFocusedToolSession)
        XCTAssertTrue(coordinator.isRunning)
        guard case .focusedToolRunning(let tool, _) = coordinator.state else {
            return XCTFail("Focused tool did not own the Practice Dock")
        }
        XCTAssertEqual(tool, .warmUp)
        coordinator.pause()
    }

    func testContextualToolKeepsTheParentSessionIdentity() throws {
        let suiteName = "StudioQuestFoundationTests.runtime.contextual.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = PracticeSessionCoordinator(defaults: defaults)
        coordinator.preparePlan(
            piece: "Cello",
            tasks: [PracticePlanTask(title: "Bowing", minutes: 10)],
            verified: false,
            launchContext: PracticeLaunchContext(source: .setup)
        )
        let parentID = coordinator.activeSessionID

        let context = coordinator.attachTool(.tuner)

        XCTAssertEqual(coordinator.activeSessionID, parentID)
        XCTAssertEqual(context.parentSessionID, parentID)
        XCTAssertEqual(context.source, .activeSession)
    }

    func testToolActivityPauseUsesTimestampElapsedAndPersistsRecovery() throws {
        let suiteName = "StudioQuestFoundationTests.runtime.recovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = PracticeSessionCoordinator(defaults: defaults)

        coordinator.beginFocusedTool(.warmUp, durationMinutes: 5)
        coordinator.startToolActivity(recoveryPayloadJSON: #"{"step":2}"#)
        coordinator.pauseToolActivity(recoveryPayloadJSON: #"{"step":3}"#)

        XCTAssertEqual(coordinator.toolActivityState?.phase, .paused)
        XCTAssertEqual(
            coordinator.toolActivityState?.recoveryPayloadJSON,
            #"{"step":3}"#
        )

        let restored = PracticeSessionCoordinator(defaults: defaults)
        XCTAssertEqual(restored.activeToolID, .warmUp)
        XCTAssertEqual(restored.toolActivityState?.phase, .paused)
        XCTAssertEqual(
            restored.toolActivityState?.recoveryPayloadJSON,
            #"{"step":3}"#
        )
        restored.discard()
    }

    func testQuestCompletionIsQueuedUntilCanonicalSaveCompletes() throws {
        let suiteName = "StudioQuestFoundationTests.runtime.quest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = PracticeSessionCoordinator(defaults: defaults)

        coordinator.beginFocusedTool(.warmUp, durationMinutes: 5)
        coordinator.queueQuestCompletion("warm-up-warrior")

        XCTAssertEqual(coordinator.pendingQuestIDs, Set(["warm-up-warrior"]))

        let restored = PracticeSessionCoordinator(defaults: defaults)
        XCTAssertEqual(restored.pendingQuestIDs, Set(["warm-up-warrior"]))
        restored.discard()
        XCTAssertTrue(restored.pendingQuestIDs.isEmpty)
    }

    func testLegacyTabsMigrateToFourDestinationShell() {
        XCTAssertEqual(AppDestination.migrated(fromLegacyTab: 0), .today)
        XCTAssertEqual(AppDestination.migrated(fromLegacyTab: 1), .quest)
        XCTAssertEqual(AppDestination.migrated(fromLegacyTab: 2), .community)
        XCTAssertEqual(AppDestination.migrated(fromLegacyTab: 4), .you)
    }

    func testQuestCompletionUsesPersistedProgress() {
        let quest = QuestPresentation(
            id: "test",
            title: "Test quest",
            subtitle: "Objective",
            progress: 1,
            target: 1,
            rewardTokens: 10,
            systemImage: "checkmark",
            period: .featured,
            action: .route(.warmUp)
        )
        XCTAssertTrue(quest.isComplete)
    }

    func testRouterPreservesAnIndependentTypedPathForEveryTab() {
        let router = AppRouter()
        let sessionID = UUID()

        router.navigate(to: .goals, in: .today)
        router.navigate(to: .sessionDetail(sessionID: sessionID), in: .today)
        router.navigate(to: .duelArena(challengeID: "duel-42"), in: .quest)
        router.navigate(
            to: .communityMessages(friendUID: "friend-7", threadID: "thread-9"),
            in: .community
        )
        router.navigate(to: .settings(section: .privacy), in: .you)

        XCTAssertEqual(
            router.pathBinding(for: .today).wrappedValue,
            [.goals, .sessionDetail(sessionID: sessionID)]
        )
        XCTAssertEqual(
            router.pathBinding(for: .quest).wrappedValue,
            [.duelArena(challengeID: "duel-42")]
        )
        XCTAssertEqual(
            router.pathBinding(for: .community).wrappedValue,
            [.communityMessages(friendUID: "friend-7", threadID: "thread-9")]
        )
        XCTAssertEqual(
            router.pathBinding(for: .you).wrappedValue,
            [.settings(section: .privacy)]
        )
        XCTAssertEqual(router.selectedDestination, .you)
    }

    func testV2MigrationPreservesLegacyTabAndAvatarIdentity() throws {
        let suiteName = "StudioQuestFoundationTests.migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(2, forKey: "pb.tab.selection")
        defaults.set("avatar_mic", forKey: "pb.profile.avatarID")

        PractiQuestV2Migration.run(defaults: defaults)

        XCTAssertEqual(
            defaults.integer(forKey: "practiquest.v2.destination"),
            AppDestination.community.rawValue
        )
        let data = try XCTUnwrap(defaults.data(forKey: "practiquest.avatar.loadout"))
        let loadout = try JSONDecoder().decode(AvatarLoadout.self, from: data)
        XCTAssertEqual(loadout.baseID, "avatar_mic")
        XCTAssertEqual(loadout.version, AvatarLoadout.currentVersion)
    }

    func testLegacyAvatarLoadoutDecodesIntoExpandableRoomSchema() throws {
        let legacyJSON = """
        {"baseID":"avatar_mic","skinToneID":"skin_03","hairID":"hair_crop_01","outfitID":"outfit_jazz_01","instrumentID":"instrument_guitar","poseID":"pose_idle","roomID":"room_midnight_stage"}
        """
        let loadout = try JSONDecoder().decode(AvatarLoadout.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(loadout.version, 1)
        XCTAssertEqual(loadout.roomID, "room_midnight_stage")
        XCTAssertTrue(loadout.roomLayouts.isEmpty)
        XCTAssertEqual(loadout.layout().roomID, "room_midnight_stage")
    }

    func testRoomZonesClampPlacementsInsideTheirAllowedArea() {
        XCTAssertEqual(
            StudioQuestRoomZone.floor.clamped(.init(x: -1, y: 0.2)),
            .init(x: 0.06, y: 0.54)
        )
        XCTAssertEqual(
            StudioQuestRoomZone.wall.clamped(.init(x: 2, y: 0.9)),
            .init(x: 0.94, y: 0.60)
        )
        XCTAssertEqual(
            StudioQuestRoomZone.surface.clamped(.init(x: 0.50, y: 0.1)),
            .init(x: 0.50, y: 0.32)
        )
    }

    func testTypedSocialAndIdentityRoutesPreservePayloads() {
        let router = AppRouter()
        let sessionID = UUID()
        router.navigate(to: .publicProfile(userID: "musician-42"), in: .community)
        router.navigate(to: .practiceMoment(momentID: "moment-9"), in: .community)
        router.navigate(to: .practiceMomentComposer(sessionID: sessionID), in: .community)
        router.navigate(to: .avatarStudio(section: .customize), in: .you)
        router.navigate(to: .pro(source: .smartCoach), in: .you)

        XCTAssertEqual(
            router.pathBinding(for: .community).wrappedValue,
            [
                .publicProfile(userID: "musician-42"),
                .practiceMoment(momentID: "moment-9"),
                .practiceMomentComposer(sessionID: sessionID)
            ]
        )
        XCTAssertEqual(
            router.pathBinding(for: .you).wrappedValue,
            [.avatarStudio(section: .customize), .pro(source: .smartCoach)]
        )
    }

    func testQuestEventCountersPersistWithoutSessionContent() throws {
        let suiteName = "StudioQuestFoundationTests.quest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = PracticeQuestProgressStore(defaults: defaults)
        firstStore.record("rhythm-clarity")
        firstStore.record("rhythm-clarity")

        let restoredStore = PracticeQuestProgressStore(defaults: defaults)
        XCTAssertEqual(restoredStore.count(for: "rhythm-clarity"), 2)
        XCTAssertEqual(restoredStore.count(for: "unknown"), 0)
    }

    func testPresenceExpiresAtTwoMinutesAndRejectsFutureTimestamps() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(
            BuddiesViewModel.isPresenceOnline(
                BuddyPresenceState(state: .online, lastChanged: now.addingTimeInterval(-119)),
                now: now
            )
        )
        XCTAssertFalse(
            BuddiesViewModel.isPresenceOnline(
                BuddyPresenceState(state: .online, lastChanged: now.addingTimeInterval(-121)),
                now: now
            )
        )
        XCTAssertFalse(
            BuddiesViewModel.isPresenceOnline(
                BuddyPresenceState(state: .offline, lastChanged: now),
                now: now
            )
        )
        XCTAssertFalse(
            BuddiesViewModel.isPresenceOnline(
                BuddyPresenceState(state: .online, lastChanged: now.addingTimeInterval(1)),
                now: now
            )
        )
    }

    func testAnalyticsDimensionsContainOnlyBoundedMetadata() {
        XCTAssertEqual(
            PracticeAnalytics.Event.practiceSaved(durationSeconds: 2_400).safeDimensions,
            ["duration_bucket": "30_to_60m"]
        )
        XCTAssertEqual(
            PracticeAnalytics.Event.routeOpened(depth: 4).safeDimensions,
            ["depth": "4"]
        )
        XCTAssertEqual(
            PracticeAnalytics.Event.signInConversion(source: "account_setup").safeDimensions,
            ["source": "account_setup"]
        )
    }
}
