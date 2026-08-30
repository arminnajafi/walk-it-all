import XCTest

final class WalkItAllUITests: XCTestCase {
    @MainActor
    func testMapFirstLaunchShowsRestrainedEmptyState() {
        let app = launch(arguments: ["-resetOnboarding", "-skipOnboarding"])

        XCTAssertTrue(app.descendants(matching: .any)["manhattan-recenter"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["No outdoor routes mapped yet"].exists)
        XCTAssertTrue(app.buttons["Connect Apple Health"].exists)
        XCTAssertFalse(app.staticTexts["of Manhattan walked"].exists)
        attachScreenshot(named: "01-main-empty-map", app: app)
    }

    @MainActor
    func testTwoStepOnboardingExplainsMapAndPrivacy() {
        let app = launch(arguments: ["-resetOnboarding"])

        XCTAssertTrue(app.staticTexts["See everywhere you’ve covered."].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].exists)
        XCTAssertFalse(app.buttons["Not now"].exists)
        attachScreenshot(named: "02-onboarding-map", app: app)

        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Private by design."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding-connect-health"].exists)
        XCTAssertTrue(app.buttons["Not now"].exists)
        attachScreenshot(named: "03-onboarding-privacy", app: app)
    }

    @MainActor
    func testNotNowReachesMapAndHealthCanBeConnectedLater() {
        let app = launch(arguments: ["-resetOnboarding"])
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 30))
        app.buttons["Continue"].tap()
        app.buttons["Not now"].tap()

        XCTAssertTrue(app.staticTexts["No outdoor routes mapped yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Connect Apple Health"].exists)
    }

    @MainActor
    func testAccessibilityXXXLKeepsOnboardingActionsReachable() {
        let app = launch(arguments: [
            "-resetOnboarding",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])

        XCTAssertTrue(app.staticTexts["See everywhere you’ve covered."].waitForExistence(timeout: 30))
        let continueButton = app.buttons["Continue"]
        scrollUntilHittable(continueButton, in: app)
        XCTAssertTrue(continueButton.isHittable)
        continueButton.tap()

        let connectButton = app.buttons["onboarding-connect-health"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(connectButton.isHittable)
        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        XCTAssertTrue(notNow.isHittable)
        attachScreenshot(named: "04-onboarding-accessibility-xxxl", app: app)
    }

    @MainActor
    func testDetailsExplainMapHealthPrivacyAndRecovery() {
        let app = launch(arguments: ["-resetOnboarding", "-skipOnboarding"])
        let about = app.buttons["About Walk It All"]
        XCTAssertTrue(about.waitForExistence(timeout: 30))
        about.tap()

        XCTAssertTrue(app.navigationBars["Walk It All"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Refresh from Apple Health"].exists)
        XCTAssertTrue(app.buttons["Rebuild full history"].exists)

        let aboutMap = app.buttons["About this map"]
        scrollUntilHittable(aboutMap, in: app)
        XCTAssertTrue(aboutMap.isHittable)
        aboutMap.tap()
        XCTAssertTrue(app.navigationBars["About This Map"].waitForExistence(timeout: 5))
        let limitation = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "not proof that every street")
        ).firstMatch
        scrollUntilHittable(limitation, in: app)
        XCTAssertTrue(limitation.exists)
        attachScreenshot(named: "05-about-map", app: app)
        app.navigationBars["About This Map"].buttons["Walk It All"].tap()

        let privacy = app.buttons["Privacy and recovery"]
        scrollUntilHittable(privacy, in: app)
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy and Recovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No route uploads"].exists)
        attachScreenshot(named: "06-privacy-recovery", app: app)
        app.navigationBars["Privacy and Recovery"].buttons["Walk It All"].tap()

        let healthAccess = app.buttons["Review Health access"]
        scrollUntilHittable(healthAccess, in: app)
        healthAccess.tap()
        XCTAssertTrue(app.navigationBars["Health Access"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Request Apple Health Access"].exists)
    }

    @MainActor
    func testPopulatedMapUsesRestrainedLiveTrailActionAndSupportsHistorySelection() {
        let app = launch(arguments: ["-resetOnboarding", "-skipOnboarding", "-uiTestPopulated"])
        XCTAssertTrue(app.buttons["start-live-trail"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["2 walks mapped"].exists)
        XCTAssertTrue(app.buttons["current-location"].exists)
        app.buttons["About Walk It All"].tap()
        let history = app.buttons["Workout history"]
        scrollUntilHittable(history, in: app)
        XCTAssertTrue(history.isHittable)
        history.tap()

        let first = app.buttons.matching(identifier: "workout-history-row").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()

        XCTAssertTrue(app.descendants(matching: .any)["selected-workout-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Walking"].exists)
        XCTAssertTrue(app.staticTexts["Orange with a contrasting outline shows this workout"].exists)
        attachScreenshot(named: "07-selected-workout", app: app)
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.buttons["start-live-trail"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFirstLiveTrailStartExplainsIndependentTemporaryStorageAndBackgroundUse() {
        let app = launch(arguments: ["-resetOnboarding", "-skipOnboarding", "-uiTestPopulated"])
        let start = app.buttons["start-live-trail"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()

        XCTAssertTrue(app.navigationBars["Live Trail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["See where you go now"].exists)
        XCTAssertTrue(app.staticTexts["Start Live Trail here"].exists)
        XCTAssertTrue(app.staticTexts["Pause and resume when needed"].exists)
        XCTAssertTrue(app.staticTexts["Finish when you are done"].exists)
        let confirm = app.buttons["confirm-start-live-trail"]
        XCTAssertTrue(confirm.exists)
        XCTAssertTrue(confirm.isHittable, "The primary Live Trail action must stay above the fold")
        attachScreenshot(named: "08-live-trail-intro", app: app)
    }

    @MainActor
    func testActiveLiveTrailUsesTheSharedControlLayout() {
        let app = launch(arguments: [
            "-resetOnboarding", "-skipOnboarding", "-uiTestPopulated",
            "-uiTestActiveLiveTrail",
        ])

        XCTAssertTrue(app.descendants(matching: .any)["active-live-trail"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Live Trail"].exists)
        XCTAssertTrue(app.staticTexts["Active · continues when your screen locks"].exists)
        let pause = app.buttons["pause-live-trail"]
        let finish = app.buttons["finish-live-trail"]
        XCTAssertTrue(pause.isHittable)
        XCTAssertTrue(finish.isHittable)
        XCTAssertEqual(pause.frame.width, finish.frame.width, accuracy: 1)
        XCTAssertEqual(pause.frame.height, finish.frame.height, accuracy: 1)
        XCTAssertEqual(pause.frame.minY, finish.frame.minY, accuracy: 1)
        attachScreenshot(named: "09-live-trail-active", app: app)
    }

    @MainActor
    func testPausedLiveTrailClearlyOffersResumeOrFinalFinish() {
        let app = launch(arguments: [
            "-resetOnboarding", "-skipOnboarding", "-uiTestPopulated",
            "-uiTestPausedLiveTrail",
        ])

        XCTAssertTrue(app.descendants(matching: .any)["paused-live-trail"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Live Trail"].exists)
        XCTAssertTrue(app.staticTexts["Paused · location is off"].exists)
        let resume = app.buttons["resume-live-trail"]
        let finish = app.buttons["finish-paused-live-trail"]
        XCTAssertTrue(resume.isHittable)
        XCTAssertTrue(finish.isHittable)
        XCTAssertEqual(resume.frame.width, finish.frame.width, accuracy: 1)
        XCTAssertEqual(resume.frame.height, finish.frame.height, accuracy: 1)
        XCTAssertEqual(resume.frame.minY, finish.frame.minY, accuracy: 1)
        XCTAssertFalse(app.buttons["clear-paused-live-trail"].exists)
        attachScreenshot(named: "09-live-trail-paused", app: app)

        finish.tap()
        XCTAssertTrue(app.staticTexts["Finish Live Trail?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Finish stops tracking. This trail will remain on the map until you clear it or start a new one."].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["paused-live-trail"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFinishedLiveTrailStaysUntilStartNewOrClear() {
        let app = launch(arguments: [
            "-resetOnboarding", "-skipOnboarding", "-uiTestPopulated",
            "-uiTestFinishedLiveTrail",
        ])

        XCTAssertTrue(app.descendants(matching: .any)["finished-live-trail"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Live Trail"].exists)
        XCTAssertTrue(app.staticTexts["Finished · stays until cleared"].exists)
        let startNew = app.buttons["start-new-live-trail"]
        let clear = app.buttons["clear-finished-live-trail"]
        XCTAssertTrue(startNew.isHittable)
        XCTAssertTrue(clear.isHittable)
        XCTAssertEqual(startNew.frame.width, clear.frame.width, accuracy: 1)
        XCTAssertEqual(startNew.frame.height, clear.frame.height, accuracy: 1)
        XCTAssertEqual(startNew.frame.minY, clear.frame.minY, accuracy: 1)
        attachScreenshot(named: "10-live-trail-finished", app: app)
    }

    @MainActor
    func testPopulatedMapRendersInDarkAppearance() {
        let previousAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = previousAppearance }

        let app = launch(arguments: [
            "-resetOnboarding", "-skipOnboarding", "-uiTestPopulated",
        ])
        XCTAssertTrue(app.buttons["start-live-trail"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["2 walks mapped"].exists)
        attachScreenshot(named: "11-populated-dark", app: app)
    }

    @MainActor
    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-uiTestResetLiveTrail"]
        app.launch()
        return app
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 6 where !element.isHittable {
            app.swipeUp()
        }
    }
}
