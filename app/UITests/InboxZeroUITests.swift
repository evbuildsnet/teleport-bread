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
        let compose = app.buttons["New need"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10), "inbox should finish loading")
        compose.tap()
        let field = app.descendants(matching: .any)["needTitleField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.buttons["Create need"].tap()
        XCTAssertTrue(scrollTo(item(title)),
                      "captured reminder should appear in the inbox with a Today due date")
    }

    /// Any element whose label is exactly `title` (rows are buttons, thread
    /// messages are static texts).
    private func item(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
    }

    /// Message bubbles are UITextViews: match by value, not label.
    private func bubble(_ message: String) -> XCUIElement {
        app.textViews.matching(NSPredicate(format: "value == %@", message)).firstMatch
    }

    private func cell(_ title: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
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

    func testPullDownPastThresholdOpensCompose() {
        let compose = app.buttons["New need"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        // Press on the list and drag well past the overscroll threshold, then release.
        let list = app.collectionViews.firstMatch
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)

        let field = app.descendants(matching: .any)["needTitleField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "releasing past the threshold should open compose")
        app.buttons["Discard"].tap()
    }

    func testCaptureThenSettleRemovesFromInbox() {
        let title = unique("UITest settle")
        capture(title)

        swipeAndTap(title, action: "Settle")

        XCTAssertTrue(waitForDisappearance(of: item(title)),
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

        let snoozedHeader = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Snoozed'")
        ).firstMatch
        XCTAssertTrue(scrollTo(snoozedHeader))
        snoozedHeader.tap()
        XCTAssertTrue(scrollTo(item(title)),
                      "snoozed reminder should be listed under Snoozed")

        // Snoozed rows only offer Wake; wake it back to today, then settle.
        swipeAndTap(title, action: "Wake")
        app.swipeDown()
        XCTAssertTrue(scrollTo(item(title)), "woken reminder should be back in the inbox")
        swipeAndTap(title, action: "Settle")
        XCTAssertTrue(waitForDisappearance(of: item(title)))
    }

    func testThreadAppendPersistsAcrossRelaunch() {
        let title = unique("UITest thread")
        let message = "Thought for later \(Int(Date().timeIntervalSince1970))"
        capture(title)

        item(title).tap()
        let field = app.textFields["Message to your future self"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(message)
        app.buttons["Append message"].tap()
        XCTAssertTrue(bubble(message).waitForExistence(timeout: 5),
                      "appended message should render in the thread")

        // The "…" menu exposes the explicit history-edit actions.
        app.buttons["Message actions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3), "menu should offer Edit")
        XCTAssertTrue(app.buttons["Delete"].exists, "menu should offer Delete")
        app.buttons["Copy"].tap()

        // Relaunch: the message must come back from EventKit, not app state.
        app.terminate()
        app.launch()
        XCTAssertTrue(scrollTo(item(title)))
        item(title).tap()
        XCTAssertTrue(bubble(message).waitForExistence(timeout: 5),
                      "appended message should survive a cold relaunch via EventKit")

        // Cleanup: back to the list, settle via the swipe gesture (the only way).
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(scrollTo(item(title)))
        swipeAndTap(title, action: "Settle")
        XCTAssertTrue(waitForDisappearance(of: item(title)))
    }
}
