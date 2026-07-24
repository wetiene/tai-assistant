import XCTest

final class ImageDomainClassificationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testMealImageThroughGymPhotoShowsMealEstimateOnly() throws {
        launch(scenario: "mealViaGymPhoto")
        startWorkoutAndSubmitPhoto()

        XCTAssertFalse(
            app.descendants(matching: .any)["strength.conversation.photoReview"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["strength.conversation.exerciseWorkspace.legPress"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            waitForMealEstimateCard(timeout: 120),
            "Expected meal estimate after gym-to-meal reroute"
        )
        XCTAssertFalse(app.buttons["Log meal"].exists)
    }

    func testGymImageThroughMealPhotoShowsPhotoReviewOnly() throws {
        launch(scenario: "gymViaMealPhoto")
        startWorkoutAndSubmitPhoto()

        XCTAssertFalse(
            app.descendants(matching: .any)["meal.estimate.card"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["strength.conversation.photoReview"].waitForExistence(timeout: 30)
        )
    }

    func testUserCorrectionSupersedesWrongGymArtifact() throws {
        launch(scenario: "wrongGymArtifact", autoSubmitCorrection: true)
        startWorkoutAndSubmitPhoto()

        XCTAssertTrue(
            waitForMealEstimateCard(timeout: 120),
            "Expected corrected meal estimate to replace the wrong gym review"
        )
        let apply = app.buttons["strength.conversation.applyPhotoReview"]
        if apply.waitForExistence(timeout: 2) {
            XCTAssertFalse(apply.isEnabled)
        }
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "meal.estimate.card").allElementsBoundByIndex.filter(\.isHittable).count,
            1
        )
    }

    func testPartialGymWeightShowsNotDetectedAndAllowsApply() throws {
        launch(scenario: "partialGymWeight")
        startWorkoutAndSubmitPhoto()

        XCTAssertTrue(
            app.descendants(matching: .any)["strength.conversation.photoReview"].waitForExistence(timeout: 30)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["strength.conversation.photoReview.weightNotDetected"]
                .waitForExistence(timeout: 10)
        )

        let apply = app.buttons["strength.conversation.applyPhotoReview"]
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        XCTAssertTrue(apply.isEnabled)
        apply.tap()

        let workspace = app.descendants(matching: .any)["strength.conversation.exerciseWorkspace.legPress"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.descendants(matching: .any)["strength.conversation.weight.needsEntry"]
                .waitForExistence(timeout: 10)
        )
        let confirmSet = app.buttons["strength.conversation.confirmSet"]
        if confirmSet.waitForExistence(timeout: 2) {
            XCTAssertFalse(confirmSet.isEnabled)
        }
    }

    func testAmbiguousImageShowsClarificationWithoutArtifacts() throws {
        launch(scenario: "ambiguousImage")
        startWorkoutAndSubmitPhoto()

        XCTAssertFalse(
            app.descendants(matching: .any)["meal.estimate.card"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["strength.conversation.photoReview"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'meal' OR label CONTAINS[c] 'gym'")
            ).firstMatch.waitForExistence(timeout: 60)
            || app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'meal' OR label CONTAINS[c] 'gym' OR label CONTAINS[c] 'photo'")
            ).firstMatch.waitForExistence(timeout: 60)
        )
    }

    // MARK: - Helpers

    private func launch(scenario: String, autoSubmitCorrection: Bool = false) {
        app.launchArguments = ["-UITestImageDomain"]
        var environment = [
            "UITEST_IMAGE_DOMAIN": "1",
            "UITEST_IMAGE_DOMAIN_SCENARIO": scenario,
            "UITEST_AUTO_SUBMIT_IMAGE_DOMAIN_PHOTO": "1",
            "UITEST_STRENGTH_FORCE_LOWER_BODY": "1",
        ]
        if autoSubmitCorrection {
            environment["UITEST_AUTO_SUBMIT_IMAGE_DOMAIN_CORRECTION"] = "1"
        }
        app.launchEnvironment = environment
        app.launch()
        _ = app.textFields["tai.composer.textField"].waitForExistence(timeout: 30)
    }

    private func startWorkoutAndSubmitPhoto() {
        let composer = app.textFields["tai.composer.textField"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("I've arrived at the gym")
        app.buttons["tai.composer.send"].tap()

        let overview = app.descendants(matching: .any)["strength.conversation.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 120))
        pause(seconds: 2)
    }

    private func pause(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func waitForMealEstimateCard(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.staticTexts["Garden salad bowl"].waitForExistence(timeout: 1) { return true }
            if app.staticTexts["Detected meal"].waitForExistence(timeout: 1) { return true }
            if app.descendants(matching: .any)["meal.estimate.card"].waitForExistence(timeout: 1) { return true }
        }
        return false
    }
}
