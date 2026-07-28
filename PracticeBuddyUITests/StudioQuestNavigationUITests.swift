import XCTest

final class StudioQuestNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(
        destination: Int = 0,
        route: String? = nil,
        populated: Bool = true,
        communityPopulated: Bool = true,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // UI-test methods intentionally launch several deterministic states in
        // one runner process. Explicitly terminate the previous app process so
        // UIKit scene restoration cannot write a stale tab selection into the
        // new router before its immutable QA configuration owns the shell.
        if app.state != .notRunning {
            app.terminate()
        }
        app.launchArguments = [
            "--qa-skip-onboarding",
            "--qa-skip-version-gate",
            "--qa-destination", "\(destination)",
            "--qa-launch-token", UUID().uuidString
        ] + extraArguments
        if communityPopulated {
            app.launchArguments.append("--qa-community-populated")
        }
        if populated {
            app.launchArguments.append("--qa-populated")
        }
        if let route {
            app.launchArguments += ["--qa-route", route]
        }
        app.launch()
        return app
    }

    @discardableResult
    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 8
    ) -> Bool {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<maximumSwipes {
            if element.exists, element.isHittable {
                return true
            }
            if scrollView.exists {
                scrollView.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        return element.exists && element.isHittable
    }

    @discardableResult
    private func revealAbovePracticeDock(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 14
    ) -> Bool {
        let dock = app.buttons["practice.dock"]
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<maximumSwipes {
            if element.exists,
               element.isHittable,
               (!dock.exists || element.frame.maxY <= dock.frame.minY) {
                return true
            }
            if scrollView.exists {
                scrollView.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        return element.exists
            && element.isHittable
            && (!dock.exists || element.frame.maxY <= dock.frame.minY)
    }

    func testFourDestinationShellAndQuestPath() {
        let app = launch(destination: 1)

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Quest"].exists)
        XCTAssertTrue(app.tabBars.buttons["Community"].exists)
        XCTAssertTrue(app.tabBars.buttons["You"].exists)
        XCTAssertTrue(app.staticTexts["Quest"].exists)
    }

    func testLaunchLoadingAndMandatoryUpdateUseStudioQuestStates() {
        let loadingApp = launch(
            populated: false,
            communityPopulated: false,
            extraArguments: ["--qa-state", "loading"]
        )
        XCTAssertTrue(
            loadingApp.staticTexts["Loading your practice world…"].waitForExistence(timeout: 8)
        )
        loadingApp.terminate()

        let updateApp = launch(
            populated: false,
            communityPopulated: false,
            extraArguments: ["--qa-version-gate", "updateRequired"]
        )
        XCTAssertTrue(updateApp.buttons["versionGate.update"].waitForExistence(timeout: 8))
        XCTAssertTrue(updateApp.buttons["versionGate.recheck"].exists)
    }

    func testEveryFeaturedQuestNodeOpensAFunctionalDetail() {
        let app = launch(destination: 1, populated: false)
        let questNames = [
            "Warm-up warrior",
            "Rhythm clarity",
            "Dynamic control",
            "Expression mastery"
        ]

        for name in questNames {
            let node = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", name)
            ).firstMatch
            XCTAssertTrue(node.waitForExistence(timeout: 6), "Missing quest node \(name)")
            XCTAssertTrue(reveal(node, in: app), "Quest node \(name) was not reachable")
            node.tap()
            XCTAssertTrue(
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", name)
                ).firstMatch.waitForExistence(timeout: 4)
            )
            XCTAssertTrue(app.staticTexts["Progress"].exists)
            app.buttons["Close"].tap()
        }
    }

    /// iOS 26 renders the back affordance as a floating circular button that
    /// XCUITest does not expose under `app.navigationBars`, so reaching for
    /// `navigationBars.buttons` finds nothing. Falls back to the edge swipe.
    private func goBack(in app: XCUIApplication) {
        let barButton = app.navigationBars.buttons.element(boundBy: 0)
        if barButton.exists, barButton.isHittable {
            barButton.tap()
            return
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func elapsedSeconds(from accessibilityValue: String) -> Int? {
        let duration = accessibilityValue
            .split(separator: "·", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let components = duration
            .split(separator: ":")
            .compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return components[0] * 60 + components[1]
    }

    func testYouDestinationLinksOpenTheNewV2Screens() {
        let app = launch(destination: 3)
        for destination in ["Goals", "History", "Avatar Studio", "Settings"] {
            // Re-enter You from the tab bar each time. Returning by gesture can
            // leave the pop mid-flight, and the tab's scroll offset survives, so
            // driving from a known state is what keeps this deterministic.
            let youTab = app.tabBars.buttons["You"]
            XCTAssertTrue(youTab.waitForExistence(timeout: 8), "You tab missing")
            youTab.tap()

            let link = app.buttons[destination]
            XCTAssertTrue(link.waitForExistence(timeout: 6), "Missing You link \(destination)")
            XCTAssertTrue(
                revealAbovePracticeDock(link, in: app),
                "\(destination) could not scroll fully above the Practice Dock"
            )
            link.tap()
            XCTAssertTrue(
                app.staticTexts[destination].waitForExistence(timeout: 6),
                "You link \(destination) did not open its screen"
            )
            goBack(in: app)
        }
    }

    func testTodayEditorialHierarchyRoutesToPracticeAndSmartCoach() {
        let app = launch(destination: 0)

        XCTAssertTrue(app.buttons["today.startPractice"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["today.setupPractice"].exists)
        XCTAssertTrue(
            reveal(app.buttons["today.smartCoach"], in: app),
            "Smart Coach should remain reachable above the Practice Dock"
        )
        app.buttons["today.smartCoach"].tap()
        XCTAssertTrue(app.staticTexts["Smart Coach"].waitForExistence(timeout: 6))
    }

    func testCommunityFeedFixtureAndConnectionsSummaryAreDeterministic() {
        let app = launch(destination: 2)

        XCTAssertTrue(app.staticTexts["Breakthrough"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["community.connections"].exists)
        app.buttons["community.connections"].tap()
        XCTAssertTrue(app.staticTexts["Connections"].waitForExistence(timeout: 6))
    }

    func testAllSecondaryRoutesAreReachableWithoutLegacyJumpTokens() {
        let routesAndTitles = [
            ("goals", "Goals"),
            ("history", "History"),
            ("profile", "Profile"),
            ("settings", "Settings"),
            ("duel", "Duel Arena"),
            ("avatar", "Avatar Studio"),
            ("library", "Practice Library"),
            ("notifications", "Notifications")
        ]

        for (route, title) in routesAndTitles {
            let app = launch(route: route)
            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: 7),
                "Route \(route) did not open \(title)"
            )
            app.terminate()
        }
    }

    func testTheEntireFriendPillOpensItsActionChooserThenTheExactConversation() {
        // Friends live under Community -> Connections, not on the feed root.
        // This previously launched straight to the Community tab, where an
        // anonymous QA session only ever sees the "join your community" gate.
        let app = launch(destination: 2, route: "communityFriends")
        let friendPill = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Aya Chen")
        ).firstMatch
        XCTAssertTrue(friendPill.waitForExistence(timeout: 8), "Friend fixture did not appear")

        let rightEdgePoint = friendPill.coordinate(
            withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
        )
        rightEdgePoint.tap()

        XCTAssertTrue(app.buttons["Message"].waitForExistence(timeout: 6))
        app.buttons["Message"].tap()
        XCTAssertTrue(app.navigationBars["Aya Chen"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.textFields["Write a message…"].exists)
    }

    func testPublicProfileActionsReflectRelationshipState() {
        let followApp = launch(route: "publicProfileNone")
        let follow = followApp.buttons["profile.follow"]
        XCTAssertTrue(reveal(follow, in: followApp), "A new relationship should offer Follow")
        follow.tap()
        XCTAssertTrue(
            followApp.buttons["profile.unfollow"].waitForExistence(timeout: 5),
            "Following a public fixture should update the profile action in place"
        )
        followApp.terminate()

        let requestedApp = launch(route: "publicProfileRequested")
        let requested = requestedApp.buttons["profile.cancelFollowRequest"]
        XCTAssertTrue(reveal(requested, in: requestedApp), "A pending private-profile request should show Requested")
        requested.tap()
        XCTAssertTrue(
            requestedApp.buttons["profile.follow"].waitForExistence(timeout: 5),
            "Canceling a request should restore the Follow action"
        )
        requestedApp.terminate()

        let friendApp = launch(route: "publicProfileFriend")
        XCTAssertTrue(
            reveal(friendApp.buttons["profile.message"], in: friendApp),
            "Accepted friends should expose messaging"
        )
        XCTAssertTrue(friendApp.buttons["profile.duel"].exists)
    }

    func testBlockedPublicProfileCanBeUnblocked() {
        let app = launch(route: "publicProfileBlocked")
        let unblock = app.buttons["profile.unblock"]
        XCTAssertTrue(reveal(unblock, in: app), "Blocked profiles should expose Unblock")
        unblock.tap()
        XCTAssertTrue(
            app.buttons["profile.follow"].waitForExistence(timeout: 5),
            "Unblocking should restore the available follow action"
        )
    }

    func testAccessibilityTextAndPseudolocalizationKeepCoreControlsReachable() {
        let app = launch(
            route: "settings",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
                "-NSDoubleLocalizedStrings", "YES",
                "-NSShowNonLocalizedStrings", "YES"
            ]
        )

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Settings")
            ).firstMatch.waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.tabBars.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Today")
            ).firstMatch.exists
        )
        let firstSwitch = app.switches.firstMatch
        XCTAssertTrue(
            reveal(firstSwitch, in: app, maximumSwipes: 12),
            "Settings controls were not reachable at the largest accessibility text size"
        )
    }

    func testSmartLoopDeterministicRuntimeCanPauseResumeAndReachAResult() {
        let app = launch(
            route: "smartLoop",
            populated: false,
            extraArguments: [
                "--qa-appearance", "light",
                "--qa-tool-state", "running"
            ]
        )

        XCTAssertTrue(
            app.buttons["smartloop.pause"].waitForExistence(timeout: 8),
            "Smart Loop running fixture did not load"
        )
        XCTAssertTrue(app.buttons["smartloop.finish"].exists)

        app.buttons["smartloop.pause"].tap()
        XCTAssertTrue(app.buttons["smartloop.pause"].waitForExistence(timeout: 4))
        app.buttons["smartloop.pause"].tap()

        app.buttons["smartloop.finish"].tap()
        XCTAssertTrue(
            app.buttons["smartloop.save"].waitForExistence(timeout: 6),
            "Finishing Smart Loop did not produce a savable result"
        )
    }

    func testWarmUpRuntimePausesResumesAndReachesAResult() {
        let app = launch(
            route: "warmUp",
            populated: false,
            extraArguments: [
                "--qa-appearance", "light",
                "--qa-tool-state", "running"
            ]
        )

        let pause = app.buttons["warmup.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 8), "Warm-up running fixture did not load")
        let dock = app.buttons["practice.dock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 4))
        let liveElapsed = app.descendants(matching: .any)["warmup.elapsed"]
        XCTAssertTrue(liveElapsed.waitForExistence(timeout: 4))
        let dockSeconds = elapsedSeconds(from: dock.value as? String ?? "")
        let liveSeconds = elapsedSeconds(from: liveElapsed.value as? String ?? "")
        XCTAssertNotNil(dockSeconds)
        XCTAssertNotNil(liveSeconds)
        XCTAssertLessThanOrEqual(
            abs((dockSeconds ?? 0) - (liveSeconds ?? 0)),
            1,
            "The Practice Dock and Warm-up runtime did not share one elapsed clock"
        )
        pause.tap()
        XCTAssertTrue(app.buttons["warmup.pause"].waitForExistence(timeout: 4))
        app.buttons["warmup.pause"].tap()

        let finish = app.buttons["warmup.finish"]
        XCTAssertTrue(
            reveal(finish, in: app),
            "Warm-up finish action was hidden by the Practice Dock"
        )
        finish.tap()
        XCTAssertTrue(
            app.buttons["warmup.done"].waitForExistence(timeout: 6),
            "Finishing Warm-up did not produce a saved result"
        )
    }

    func testPracticeLibraryCardsAndFavoritesUseTheirFullSurfaces() {
        let app = launch(route: "library", populated: false)
        let warmUpCard = app.buttons["library.tool.warm-up"]
        XCTAssertTrue(warmUpCard.waitForExistence(timeout: 8))
        XCTAssertTrue(reveal(warmUpCard, in: app))

        warmUpCard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Warm-up Generator"].waitForExistence(timeout: 6))
    }

    func testAccountSetupEmailFlowUsesStudioQuestFields() {
        let app = launch(route: "accountSetup", populated: false)
        XCTAssertTrue(app.staticTexts["Protect your progress"].waitForExistence(timeout: 6))

        let email = app.buttons["account.email"]
        XCTAssertTrue(reveal(email, in: app))
        email.tap()
        XCTAssertTrue(app.buttons["auth.mode.signUp"].waitForExistence(timeout: 6))
        XCTAssertTrue(
            app.descendants(matching: .any)["auth.email"].waitForExistence(timeout: 4),
            "Email field was missing from the account sheet"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["auth.password"].exists,
            "Password field was missing from the account sheet"
        )
    }

    func testRoomEditorPlacesStarterDecorationAndExposesAccessibleControls() {
        let app = launch(route: "roomEditor", populated: false)
        let decoration = app.buttons["room.decoration.room_decoration_plant"]
        XCTAssertTrue(decoration.waitForExistence(timeout: 8))
        decoration.tap()

        XCTAssertTrue(app.buttons["room.doneEditingItem"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["room.done"].exists)
        XCTAssertTrue(app.buttons["room.changeRoom"].exists)
    }

    func testShopEarnMoreActionRoutesToQuest() {
        let app = launch(route: "shop", populated: false)
        let earnMore = app.buttons["shop.earnMore"]
        XCTAssertTrue(earnMore.waitForExistence(timeout: 8))
        earnMore.tap()
        XCTAssertTrue(app.staticTexts["Quest"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.tabBars.buttons["Quest"].isSelected)
    }

    func testDuelCaptureFixtureUsesTheSharedRecordingSurface() {
        let app = launch(
            route: "duelCapture",
            populated: false,
            extraArguments: ["--qa-appearance", "dark"]
        )

        XCTAssertTrue(app.staticTexts["Record Duel Take"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["duel.startRecording"].exists)
        XCTAssertTrue(app.staticTexts["C major · clean pulse"].exists)
    }

    func testGuidedPracticeRuntimePausesAndReachesPrivateReflection() {
        let app = launch(
            route: "planExecuteReflect",
            populated: false,
            extraArguments: [
                "--qa-appearance", "dark",
                "--qa-tool-state", "running"
            ]
        )

        let pause = app.buttons["guided.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 8), "Guided practice running fixture did not load")
        pause.tap()
        XCTAssertTrue(app.buttons["guided.pause"].waitForExistence(timeout: 4))
        app.buttons["guided.pause"].tap()

        let reflect = app.buttons["guided.reflect"]
        XCTAssertTrue(
            reveal(reflect, in: app, maximumSwipes: 8),
            "Guided practice reflection action was hidden by the Practice Dock"
        )
        reflect.tap()
        XCTAssertTrue(
            app.buttons["guided.save"].waitForExistence(timeout: 6),
            "Guided practice did not reach its private reflection"
        )
    }

    func testRunThroughRuntimeMarksPausesAndReachesReview() {
        let app = launch(
            route: "runThrough",
            populated: false,
            extraArguments: [
                "--qa-appearance", "light",
                "--qa-tool-state", "running"
            ]
        )

        let marker = app.buttons["runthrough.marker"]
        XCTAssertTrue(marker.waitForExistence(timeout: 8), "Run-through running fixture did not load")
        marker.tap()

        let pause = app.buttons["runthrough.pause"]
        XCTAssertTrue(pause.exists)
        let finish = app.buttons["runthrough.finish"]
        XCTAssertTrue(
            reveal(finish, in: app, maximumSwipes: 8),
            "Run-through finish action was hidden by the Practice Dock"
        )
        finish.tap()
        XCTAssertTrue(
            app.buttons["runthrough.save"].waitForExistence(timeout: 6),
            "Finishing Run-through did not produce a savable review"
        )
    }

    func testRunThroughPermissionDeniedStateExplainsRecovery() {
        let app = launch(
            route: "runThrough",
            populated: false,
            extraArguments: [
                "--qa-appearance", "dark",
                "--qa-tool-state", "permissionDenied"
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Microphone access is off"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    func testRhythmAccuracyRuntimePausesAndReachesAResult() {
        let app = launch(
            route: "rhythm",
            populated: false,
            extraArguments: [
                "--qa-appearance", "light",
                "--qa-tool-state", "running"
            ]
        )

        let pause = app.buttons["rhythm.pause"]
        XCTAssertTrue(
            pause.waitForExistence(timeout: 8),
            "Rhythm Accuracy running fixture did not load"
        )
        pause.tap()
        XCTAssertTrue(app.buttons["rhythm.pause"].waitForExistence(timeout: 4))
        app.buttons["rhythm.pause"].tap()

        let finish = app.buttons["rhythm.finish"]
        XCTAssertTrue(
            reveal(finish, in: app, maximumSwipes: 8),
            "Rhythm Accuracy finish action was hidden by the Practice Dock"
        )
        finish.tap()
        XCTAssertTrue(
            app.buttons["rhythm.save"].waitForExistence(timeout: 6),
            "Finishing Rhythm Accuracy did not produce a savable result"
        )
    }

    func testRhythmAccuracyPermissionDeniedStateExplainsRecovery() {
        let app = launch(
            route: "rhythm",
            populated: false,
            extraArguments: [
                "--qa-appearance", "dark",
                "--qa-tool-state", "permissionDenied"
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Microphone access is off"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    func testIntonationRuntimePausesAndReachesAResult() {
        let app = launch(
            route: "intonation",
            populated: false,
            extraArguments: [
                "--qa-appearance", "light",
                "--qa-tool-state", "running"
            ]
        )

        let pause = app.buttons["intonation.pause"]
        XCTAssertTrue(
            pause.waitForExistence(timeout: 8),
            "Intonation running fixture did not load"
        )
        pause.tap()
        XCTAssertTrue(app.buttons["intonation.pause"].waitForExistence(timeout: 4))
        app.buttons["intonation.pause"].tap()

        let finish = app.buttons["intonation.finish"]
        XCTAssertTrue(
            reveal(finish, in: app, maximumSwipes: 8),
            "Intonation finish action was hidden by the Practice Dock"
        )
        finish.tap()
        XCTAssertTrue(
            app.buttons["intonation.save"].waitForExistence(timeout: 6),
            "Finishing Intonation did not produce a savable result"
        )
    }

    func testIntonationPermissionDeniedStateExplainsRecovery() {
        let app = launch(
            route: "intonation",
            populated: false,
            extraArguments: [
                "--qa-appearance", "dark",
                "--qa-tool-state", "permissionDenied"
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Microphone access is off"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    func testMetronomeRuntimeStopsThroughItsFullPrimarySurface() {
        let app = launch(
            route: "metronome",
            populated: false,
            extraArguments: [
                "--qa-appearance", "light",
                "--qa-tool-state", "running"
            ]
        )

        let toggle = app.buttons["metronome.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(toggle.label.localizedCaseInsensitiveContains("Stop metronome"))
        toggle.tap()
        XCTAssertTrue(
            app.buttons["metronome.toggle"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.buttons["metronome.toggle"].label
                .localizedCaseInsensitiveContains("Start metronome")
        )
    }

    func testTunerRuntimeStopsListeningAndKeepsControlsReachable() {
        let app = launch(
            route: "tuner",
            populated: false,
            extraArguments: [
                "--qa-appearance", "dark",
                "--qa-tool-state", "running"
            ]
        )

        let toggle = app.buttons["tuner.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(toggle.label.localizedCaseInsensitiveContains("Stop listening"))
        toggle.tap()
        XCTAssertTrue(app.buttons["tuner.reference"].exists)
        XCTAssertTrue(
            app.buttons["tuner.toggle"].label
                .localizedCaseInsensitiveContains("Start tuner")
        )
    }

    func testEveryPracticeToolKeepsFailedResultsAvailableForRetry() {
        let tools = [
            ("smartLoop", "smartloop.status"),
            ("warmUp", "warmup.status"),
            ("planExecuteReflect", "guided.status"),
            ("runThrough", "runthrough.status"),
            ("rhythm", "rhythm.status"),
            ("intonation", "intonation.status"),
            ("metronome", "metronome.status"),
            ("tuner", "tuner.status")
        ]

        for (route, statusIdentifier) in tools {
            let app = launch(
                route: route,
                populated: false,
                extraArguments: [
                    "--qa-appearance", "dark",
                    "--qa-tool-state", "saveError"
                ]
            )
            let error = app.descendants(matching: .any)[statusIdentifier]
            XCTAssertTrue(
                error.waitForExistence(timeout: 8),
                "\(route) did not retain a reader-facing failed-save state"
            )
            app.terminate()
        }
    }

    func testEveryPracticeToolPresentsItsRecoveredState() {
        let recoveredStates = [
            ("smartLoop", "smartloop.status"),
            ("warmUp", "warmup.status"),
            ("planExecuteReflect", "guided.status"),
            ("runThrough", "runthrough.status"),
            ("rhythm", "rhythm.status"),
            ("intonation", "intonation.status"),
            ("metronome", "metronome.status"),
            ("tuner", "tuner.status")
        ]

        for (route, statusIdentifier) in recoveredStates {
            let app = launch(
                route: route,
                populated: false,
                extraArguments: [
                    "--qa-appearance", "light",
                    "--qa-tool-state", "recovered"
                ]
            )
            let recovery = app.descendants(matching: .any)[statusIdentifier]
            XCTAssertTrue(
                recovery.waitForExistence(timeout: 8),
                "\(route) did not present its deterministic recovery state"
            )
            app.terminate()
        }
    }

    func testKoreanAndRomanianLaunchesKeepThePrimaryPracticeActionReachable() {
        let languages = [
            ("ko", "ko_KR"),
            ("ro", "ro_RO")
        ]

        for (language, locale) in languages {
            let app = launch(
                extraArguments: [
                    "-AppleLanguages", "(\(language))",
                    "-AppleLocale", locale
                ]
            )
            XCTAssertTrue(
                app.buttons["today.startPractice"].waitForExistence(timeout: 8),
                "The primary Today action was not reachable in \(language)"
            )
            XCTAssertEqual(app.tabBars.buttons.count, 4)
            app.terminate()
        }
    }
}
