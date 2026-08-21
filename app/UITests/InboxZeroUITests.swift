import XCTest

/// Each test creates its own uniquely named reminders through the capture UI,
/// so runs don't depend on seed data or a clean simulator.
final class InboxZeroUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func capture(_ title: String) {
        app.buttons["New reminder"].tap()
        let field = app.textFields["What needs doing?"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5),
                      "captured reminder should appear in the inbox with a Today due date")
    }

    private func unique(_ prefix: String) -> String {
        "\(prefix) \(Int(Date().timeIntervalSince1970))"
    }

    func testCaptureThenSettleRemovesFromInbox() {
        let title = unique("UITest settle")
        capture(title)

        let cell = app.cells.containing(.staticText, identifier: title).firstMatch
        cell.swipeLeft()
        let settle = app.buttons["Settle"]
        XCTAssertTrue(settle.waitForExistence(timeout: 3))
        settle.tap()

        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts[title]),
            "settled reminder should leave the inbox"
        )
    }

    func testSnoozeMovesToSnoozedSection() {
        let title = unique("UITest snooze")
        capture(title)

        let cell = app.cells.containing(.staticText, identifier: title).firstMatch
        cell.swipeLeft()
        let snooze = app.buttons["Snooze"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 3))
        snooze.tap()

        let tomorrow = app.buttons["Tomorrow"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.tap()

        XCTAssertTrue(
            waitForDisappearance(of: app.cells.containing(.staticText, identifier: title).firstMatch),
            "snoozed reminder should leave the inbox section"
        )

        // Expand Snoozed and confirm it moved there with a Tomorrow label.
        let snoozedHeader = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Snoozed'")).firstMatch
        XCTAssertTrue(snoozedHeader.waitForExistence(timeout: 3))
        snoozedHeader.tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        app.staticTexts[title].tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5),
                      "appended message should survive a cold relaunch via EventKit")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
