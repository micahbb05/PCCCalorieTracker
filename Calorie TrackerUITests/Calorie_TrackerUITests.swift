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
    @MainActor
    func testStressRapidTabSwitching() throws {
        let app = XCUIApplication()
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 5) {
            let count = tabBar.buttons.count
            if count > 0 {
                for _ in 0..<30 {
                    let randomIdx = Int.random(in: 0..<count)
                    tabBar.buttons.element(boundBy: randomIdx).tap()
                }
            }
        }
    }
    
    @MainActor
    func testStressExcessiveTextEntry() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_PCC_MENU", "YES"]
        app.launch()
        
        let searchField = app.textFields["Search menu"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        
        searchField.tap()
        // Type a very long string that might cause UI to lag or layout to break
        let longString = String(repeating: "Chicken ", count: 50)
        searchField.typeText(longString)
        
        XCTAssertTrue(searchField.exists)
        
        // Clear it by hitting delete multiple times
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 400)
        searchField.typeText(deleteString)
    }

    @MainActor
    func testStressMonkey2000Interactions() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_PCC_MENU", "YES"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))
        let searchField = app.textFields["Search menu"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))

        var actions = 0
        var successes = 0
        let actionTarget = 2000

        for i in 0..<actionTarget {
            actions += 1
            if i % 5 == 0 {
                let count = tabBar.buttons.count
                if count > 0 {
                    let idx = Int.random(in: 0..<count)
                    let button = tabBar.buttons.element(boundBy: idx)
                    if button.exists && button.isHittable {
                        button.tap()
                        successes += 1
                    }
                }
                continue
            }

            if searchField.exists && searchField.isHittable {
                searchField.tap()
                if i % 2 == 0 {
                    searchField.typeText("a")
                } else {
                    searchField.typeText(XCUIKeyboardKey.delete.rawValue)
                }
                successes += 1
            } else {
                app.swipeUp()
            }
        }

        let successRate = actions > 0 ? Double(successes) / Double(actions) : 0
        print("STRESS_METRIC actions=\(actions)")
        print("STRESS_METRIC successes=\(successes)")
        print("STRESS_METRIC action_success_rate=\(String(format: "%.5f", successRate))")
        XCTAssertGreaterThanOrEqual(successRate, 0.99)
    }

    @MainActor
    func testE2EHappyPathPCCMenuSearchFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_PCC_MENU", "YES"]
        app.launch()

        let searchField = app.textFields["Search menu"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("Chicken")

        let results = app.otherElements["pccMenu.searchResults"]
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Grilled Chicken Bowl"].waitForExistence(timeout: 3))

        let clearButton = app.descendants(matching: .any)["pccMenu.clearSearchButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
        XCTAssertTrue(clearButton.isHittable)
        clearButton.tap()
        XCTAssertEqual((searchField.value as? String) ?? "", "")

        print("STRESS_METRIC e2e_happy_path=1")
    }
}
