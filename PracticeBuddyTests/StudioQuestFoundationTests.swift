import XCTest
import SwiftData
@testable import PracticeBuddy

@MainActor
final class StudioQuestFoundationTests: XCTestCase {
    func testIncomingLinkParserAcceptsValidatedCustomFriendInvite() throws {
        let url = try XCTUnwrap(URL(string: "practicebuddy://add-buddy?code=ab12-cd34"))

        XCTAssertEqual(
            IncomingLinkParser.action(from: url),
            .addBuddy(friendCode: "AB12-CD34")
        )
    }

    func testIncomingLinkParserAcceptsTrustedUniversalFriendInvite() throws {
        let url = try XCTUnwrap(
            URL(string: "https://practicebuddytracker.web.app/invite?code=AB12-CD34")
        )

        XCTAssertEqual(
            IncomingLinkParser.action(from: url),
            .addBuddy(friendCode: "AB12-CD34")
        )
    }

    func testIncomingLinkParserRejectsUntrustedOrMalformedFriendInvites() throws {
        let malicious = try XCTUnwrap(
            URL(string: "https://practicebuddytracker.web.app.evil.example/invite?code=AB12-CD34")
        )
        let malformed = try XCTUnwrap(
            URL(string: "https://practicebuddytracker.web.app/invite?code=not-a-code")
        )

        XCTAssertNil(IncomingLinkParser.action(from: malicious))
        XCTAssertNil(IncomingLinkParser.action(from: malformed))
    }

    func testBuddyInviteURLUsesThePublicUniversalLinkShape() throws {
        let url = try XCTUnwrap(AppInfo.buddyInviteURL(friendCode: "ab12-cd34"))

        XCTAssertEqual(url.host, "practicebuddytracker.web.app")
        XCTAssertEqual(url.path, "/invite")
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value,
            "AB12-CD34"
        )
    }

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

    func testLaunchConfigurationParsesDeterministicVersionGateFixture() throws {
        let suiteName = "StudioQuestFoundationTests.launch.versionGate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppLaunchConfiguration(
            arguments: [
                "PracticeBuddy",
                "--qa-skip-version-gate",
                "--qa-version-gate", "updateRequired"
            ],
            defaults: defaults,
            qaOverridesEnabled: true
        )

        XCTAssertEqual(configuration.versionGateFixture, .updateRequired)
        XCTAssertTrue(configuration.skipVersionGate)
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

        let context = try XCTUnwrap(coordinator.attachTool(.tuner))

        XCTAssertEqual(coordinator.activeSessionID, parentID)
        XCTAssertEqual(context.parentSessionID, parentID)
        XCTAssertEqual(context.source, .activeSession)
    }

    func testCoordinatorRejectsASecondToolWithoutExplicitReplacement() throws {
        let suiteName = "StudioQuestFoundationTests.runtime.exclusive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = PracticeSessionCoordinator(defaults: defaults)
        coordinator.preparePlan(
            piece: "Violin",
            tasks: [PracticePlanTask(title: "Scales", minutes: 5)],
            verified: false,
            launchContext: PracticeLaunchContext(source: .setup)
        )

        XCTAssertNotNil(coordinator.attachTool(.metronome))
        XCTAssertNil(coordinator.attachTool(.tuner))
        XCTAssertEqual(coordinator.activeToolID, .metronome)
        XCTAssertNotNil(coordinator.toolErrorMessage)
    }

    func testAudioCoordinatorSerializesOwners() async throws {
        let audio = PracticeAudioSessionCoordinator()
        try await audio.claim(.metronome, requirements: .playback)
        do {
            try await audio.claim(.tuner, requirements: .playback)
            XCTFail("A second audio owner should not be accepted")
        } catch let error as PracticeAudioSessionError {
            XCTAssertEqual(error, .ownedBy(.metronome))
        }
        audio.release(.metronome)
        XCTAssertNil(audio.owner)
    }

    func testDuelRecordingCannotCompeteWithTheTunerMicrophoneOwner() async throws {
        let audio = PracticeAudioSessionCoordinator()
        // Ownership serialization is independent of the real microphone
        // permission, which simulator unit tests must not prompt for.
        try await audio.claim(.duel, requirements: .playback)
        do {
            try await audio.claim(.tuner, requirements: .playback)
            XCTFail("Tuner must not replace an active duel recording")
        } catch let error as PracticeAudioSessionError {
            XCTAssertEqual(error, .ownedBy(.duel))
        }

        audio.release(.duel)
        try await audio.claim(.tuner, requirements: .playback)
        XCTAssertEqual(audio.owner, .tuner)
        audio.release(.tuner)
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

    func testSmartLoopAdvancesAcrossBackgroundBoundariesWithoutLosingTime() {
        let start = Date(timeIntervalSince1970: 10_000)
        var state = SmartLoopRunState(
            settings: SmartLoopSettings(
                loopDurationSeconds: 10,
                restDurationSeconds: 5,
                targetLoops: 2,
                runsUntilStopped: false,
                metronomeEnabled: false,
                startingTempoBPM: 72,
                autoIncreaseEnabled: false,
                autoIncreaseEvery: 2,
                tempoIncreaseBPM: 2,
                tempoLadderEnabled: false,
                cleanLoopsRequired: 3
            )
        )

        _ = state.start(at: start)
        let events = state.advance(to: start.addingTimeInterval(26))

        XCTAssertEqual(state.phase, .finished)
        XCTAssertEqual(state.loopsCompleted, 2)
        XCTAssertEqual(state.completedWorkSeconds, 20)
        XCTAssertTrue(events.contains(.finished))
    }

    func testSmartLoopCleanMarkCanOnlyCountOncePerCompletedInterval() {
        let start = Date(timeIntervalSince1970: 20_000)
        var state = SmartLoopRunState(
            settings: SmartLoopSettings(
                loopDurationSeconds: 10,
                restDurationSeconds: 5,
                targetLoops: 4,
                runsUntilStopped: false,
                metronomeEnabled: true,
                startingTempoBPM: 72,
                autoIncreaseEnabled: false,
                autoIncreaseEvery: 2,
                tempoIncreaseBPM: 2,
                tempoLadderEnabled: true,
                cleanLoopsRequired: 2
            )
        )

        _ = state.start(at: start)
        _ = state.advance(to: start.addingTimeInterval(10))
        XCTAssertTrue(state.markLastCompletedLoopClean().isEmpty)
        XCTAssertEqual(state.cleanLoopsAtCurrentTempo, 1)
        XCTAssertTrue(state.markLastCompletedLoopClean().isEmpty)
        XCTAssertEqual(state.cleanLoopsAtCurrentTempo, 1)

        _ = state.advance(to: start.addingTimeInterval(25))
        XCTAssertEqual(
            state.markLastCompletedLoopClean(),
            [.tempoChanged(74)]
        )
        XCTAssertEqual(state.currentTempoBPM, 74)
        XCTAssertEqual(state.cleanLoopsAtCurrentTempo, 0)
    }

    func testSmartLoopPauseResumePreservesPhaseProgress() {
        let start = Date(timeIntervalSince1970: 30_000)
        var state = SmartLoopRunState(
            settings: SmartLoopSettings(
                loopDurationSeconds: 30,
                restDurationSeconds: 10,
                targetLoops: 2,
                runsUntilStopped: false,
                metronomeEnabled: false,
                startingTempoBPM: 72,
                autoIncreaseEnabled: false,
                autoIncreaseEvery: 2,
                tempoIncreaseBPM: 2,
                tempoLadderEnabled: false,
                cleanLoopsRequired: 3
            )
        )

        _ = state.start(at: start)
        state.pause(at: start.addingTimeInterval(12))
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(100)), 18)

        _ = state.resume(at: start.addingTimeInterval(100))
        _ = state.advance(to: start.addingTimeInterval(118))
        XCTAssertEqual(state.loopsCompleted, 1)
        XCTAssertEqual(state.phase, .rest)
    }

    func testGuidedPracticeAdvancesAcrossEveryBackgroundBlockBoundary() {
        let start = Date(timeIntervalSince1970: 40_000)
        let blocks = [
            GuidedPracticeBlock(kind: .warmUp, durationSeconds: 60),
            GuidedPracticeBlock(kind: .technique, durationSeconds: 60),
            GuidedPracticeBlock(kind: .repertoire, durationSeconds: 60)
        ]
        var state = GuidedPracticeRunState(
            goals: [.intonation, .rhythm],
            blocks: blocks
        )

        _ = state.start(at: start)
        let events = state.advance(to: start.addingTimeInterval(135))

        XCTAssertEqual(state.currentBlock?.kind, .repertoire)
        XCTAssertEqual(state.currentBlockRemainingSeconds(at: start.addingTimeInterval(135)), 45)
        XCTAssertEqual(state.totalElapsedSeconds(at: start.addingTimeInterval(135)), 135)
        XCTAssertTrue(events.contains(.blockCompleted(.warmUp)))
        XCTAssertTrue(events.contains(.blockCompleted(.technique)))
    }

    func testGuidedPracticePauseResumeDoesNotCountTimeWhilePaused() {
        let start = Date(timeIntervalSince1970: 50_000)
        var state = GuidedPracticeRunState(
            goals: [.rhythm, .tone],
            blocks: [
                GuidedPracticeBlock(kind: .technique, durationSeconds: 120)
            ]
        )

        _ = state.start(at: start)
        state.pause(at: start.addingTimeInterval(20))
        XCTAssertEqual(
            state.totalElapsedSeconds(at: start.addingTimeInterval(600)),
            20
        )

        _ = state.resume(at: start.addingTimeInterval(600))
        XCTAssertEqual(
            state.totalElapsedSeconds(at: start.addingTimeInterval(610)),
            30
        )
    }

    @MainActor
    func testNestedToolResultDoesNotReplaceGuidedPracticeRuntime() throws {
        let suiteName = "StudioQuestFoundationTests.nested.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = PracticeSessionCoordinator(defaults: defaults)

        XCTAssertTrue(
            coordinator.beginFocusedTool(
                .planExecuteReflect,
                title: "Guided practice",
                durationMinutes: 20,
                source: .library
            )
        )
        XCTAssertNotNil(coordinator.beginNestedTool(.smartLoop))

        let nestedResult = PracticeToolResult(
            toolID: .smartLoop,
            sessionID: coordinator.activeSessionID,
            durationSeconds: 30
        )
        coordinator.attachCompletedToolResult(nestedResult)
        coordinator.endNestedTool(.smartLoop)

        XCTAssertEqual(coordinator.activeToolID, .planExecuteReflect)
        XCTAssertNil(coordinator.nestedToolID)
        XCTAssertEqual(coordinator.attachedToolResults, [nestedResult])
        XCTAssertNil(coordinator.latestToolResult)
        coordinator.discard()
    }

    func testRunThroughTimingExcludesPausedTime() {
        let start = Date(timeIntervalSince1970: 60_000)
        var state = RunThroughRunState(
            settings: RunThroughSettings(
                noPauseMode: false,
                useMetronome: false,
                metronomeBPM: 72
            )
        )

        state.beginCountIn(at: start)
        XCTAssertEqual(state.countInBeat(at: start.addingTimeInterval(1)), 2)
        state.beginRecording(
            filePath: "/tmp/runthrough-test.m4a",
            at: start.addingTimeInterval(3)
        )
        state.pause(at: start.addingTimeInterval(15))
        XCTAssertEqual(
            state.elapsedSeconds(at: start.addingTimeInterval(100)),
            12
        )

        state.resume(at: start.addingTimeInterval(100))
        state.finish(at: start.addingTimeInterval(108))
        XCTAssertEqual(state.elapsedSeconds(at: start.addingTimeInterval(500)), 20)
        XCTAssertEqual(state.phase, .review)
    }

    func testRunThroughMarkersUseRecordingTimeline() {
        let start = Date(timeIntervalSince1970: 70_000)
        var state = RunThroughRunState(
            settings: RunThroughSettings(
                noPauseMode: false,
                useMetronome: false,
                metronomeBPM: 72
            )
        )
        state.beginRecording(filePath: "/tmp/runthrough-test.m4a", at: start)
        state.addMarker("rhythm", at: start.addingTimeInterval(9))
        state.pause(at: start.addingTimeInterval(12))
        state.addMarker("intonation", at: start.addingTimeInterval(300))

        XCTAssertEqual(state.markers.map(\.second), [9, 12])
        XCTAssertEqual(state.markers.map(\.label), ["rhythm", "intonation"])
    }

    func testRunThroughFileLifecycleDeletesAbandonedRecording() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("abandoned.m4a")
        try Data("fixture".utf8).write(to: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        RunThroughFileLifecycle.removeIfPresent(at: file)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRhythmScorerClassifiesCenteredEarlyAndLateTakes() {
        let centered = RhythmAccuracyScorer.summary(
            for: [-12, 4, 8, -6, 14, -10, 2, 0]
        )
        XCTAssertEqual(centered.tendency, .centered)
        XCTAssertEqual(centered.centeredCount, 8)
        XCTAssertGreaterThanOrEqual(centered.grooveScore, 90)

        let early = RhythmAccuracyScorer.summary(
            for: [-72, -61, -54, -80, -65, -58, -77, -69]
        )
        XCTAssertEqual(early.tendency, .early)
        XCTAssertEqual(early.earlyCount, 8)
        XCTAssertLessThan(early.averageOffsetMs, 0)

        let late = RhythmAccuracyScorer.summary(
            for: [72, 61, 54, 80, 65, 58, 77, 69]
        )
        XCTAssertEqual(late.tendency, .late)
        XCTAssertEqual(late.lateCount, 8)
        XCTAssertGreaterThan(late.averageOffsetMs, 0)
    }

    func testRhythmGridOffsetUsesTheNearestBeat() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                RhythmAccuracyScorer.offsetMilliseconds(
                    onsetHostSeconds: 10.522,
                    gridAnchorHostSeconds: 10,
                    beatInterval: 0.5
                )
            ),
            22,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                RhythmAccuracyScorer.offsetMilliseconds(
                    onsetHostSeconds: 10.982,
                    gridAnchorHostSeconds: 10,
                    beatInterval: 0.5
                )
            ),
            -18,
            accuracy: 0.001
        )
        XCTAssertNil(
            RhythmAccuracyScorer.offsetMilliseconds(
                onsetHostSeconds: 9.9,
                gridAnchorHostSeconds: 10,
                beatInterval: 0.5
            )
        )
    }

    func testRhythmOnsetDetectorRequiresANewThresholdCrossingAndRefractoryGap() {
        var detector = RhythmOnsetDetector(
            threshold: 0.02,
            refractorySeconds: 0.08
        )

        XCTAssertFalse(detector.detectOnset(samples: [0.01], at: 1))
        XCTAssertTrue(detector.detectOnset(samples: [0.03], at: 1.01))
        XCTAssertFalse(detector.detectOnset(samples: [0.04], at: 1.02))
        XCTAssertFalse(detector.detectOnset(samples: [0.01], at: 1.03))
        XCTAssertFalse(detector.detectOnset(samples: [0.03], at: 1.05))
        XCTAssertFalse(detector.detectOnset(samples: [0.01], at: 1.06))
        XCTAssertTrue(detector.detectOnset(samples: [0.03], at: 1.10))
    }

    func testRhythmCalibrationThresholdIsAdaptiveAndBounded() {
        XCTAssertEqual(RhythmCalibrationThreshold.value(from: []), 0.02)
        XCTAssertEqual(
            RhythmCalibrationThreshold.value(from: [0.001, 0.002, 0.003]),
            0.012
        )
        XCTAssertEqual(
            RhythmCalibrationThreshold.value(from: [0.05, 0.06, 0.08]),
            0.15,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RhythmCalibrationThreshold.value(from: [0.2, 0.4, 0.8]),
            0.25
        )
    }

    func testRhythmRunStateSeparatesInsufficientInputFromPoorTiming() {
        var insufficient = RhythmAccuracyRunState(
            settings: RhythmAccuracySettings(
                bpm: 80,
                targetBeats: 8,
                pulseMode: .visualHaptic
            )
        )
        insufficient.beginListening()
        insufficient.register(offsetMilliseconds: 4)
        insufficient.register(offsetMilliseconds: -7)
        insufficient.finish()
        XCTAssertEqual(insufficient.phase, .insufficientInput)
        XCTAssertNil(insufficient.summary)

        var inaccurate = RhythmAccuracyRunState(settings: insufficient.settings)
        inaccurate.beginListening()
        for offset in [180, -210, 165, -190] {
            inaccurate.register(offsetMilliseconds: Double(offset))
        }
        inaccurate.finish()
        XCTAssertEqual(inaccurate.phase, .result)
        XCTAssertNotNil(inaccurate.summary)
        XCTAssertLessThan(inaccurate.summary?.grooveScore ?? 100, 25)
    }

    func testRhythmRunStatePauseResumeExcludesPausedTime() {
        let start = Date(timeIntervalSince1970: 80_000)
        var state = RhythmAccuracyRunState(
            settings: RhythmAccuracySettings(
                bpm: 80,
                targetBeats: 16,
                pulseMode: .visualHaptic
            )
        )
        state.beginListening(at: start)
        state.pause(at: start.addingTimeInterval(12))
        XCTAssertEqual(state.elapsedSeconds(at: start.addingTimeInterval(500)), 12)

        state.beginListening(at: start.addingTimeInterval(500))
        state.finish(at: start.addingTimeInterval(508))
        XCTAssertEqual(state.elapsedSeconds(at: start.addingTimeInterval(900)), 20)
    }

    func testIntonationTargetDegreesRemainCorrectAscendingAndDescending() {
        let settings = IntonationSettings(
            exercise: .oneOctaveScale,
            mode: .major,
            key: .c,
            octave: .middle,
            tempoBPM: 72,
            referenceHz: 440
        )
        let targets = IntonationTargetBuilder.targets(for: settings)

        XCTAssertEqual(
            targets.map(\.degree),
            [1, 2, 3, 4, 5, 6, 7, 1, 7, 6, 5, 4, 3, 2, 1]
        )
        XCTAssertEqual(targets.map(\.isDescending).filter { $0 }.count, 7)
    }

    func testIntonationArpeggioUsesRootThirdFifthInBothDirections() {
        let settings = IntonationSettings(
            exercise: .arpeggio,
            mode: .minor,
            key: .a,
            octave: .middle,
            tempoBPM: 72,
            referenceHz: 442
        )

        XCTAssertEqual(
            IntonationTargetBuilder.targets(for: settings).map(\.degree),
            [1, 3, 5, 1, 5, 3, 1]
        )
    }

    func testIntonationScorerUsesSyntheticPitchStreamsDeterministically() {
        let settings = IntonationSettings(
            exercise: .arpeggio,
            mode: .major,
            key: .g,
            octave: .middle,
            tempoBPM: 72,
            referenceHz: 440
        )
        let targets = IntonationTargetBuilder.targets(for: settings)
        let samples = targets.map { _ in
            [
                IntonationPitchSample(cents: 4, timeInNote: 0.20),
                IntonationPitchSample(cents: 6, timeInNote: 0.30),
                IntonationPitchSample(cents: 5, timeInNote: 0.40),
                IntonationPitchSample(cents: 3, timeInNote: 0.50)
            ]
        }

        let result = IntonationScorer.score(targets: targets, samples: samples)

        XCTAssertEqual(result.signalCoverage, 1)
        XCTAssertEqual(result.meanOffsetCents, 4.5, accuracy: 0.001)
        XCTAssertGreaterThan(result.centeringScore, 95)
        XCTAssertGreaterThan(result.stabilityScore, 95)
        XCTAssertGreaterThan(result.overallScore, 85)
    }

    func testIntonationRunStateDistinguishesNoSignalAndStopsTiming() {
        let start = Date(timeIntervalSince1970: 90_000)
        var state = IntonationRunState(
            settings: IntonationSettings(
                exercise: .arpeggio,
                mode: .major,
                key: .c,
                octave: .middle,
                tempoBPM: 72,
                referenceHz: 440
            )
        )
        state.beginListening(at: start)
        state.finish(at: start.addingTimeInterval(8))

        XCTAssertEqual(state.phase, .insufficientSignal)
        XCTAssertEqual(state.elapsedSeconds(at: start.addingTimeInterval(500)), 8)
        XCTAssertEqual(state.result?.signalCoverage, 0)
    }

    func testIntonationRunStatePreservesFractionalTimeAcrossNotes() {
        let start = Date(timeIntervalSince1970: 90_100)
        var state = IntonationRunState(
            settings: IntonationSettings(
                exercise: .arpeggio,
                mode: .major,
                key: .c,
                octave: .middle,
                tempoBPM: 100,
                referenceHz: 440
            )
        )
        state.beginListening(at: start)
        state.advanceNote(at: start.addingTimeInterval(0.6))
        state.advanceNote(at: start.addingTimeInterval(1.2))
        state.advanceNote(at: start.addingTimeInterval(1.8))

        XCTAssertEqual(
            state.elapsedDuration(at: start.addingTimeInterval(1.8)),
            1.8,
            accuracy: 0.001
        )
        XCTAssertEqual(state.elapsedSeconds(at: start.addingTimeInterval(1.8)), 1)
    }

    func testDiscardingPracticeReleasesMetronomeTunerAndAudioOwnership() throws {
        let suiteName = "StudioQuestFoundationTests.audio.cleanup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = PracticeSessionCoordinator(defaults: defaults)

        _ = coordinator.beginFocusedTool(
            .tuner,
            title: "Tuner practice",
            durationMinutes: 10,
            source: .qa
        )
        coordinator.metronome.applyStudioQuestFixture(isRunning: true)
        coordinator.tuner.applyStudioQuestFixture(isListening: true)
        coordinator.audioSession.applyStudioQuestFixture(
            owner: .tuner,
            requirements: .microphone
        )

        coordinator.discard()

        XCTAssertFalse(coordinator.metronome.isRunning)
        XCTAssertFalse(coordinator.tuner.isListening)
        XCTAssertFalse(coordinator.tuner.isReferenceTonePlaying)
        XCTAssertNil(coordinator.audioSession.owner)
    }

    func testMetronomeConfigurationClampsUnsupportedValues() {
        XCTAssertEqual(MetronomeEngine.clampBeatsPerBar(2), 2)
        XCTAssertEqual(MetronomeEngine.clampBeatsPerBar(6), 6)
        XCTAssertEqual(MetronomeEngine.clampBeatsPerBar(5), 4)
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

    func testProductionFeatureFlagsFailClosedForPublicExploreAndPreserveMissingValues() {
        let defaults = StudioQuestFeatureFlagSnapshot.productionDefaults
        let updated = defaults.applying([
            "practiceMoments": false,
            "publicExplore": true,
            "unknownFlag": true
        ])

        XCTAssertFalse(updated.practiceMoments)
        XCTAssertTrue(updated.publicExplore)
        XCTAssertTrue(updated.identityUpgradeRequired)
        XCTAssertTrue(updated.smartCoach)
        XCTAssertTrue(updated.newAvatarRenderer)
        XCTAssertFalse(defaults.publicExplore)
    }

    func testEntitlementPolicyRecognizesLegacyAndCurrentProductsWithoutTrustingStaleTierState() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(
            PBEntitlementAccessPolicy.tier(
                activeProductIDs: [PurchaseManager.adFreeMonthlyProductID],
                trialEndsAt: nil,
                hasServerAllAccess: false,
                hasLocalMasterAccess: false,
                simulatesFreeMode: false,
                now: now
            ),
            .pro
        )
        XCTAssertEqual(
            PBEntitlementAccessPolicy.tier(
                activeProductIDs: [PurchaseManager.proMonthlyProductID],
                trialEndsAt: nil,
                hasServerAllAccess: false,
                hasLocalMasterAccess: false,
                simulatesFreeMode: false,
                now: now
            ),
            .pro
        )
        XCTAssertEqual(
            PBEntitlementAccessPolicy.tier(
                activeProductIDs: [],
                trialEndsAt: now.addingTimeInterval(-1),
                hasServerAllAccess: false,
                hasLocalMasterAccess: false,
                simulatesFreeMode: false,
                now: now
            ),
            .free
        )
        XCTAssertEqual(
            PBEntitlementAccessPolicy.tier(
                activeProductIDs: [],
                trialEndsAt: nil,
                hasServerAllAccess: true,
                hasLocalMasterAccess: false,
                simulatesFreeMode: false,
                now: now
            ),
            .allAccess
        )
        XCTAssertEqual(
            PBEntitlementAccessPolicy.tier(
                activeProductIDs: [PurchaseManager.proMonthlyProductID],
                trialEndsAt: now.addingTimeInterval(86_400),
                hasServerAllAccess: true,
                hasLocalMasterAccess: true,
                simulatesFreeMode: true,
                now: now
            ),
            .free
        )
    }

    func testTrialClaimUsesAppCheckCallableWithoutPostingProductIdentifiers() async throws {
        let expiry = Date(timeIntervalSince1970: 2_000_086_400)
        let transport = SocialCallableTransportStub(responses: [
            "entitlementTrialV2": [
                "ok": true,
                "trialUsed": true,
                "trialStartedNow": true,
                "trialEndsAtMs": NSNumber(value: expiry.timeIntervalSince1970 * 1_000),
                "serverAllAccess": false
            ]
        ])
        let repository = PBTrialEntitlementRepository(callable: transport)

        let state = try await repository.claim()

        XCTAssertTrue(state.trialUsed)
        XCTAssertTrue(state.trialStartedNow)
        XCTAssertEqual(
            try XCTUnwrap(state.trialEndsAt).timeIntervalSince1970,
            expiry.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertFalse(state.serverAllAccess)
        XCTAssertEqual(transport.calls.map(\.name), ["entitlementTrialV2"])
        XCTAssertEqual(transport.calls.first?.data["requestTrial"] as? Bool, true)
        XCTAssertNil(transport.calls.first?.data["activeProductIDs"])
    }

    func testSocialActionsUseTheAppCheckCallableSurface() async throws {
        let transport = SocialCallableTransportStub(responses: [
            "socialActionV2": ["ok": true, "status": "requested"]
        ])
        let repository = SocialGraphRepository(callable: transport)

        let status = try await repository.act(.follow, targetUID: "musician-42")

        XCTAssertEqual(status, "requested")
        XCTAssertEqual(transport.calls.map(\.name), ["socialActionV2"])
        XCTAssertEqual(transport.calls.first?.data["action"] as? String, "follow")
        XCTAssertEqual(transport.calls.first?.data["targetUID"] as? String, "musician-42")
    }

    func testSocialConnectionCallableResponseDecodesWithoutUserContent() async throws {
        let transport = SocialCallableTransportStub(responses: [
            "socialConnectionsV2": [
                "ok": true,
                "rows": [[
                    "id": "aya",
                    "displayName": "Aya",
                    "handle": "aya.music",
                    "profilePhotoURL": "",
                    "instrument": "Cello",
                    "avatarID": "avatar-cello",
                    "isIncoming": true
                ]]
            ]
        ])
        let repository = SocialGraphRepository(callable: transport)

        let rows = try await repository.connections(section: .requests)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "aya")
        XCTAssertEqual(rows.first?.handle, "aya.music")
        XCTAssertEqual(rows.first?.instrument, "Cello")
        XCTAssertEqual(rows.first?.isIncoming, true)
        XCTAssertEqual(transport.calls.first?.name, "socialConnectionsV2")
        XCTAssertEqual(transport.calls.first?.data["section"] as? String, "requests")
    }

    func testSocialRelationshipCallablePreservesServerState() async throws {
        let transport = SocialCallableTransportStub(responses: [
            "socialRelationshipV2": ["ok": true, "state": "mutualFollowing"]
        ])
        let repository = SocialGraphRepository(callable: transport)

        let state = try await repository.relationship(targetUID: "aya")

        XCTAssertEqual(state, .mutualFollowing)
        XCTAssertEqual(transport.calls.first?.name, "socialRelationshipV2")
    }

    func testFriendMutationsUseTheAppCheckCallableSurface() async throws {
        let transport = SocialCallableTransportStub(responses: [
            "friendInviteByCodeV2": ["ok": true, "targetUID": "musician-42"],
            "friendActionV2": ["ok": true, "targetUID": "musician-42"]
        ])
        let repository = FirebaseBuddiesRepository(callable: transport)
        let profile = FirebaseUserProfile(
            uid: "musician-me",
            displayName: "Julian Marco",
            friendCode: "JULI-2048",
            nameEditUsed: false,
            avatarID: "avatar_note",
            profilePhotoURL: "",
            bio: "",
            instrument: "Violin",
            publicLevel: 18
        )
        let incoming = BuddyInvite(
            id: "invite-incoming",
            fromUid: "musician-42",
            toUid: "musician-me",
            fromDisplayName: "Aya Chen",
            fromFriendCode: "AYAC-2345",
            toDisplayName: "Julian Marco",
            toFriendCode: "JULI-2048",
            status: .pending,
            createdAt: .now
        )
        let outgoing = BuddyInvite(
            id: "invite-outgoing",
            fromUid: "musician-me",
            toUid: "musician-42",
            fromDisplayName: "Julian Marco",
            fromFriendCode: "JULI-2048",
            toDisplayName: "Aya Chen",
            toFriendCode: "AYAC-2345",
            status: .pending,
            createdAt: .now
        )

        let target = try await repository.sendInvite(from: profile, friendCode: "ayac-2345")
        try await repository.sendInvite(from: profile, to: "musician-42")
        try await repository.acceptInvite(incoming, myUID: profile.uid)
        try await repository.declineInvite(incoming)
        try await repository.cancelInvite(outgoing)
        try await repository.removeBuddy(myUID: profile.uid, buddyUID: "musician-42")

        XCTAssertEqual(target, "musician-42")
        XCTAssertEqual(
            transport.calls.map(\.name),
            [
                "friendInviteByCodeV2",
                "friendActionV2",
                "friendActionV2",
                "friendActionV2",
                "friendActionV2",
                "friendActionV2"
            ]
        )
        XCTAssertEqual(transport.calls[0].data["friendCode"] as? String, "AYAC-2345")
        XCTAssertEqual(transport.calls[1].data["action"] as? String, "invite")
        XCTAssertEqual(transport.calls[1].data["targetUID"] as? String, "musician-42")
        XCTAssertEqual(transport.calls[2].data["action"] as? String, "accept")
        XCTAssertEqual(transport.calls[2].data["inviteID"] as? String, "invite-incoming")
        XCTAssertEqual(transport.calls[3].data["action"] as? String, "decline")
        XCTAssertEqual(transport.calls[4].data["action"] as? String, "cancel")
        XCTAssertEqual(transport.calls[5].data["action"] as? String, "remove")
    }

    func testDeterministicPracticeFixtureReplacesPriorQASaves() throws {
        let schema = Schema([
            PracticeSessionModel.self,
            LoopPracticeLogModel.self,
            PracticePlanLogModel.self,
            RhythmAccuracyTakeModel.self,
            RunThroughModel.self,
            ScaleIntonationTakeModel.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let store = SessionStore()
        store.configure(context: ModelContext(container))

        store.applyStudioQuestFixture()
        XCTAssertEqual(store.sessions.count, 4)
        XCTAssertEqual(store.sessions.first?.noteTitle, "Bach: Partita No. 2")

        XCTAssertTrue(
            store.addSession(
                date: .now,
                durationSeconds: 3,
                notes: "",
                noteTitle: "UI test save"
            )
        )
        XCTAssertEqual(store.sessions.count, 5)

        store.applyStudioQuestFixture()

        XCTAssertEqual(store.sessions.count, 4)
        XCTAssertFalse(store.sessions.contains { $0.noteTitle == "UI test save" })
        XCTAssertEqual(
            Set(store.sessions.map(\.noteTitle)),
            Set([
                "Bach: Partita No. 2",
                "Technique and scales",
                "Brahms: Sonata in F minor",
                "Sight-reading"
            ])
        )
    }
}

@MainActor
private final class SocialCallableTransportStub: FirebaseCallableTransport {
    struct Call {
        let name: String
        let data: [String: Any]
    }

    private let responses: [String: [String: Any]]
    private(set) var calls: [Call] = []

    init(responses: [String: [String: Any]]) {
        self.responses = responses
    }

    func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        calls.append(Call(name: name, data: data))
        guard let response = responses[name] else {
            throw FirebaseCallableError.invalidResponse
        }
        return response
    }
}
