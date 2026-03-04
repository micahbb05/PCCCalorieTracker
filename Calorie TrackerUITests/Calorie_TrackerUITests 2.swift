import XCTest

final class Calorie_TrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPCCMenuSearchAndScrollStayAnchored() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_PCC_MENU", "YES"]
        app.launch()

        let searchField = app.textFields["Search menu"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))

        let scrollView = app.scrollViews["pccMenu.scrollView"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))

        let entreesLabel = app.staticTexts["Entrees"]
        XCTAssertTrue(entreesLabel.waitForExistence(timeout: 5))

        let initialSearchY = searchField.frame.minY

        searchField.tap()
        XCTAssertLessThan(abs(searchField.frame.minY - initialSearchY), 2.0)

        searchField.typeText("Chicken")
        XCTAssertTrue(app.staticTexts["Grilled Chicken Bowl"].waitForExistence(timeout: 2))
        XCTAssertLessThan(abs(searchField.frame.minY - initialSearchY), 2.0)

        app.terminate()
        app.launch()

        let relaunchedSearchField = app.textFields["Search menu"].firstMatch
        XCTAssertTrue(relaunchedSearchField.waitForExistence(timeout: 8))

        let relaunchedScrollView = app.scrollViews["pccMenu.scrollView"]
        XCTAssertTrue(relaunchedScrollView.waitForExistence(timeout: 5))

        let relaunchedEntreesLabel = app.staticTexts["Entrees"]
        XCTAssertTrue(relaunchedEntreesLabel.waitForExistence(timeout: 5))

        let anchoredSearchY = relaunchedSearchField.frame.minY

        relaunchedEntreesLabel.tap()
        XCTAssertTrue(app.staticTexts["Grilled Chicken Bowl"].waitForExistence(timeout: 2))

        relaunchedScrollView.swipeUp()
        relaunchedScrollView.swipeUp()
        relaunchedScrollView.swipeUp()
        XCTAssertLessThan(relaunchedSearchField.frame.minY, anchoredSearchY - 40.0)

        relaunchedScrollView.swipeDown()
        relaunchedScrollView.swipeDown()

        var recoverySwipeCount = 0
        while relaunchedSearchField.frame.minY < anchoredSearchY - 5.0 && recoverySwipeCount < 5 {
            relaunchedScrollView.swipeDown()
            recoverySwipeCount += 1
        }

        XCTAssertLessThan(abs(relaunchedSearchField.frame.minY - anchoredSearchY), 8.0)

        relaunchedScrollView.swipeDown()
        XCTAssertLessThan(abs(relaunchedSearchField.frame.minY - anchoredSearchY), 8.0)
        XCTAssertTrue(app.staticTexts["Entrees"].exists)
    }

    @MainActor
    func testPCCMenuLastCategoryClearsBottomBar() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_PCC_MENU", "YES"]
        app.launch()

        let scrollView = app.scrollViews["pccMenu.scrollView"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 8))

        let bottomTabBarTopEdge = app.otherElements["app.bottomTabBar.topEdge"]
        XCTAssertTrue(bottomTabBarTopEdge.waitForExistence(timeout: 5))

        let dessertsLabel = app.staticTexts["Desserts"]
        var swipeCount = 0
        while (!dessertsLabel.isHittable || dessertsLabel.frame.maxY > bottomTabBarTopEdge.frame.minY - 8) && swipeCount < 12 {
            scrollView.swipeUp()
            swipeCount += 1
        }

        XCTAssertTrue(dessertsLabel.waitForExistence(timeout: 2))
        XCTAssertTrue(dessertsLabel.isHittable)
        XCTAssertLessThan(dessertsLabel.frame.maxY, bottomTabBarTopEdge.frame.minY - 8)

        dessertsLabel.tap()
        let dessertsItem = app.staticTexts["Desserts Item 1"]
        XCTAssertTrue(dessertsItem.waitForExistence(timeout: 2))
        XCTAssertTrue(dessertsItem.isHittable)
        XCTAssertLessThan(dessertsItem.frame.maxY, bottomTabBarTopEdge.frame.minY - 8)
    }
}
