import XCTest

/// Each test creates its own uniquely named reminder through the capture UI
/// and settles it at the end, so runs don't depend on seed data or a clean
/// simulator and don't accumulate rows.
final class InboxZeroUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: Helpers

    private func unique(_ prefix: String) -> String {
        "\(prefix) \(Int(Date().timeIntervalSince1970))"
    }

    /// List rows are lazy: an off-screen row doesn't exist in the hierarchy.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) -> Bool {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.waitForExistence(timeout: 2)
    }

    private func capture(_ title: String) {
        let compose = app.buttons["New reminder"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10), "inbox should finish loading")
        compose.tap()
        let field = app.textFields["What needs doing?"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.buttons["Add"].tap()
        XCTAssertTrue(scrollTo(app.staticTexts[title]),
                      "captured reminder should appear in the inbox with a Today due date")
    }

    private func cell(_ title: String) -> XCUIElement {
        app.cells.containing(.staticText, identifier: title).firstMatch
    }

    private func swipeAndTap(_ title: String, action: String) {
        cell(title).swipeLeft()
        let button = app.buttons[action]
        XCTAssertTrue(button.waitForExistence(timeout: 3), "\(action) swipe button should appear")
        button.tap()
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: Tests

    func testCaptureThenSettleRemovesFromInbox() {
        let title = unique("UITest settle")
        capture(title)

        swipeAndTap(title, action: "Settle")

        XCTAssertTrue(waitForDisappearance(of: app.staticTexts[title]),
                      "settled reminder should leave the inbox")
    }

    func testSnoozeMovesToSnoozedSection() {
        let title = unique("UITest snooze")
        capture(title)

        swipeAndTap(title, action: "Snooze")
        let tomorrow = app.buttons["Tomorrow"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.tap()

        XCTAssertTrue(waitForDisappearance(of: cell(title)),
                      "snoozed reminder should leave the inbox section")

        let snoozedHeader = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Snoozed'")
        ).firstMatch
        XCTAssertTrue(scrollTo(snoozedHeader))
        snoozedHeader.tap()
        XCTAssertTrue(scrollTo(app.staticTexts[title]),
                      "snoozed reminder should be listed under Snoozed")

        // Cleanup: settle it from the Snoozed section.
        swipeAndTap(title, action: "Settle")
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts[title]))
    }

    func testThreadAppendPersistsAcrossRelaunch() {
        let title = unique("UITest thread")
        let message = "Thought for later \(Int(Date().timeIntervalSince1970))"
        capture(title)

        app.staticTexts[title].tap()
        let field = app.textFields["Message to your future self"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(message)
        app.buttons["Append message"].tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5),
                      "appended message should render in the thread")

        // Relaunch: the message must come back from EventKit, not app state.
        app.terminate()
        app.launch()
        XCTAssertTrue(scrollTo(app.staticTexts[title]))
        app.staticTexts[title].tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5),
                      "appended message should survive a cold relaunch via EventKit")

        // Cleanup: settle from the thread toolbar.
        app.buttons["Settle"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts[title]))
    }
}
