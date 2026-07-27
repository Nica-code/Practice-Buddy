import XCTest

final class StudioQuestNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(
        destination: Int = 0,
        route: String? = nil,
        populated: Bool = true,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--qa-skip-onboarding",
            "--qa-skip-version-gate",
            "--qa-community-populated",
            "--qa-destination", "\(destination)"
        ] + extraArguments
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

    func testFourDestinationShellAndQuestPath() {
        let app = launch(destination: 1)

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Quest"].exists)
        XCTAssertTrue(app.tabBars.buttons["Community"].exists)
        XCTAssertTrue(app.tabBars.buttons["You"].exists)
        XCTAssertTrue(app.staticTexts["Quest"].exists)
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

    func testYouDestinationLinksOpenTheNewV2Screens() {
        let app = launch(destination: 3)
        for destination in ["Goals", "History", "Avatar Studio", "Shop", "Settings"] {
            // Re-enter You from the tab bar each time. Returning by gesture can
            // leave the pop mid-flight, and the tab's scroll offset survives, so
            // driving from a known state is what keeps this deterministic.
            let youTab = app.tabBars.buttons["You"]
            XCTAssertTrue(youTab.waitForExistence(timeout: 8), "You tab missing")
            youTab.tap()

            let link = app.buttons[destination]
            XCTAssertTrue(link.waitForExistence(timeout: 6), "Missing You link \(destination)")
            // The link list sits below the hero, so the lower rows start out
            // behind the practice dock and tab bar and report as not hittable.
            // Scroll toward them, then tap by coordinate, which lands correctly
            // even when XCUITest still considers the element occluded.
            _ = reveal(link, in: app, maximumSwipes: 12)
            link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(
                app.staticTexts[destination].waitForExistence(timeout: 6),
                "You link \(destination) did not open its screen"
            )
            goBack(in: app)
        }
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
}
