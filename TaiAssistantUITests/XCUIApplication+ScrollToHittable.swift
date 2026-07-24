import XCTest

extension XCUIApplication {
    /// Scrolls the primary Home scroll surface until `element` exists and reports hittable.
    @discardableResult
    func scrollToMakeHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 20
    ) -> Bool {
        let scrollSurface = scrollViews.firstMatch
        if scrollSurface.exists {
            scrollSurface.swipeDown(velocity: .fast)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var upwardSwipes = 0
        while Date() < deadline {
            if element.exists, element.isHittable {
                return true
            }
            if scrollSurface.exists {
                if upwardSwipes < 8 {
                    scrollSurface.swipeUp()
                    upwardSwipes += 1
                } else {
                    scrollSurface.swipeDown()
                }
            } else {
                swipeUp()
            }
        }
        return element.exists && element.isHittable
    }

    func tapElement(_ element: XCUIElement) {
        if element.exists, element.isHittable {
            element.tap()
            return
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coordinate.tap()
    }
}
