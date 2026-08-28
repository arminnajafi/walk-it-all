import XCTest

final class WalkItAllUITests: XCTestCase {
    @MainActor
    func testMapFirstLaunchSurface() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetOnboarding", "-skipOnboarding"]
        app.launch()

        let completionArea = app.descendants(matching: .any)["current-completion-area"]
        XCTAssertTrue(completionArea.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Refresh from Apple Health"].exists)
        XCTAssertTrue(app.staticTexts["of Manhattan walked"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["osm-attribution"].exists)
        attachScreenshot(named: "01-main-map", app: app)
    }

    @MainActor
    func testTwoStepOnboardingExplainsValueAndPrivacy() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["See what you’ve covered."].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].exists)
        attachScreenshot(named: "02-onboarding-value", app: app)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Your history stays yours."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Step 2 of 2"].exists)
        XCTAssertTrue(app.buttons["Connect Apple Health"].exists)
        attachScreenshot(named: "03-onboarding-health", app: app)
    }

    @MainActor
    func testExploreFirstCanReachHealthRefreshAndEmptyExplanation() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetOnboarding"]
        app.launch()

        XCTAssertTrue(app.buttons["Explore first"].waitForExistence(timeout: 30))
        app.buttons["Explore first"].tap()

        XCTAssertTrue(app.buttons["Refresh from Apple Health"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No mappable walking routes yet"].exists)
        attachScreenshot(named: "04-empty-map", app: app)
    }

    @MainActor
    func testAccessibilityXXXLOnboardingKeepsEveryActionReachable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-resetOnboarding",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let explanation = app.staticTexts[
            "Turn the walks already in Apple Health into a lifetime map of Manhattan—then walk what remains."
        ]
        XCTAssertTrue(explanation.waitForExistence(timeout: 30))
        let continueButton = app.buttons["Continue"]
        scrollUntilHittable(continueButton, in: app)
        XCTAssertTrue(continueButton.isHittable)
        continueButton.tap()

        XCTAssertTrue(app.staticTexts["Your history stays yours."].waitForExistence(timeout: 5))
        let connectButton = app.buttons["Connect Apple Health"]
        scrollUntilHittable(connectButton, in: app)
        XCTAssertTrue(connectButton.isHittable)
        attachScreenshot(named: "10-onboarding-accessibility-xxxl", app: app)
    }

    @MainActor
    func testCoverageDetailsExplainHistoryMethodologyAndPrivacy() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetOnboarding", "-skipOnboarding"]
        app.launch()

        let about = app.buttons["About Walk It All"]
        XCTAssertTrue(about.waitForExistence(timeout: 30))
        about.tap()
        XCTAssertTrue(app.navigationBars["Coverage"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        attachScreenshot(named: "05-coverage-details", app: app)

        let privacy = app.buttons["Privacy and data"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy and Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No route uploads"].exists)
        attachScreenshot(named: "06-privacy", app: app)
        app.navigationBars["Privacy and Data"].buttons["Coverage"].tap()

        let methodology = app.buttons["How coverage works"]
        XCTAssertTrue(methodology.waitForExistence(timeout: 5))
        methodology.tap()
        XCTAssertTrue(app.navigationBars["How Coverage Works"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["How a walk is matched"].exists)
        attachScreenshot(named: "07-methodology", app: app)
        let licenseLink = app.descendants(matching: .any)["Open Database License"]
        scrollUntilHittable(licenseLink, in: app)
        XCTAssertTrue(licenseLink.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["OpenStreetMap attribution"].exists)
        attachScreenshot(named: "07b-methodology-attribution", app: app)
        app.navigationBars["How Coverage Works"].buttons["Coverage"].tap()

        let healthAccess = app.buttons["Review Health access"]
        XCTAssertTrue(healthAccess.waitForExistence(timeout: 5))
        healthAccess.tap()
        XCTAssertTrue(app.navigationBars["Health Access"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Request Apple Health Access"].exists)
        attachScreenshot(named: "08-health-access", app: app)
        let finalAccessStep = app.staticTexts["Turn on all available read permissions."]
        scrollUntilHittable(finalAccessStep, in: app)
        XCTAssertTrue(finalAccessStep.isHittable)
        attachScreenshot(named: "08b-health-access-instructions", app: app)
        app.navigationBars["Health Access"].buttons["Coverage"].tap()

        let history = app.buttons["Workout history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.tap()
        XCTAssertTrue(app.staticTexts["No workout routes"].waitForExistence(timeout: 5))
        attachScreenshot(named: "09-workout-history-empty", app: app)
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
        for _ in 0 ..< 4 where !element.isHittable {
            app.swipeUp()
        }
    }
}
