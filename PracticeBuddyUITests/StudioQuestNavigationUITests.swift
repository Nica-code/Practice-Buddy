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

    func testYouDestinationLinksOpenTheNewV2Screens() {
        let app = launch(destination: 3)
        for destination in ["Goals", "History", "Studio", "Settings"] {
            let link = app.buttons[destination]
            XCTAssertTrue(link.waitForExistence(timeout: 6), "Missing You link \(destination)")
            XCTAssertTrue(reveal(link, in: app), "You link \(destination) was not reachable")
            link.tap()
            XCTAssertTrue(app.staticTexts[destination].waitForExistence(timeout: 4))
            app.navigationBars.buttons.element(boundBy: 0).tap()
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
        let app = launch(destination: 2)
        let friendPill = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Aya Chen")
        ).firstMatch
        XCTAssertTrue(friendPill.waitForExistence(timeout: 8))

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
}
