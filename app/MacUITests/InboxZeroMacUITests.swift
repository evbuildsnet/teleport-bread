import XCTest

/// Each test creates its own uniquely named need through the UI and settles
/// it at the end, so runs don't depend on seed data and don't accumulate.
final class InboxZeroMacUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["New need"].waitForExistence(timeout: 15), "window should reach the ready state")
    }

    private func unique(_ prefix: String) -> String { "\(prefix) \(Int(Date().timeIntervalSince1970))" }

    private func row(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func capture(_ title: String) {
        app.typeKey("n", modifierFlags: .command)
        let composer = app.textViews["Composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.click()
        composer.typeText(title)
        composer.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(row(title).waitForExistence(timeout: 5), "captured need should appear in the sidebar")
    }

    private func settleViaPalette(_ title: String) {
        row(title).click()
        app.typeKey("k", modifierFlags: .command)
        let search = app.textFields["Palette search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText(">settle")
        search.typeKey(.return, modifierFlags: [])
    }

    func testCaptureAndSettleViaPalette() {
        let title = unique("Mac capture")
        capture(title)
        settleViaPalette(title)
        // Settled shelf is expanded by default; the row is still there, as settled.
        XCTAssertTrue(row(title).waitForExistence(timeout: 5))
        row(title).click()
        XCTAssertTrue(app.staticTexts["This need is settled."].waitForExistence(timeout: 5))
    }

    func testSnoozeWakeThenSettle() {
        let title = unique("Mac snooze")
        capture(title)
        row(title).rightClick()
        app.menuItems["Snooze"].firstMatch.hover()
        let tomorrow = app.menuItems["Tomorrow"].firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.click()
        // Need is now in the Snoozed shelf; open it and wake from the banner.
        let header = app.buttons["Snoozed section"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        if !row(title).exists { header.click() }
        XCTAssertTrue(row(title).waitForExistence(timeout: 5))
        row(title).click()
        let wake = app.buttons["Wake now"].firstMatch
        XCTAssertTrue(wake.waitForExistence(timeout: 5))
        wake.click()
        XCTAssertFalse(app.buttons["Wake now"].waitForExistence(timeout: 3))
        settleViaPalette(title)
        XCTAssertTrue(app.staticTexts["This need is settled."].waitForExistence(timeout: 5))
    }

    func testThreadAppendPersistsAcrossRelaunch() {
        let title = unique("Mac thread")
        capture(title)
        let note = unique("note")
        let composer = app.textViews["Composer"].firstMatch
        composer.click()
        composer.typeText(note)
        composer.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value == %@", note)).firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(row(title).waitForExistence(timeout: 15))
        row(title).click()
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value == %@", note)).firstMatch.waitForExistence(timeout: 5),
                      "note should survive a cold relaunch")
        settleViaPalette(title)
    }
}
