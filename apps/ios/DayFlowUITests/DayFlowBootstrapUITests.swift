import XCTest

final class DayFlowBootstrapUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 60
    }

    func testSeededOwnerLoginLoadsAuthenticatedBudgetShell() {
        let app = XCUIApplication()
        let environment = ProcessInfo.processInfo.environment
        app.launchEnvironment["DAYFLOW_API_BASE_URL"] = environment["DAYFLOW_API_BASE_URL"] ?? "http://127.0.0.1:18080/v1"
        app.launch()

        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 15), "Expected the login form to load")
        email.tap()
        email.typeText(environment["DAYFLOW_IOS_TEST_OWNER_EMAIL"] ?? "owner@dayflow.local")

        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText(environment["DAYFLOW_IOS_TEST_OWNER_PASSWORD"] ?? "secret1234")
        app.buttons["login.submit"].tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "Expected an authenticated DayFlow shell after seeded owner login")
        app.tabBars.buttons["Budget"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["budget.board.loaded"].waitForExistence(timeout: 20), "Expected the seeded budget board from the real API")
        XCTAssertTrue(app.staticTexts["Housing"].waitForExistence(timeout: 20), "Expected the persisted Housing seed from the real API")
    }
}
