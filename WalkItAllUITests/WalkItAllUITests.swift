import XCTest

final class WalkItAllUITests: XCTestCase {
    func testMapFirstLaunchSurface() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Manhattan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Refresh from Apple Health"].exists)
        XCTAssertTrue(app.staticTexts["of Manhattan walked"].exists)
    }
}

