import XCTest

final class StrengthWorkoutSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestStrengthSmoke"]
        app.launch()
    }

    func testStrengthWorkoutCriticalPath() throws {
        let startButton = app.buttons["strength.home.start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 30), "Home strength start button")
        startButton.tap()

        let preflightStart = app.buttons["strength.preflight.start"]
        XCTAssertTrue(preflightStart.waitForExistence(timeout: 15), "Pre-flight start")
        preflightStart.tap()

        let confirmSet = app.buttons["strength.active.confirmSet"]
        XCTAssertTrue(confirmSet.waitForExistence(timeout: 15), "Active workout confirm set")
        confirmSet.tap()

        let finish = app.buttons["strength.active.completeWorkout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 15), "Complete workout")
        finish.tap()

        let completeWithSkipped = app.buttons["strength.active.completeWithSkipped"]
        if completeWithSkipped.waitForExistence(timeout: 5) {
            completeWithSkipped.tap()
        }

        XCTAssertTrue(
            app.buttons["strength.debrief.done"].waitForExistence(timeout: 15)
                || app.descendants(matching: .any)["strength.debrief.root"].waitForExistence(timeout: 1),
            "Coach debrief"
        )
    }
}
