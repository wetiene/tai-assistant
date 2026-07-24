import XCTest

final class StrengthConversationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestStrengthConversation"]
        app.launchEnvironment["UITEST_STRENGTH_CONVERSATION"] = "1"
        app.launchEnvironment["UITEST_AUTO_SUBMIT_STRENGTH_PHOTOS"] = "1"
        app.launchEnvironment["UITEST_STRENGTH_FORCE_LOWER_BODY"] = "1"
        app.launch()
    }

    func testConversationalStrengthCriticalPath() throws {
        let composer = app.textFields["tai.composer.textField"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "Tai composer")
        composer.tap()
        composer.typeText("I've arrived at the gym")

        let send = app.buttons["tai.composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        let overview = app.descendants(matching: .any)["strength.conversation.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 45), "Workout overview card")

        XCTAssertFalse(
            app.buttons["strength.preflight.start"].waitForExistence(timeout: 2),
            "Dedicated pre-flight screen should not open automatically"
        )
        XCTAssertFalse(
            app.buttons["strength.active.confirmSet"].waitForExistence(timeout: 2),
            "Dedicated active workout screen should not open automatically"
        )

        let thinking = app.staticTexts["Tai is thinking…"]
        _ = thinking.waitForNonExistence(timeout: 30)

        let photoReview = app.staticTexts["Photo review"]
        if !photoReview.waitForExistence(timeout: 30) {
            let errorAlert = app.alerts["Tai"]
            if errorAlert.waitForExistence(timeout: 1) {
                XCTFail("Tai error alert: \(errorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
            } else {
                XCTFail("Photo review card not found")
            }
            return
        }

        let apply = app.buttons["strength.conversation.applyPhotoReview"]
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        let applyDeadline = Date().addingTimeInterval(15)
        while Date() < applyDeadline, !apply.isEnabled {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(apply.isEnabled, "Apply should be enabled when mock matches a session exercise")
        apply.tap()

        let workspaceID = "strength.conversation.exerciseWorkspace.legPress"
        let workspace = app.descendants(matching: .any)[workspaceID]
        XCTAssertTrue(workspace.waitForExistence(timeout: 20), "Exercise workspace card")

        let confirmSet = app.buttons["strength.conversation.confirmSet"]
        XCTAssertTrue(confirmSet.waitForExistence(timeout: 10))
        confirmSet.tap()

        XCTAssertTrue(workspace.waitForExistence(timeout: 20), "Workspace remains after confirming set 1")
        XCTAssertTrue(
            app.staticTexts["strength.conversation.confirmedSet.1"].waitForExistence(timeout: 10),
            "Set 1 history visible"
        )

        let weightIncrement = app.buttons["strength.conversation.weight.increment"]
        XCTAssertTrue(weightIncrement.waitForExistence(timeout: 10))
        weightIncrement.tap()

        XCTAssertTrue(confirmSet.waitForExistence(timeout: 10))
        confirmSet.tap()

        XCTAssertTrue(
            app.staticTexts["strength.conversation.confirmedSet.1"].waitForExistence(timeout: 10),
            "Set 1 unchanged after set 2"
        )
        XCTAssertTrue(
            app.staticTexts["strength.conversation.confirmedSet.2"].waitForExistence(timeout: 10),
            "Set 2 confirmed history visible"
        )
    }
}
