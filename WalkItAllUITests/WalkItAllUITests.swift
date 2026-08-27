import XCTest

final class WalkItAllUITests: XCTestCase {
    @MainActor
    func testMapFirstLaunchSurface() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        app.launch()

        let completionArea = app.descendants(matching: .any)["current-completion-area"]
        XCTAssertTrue(completionArea.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Refresh from Apple Health"].exists)
        XCTAssertTrue(app.staticTexts["of Manhattan walked"].exists)
    }
}
