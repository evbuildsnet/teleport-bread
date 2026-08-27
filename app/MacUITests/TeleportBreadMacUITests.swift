import XCTest

/// Each test creates its own uniquely named need through the UI and settles
/// it at the end, so runs don't depend on seed data and don't accumulate.
final class TeleportBreadMacUITests: XCTestCase {
    var app: XCUIApplication!
    /// Needs created by the running test; tearDown settles whatever a failed
    /// test left active so no stray reminders accumulate.
    private var created: [String] = []

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["New need"].waitForExistence(timeout: 15), "window should reach the ready state")
    }

    override func tearDown() {
        for title in created {
            openViaPalette(title)
            if app.staticTexts["This need is settled."].waitForExistence(timeout: 2) { continue }
            if app.buttons["Wake now"].exists { app.buttons["Wake now"].click() }
            contextAction("Settle need", on: title)
        }
        created = []
    }

    private func unique(_ prefix: String) -> String { "\(prefix) \(Int(Date().timeIntervalSince1970))" }

    private func row(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func capture(_ title: String) {
        created.append(title)
        app.typeKey("n", modifierFlags: .command)
        let composer = app.textViews["Composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.click()
        composer.typeText(title)
        composer.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(row(title).waitForExistence(timeout: 5), "captured need should appear in the sidebar")
    }

    /// ⌘K, type, ⏎ — runs the first result.
    private func palette(_ text: String) {
        app.typeKey("k", modifierFlags: .command)
        let search = app.textFields["Palette search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText(text)
        search.typeKey(.return, modifierFlags: [])
    }

    /// Opens a need by searching its title — independent of shelf state.
    private func openViaPalette(_ title: String) {
        palette(title)
        let opened = app.descendants(matching: .any).matching(identifier: "threadTitle")
            .matching(NSPredicate(format: "value == %@", title)).firstMatch
        XCTAssertTrue(opened.waitForExistence(timeout: 5), "need should open in the thread pane")
    }

    /// Right-click the row and pick a menu item (the palette is search-only).
    private func contextAction(_ item: String, on title: String) {
        row(title).rightClick()
        let menuItem = app.menuItems[item].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 3), "context menu should show \(item)")
        menuItem.click()
    }

    private func bubble(_ note: String) -> XCUIElement { app.staticTexts[note].firstMatch }

    func testCaptureAndSettle() {
        let title = unique("Mac capture")
        capture(title)
        contextAction("Settle need", on: title)
        openViaPalette(title)
        XCTAssertTrue(app.staticTexts["This need is settled."].waitForExistence(timeout: 5))
    }

    func testSnoozeWakeThenSettle() {
        let title = unique("Mac snooze")
        capture(title)
        row(title).rightClick()
        let snoozeMenu = app.menuItems["Snooze"].firstMatch
        XCTAssertTrue(snoozeMenu.waitForExistence(timeout: 3))
        snoozeMenu.click()
        let tomorrow = app.menuItems["Tomorrow"].firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.click()
        // Need is now snoozed; open it through search and wake from the banner.
        sleep(1)
        openViaPalette(title)
        let wake = app.buttons["Wake now"].firstMatch
        XCTAssertTrue(wake.waitForExistence(timeout: 5))
        wake.click()
        XCTAssertFalse(app.buttons["Wake now"].waitForExistence(timeout: 3))
        contextAction("Settle need", on: title)
        // Settling the open need advances the pane to the next inbox need;
        // re-open the settled one to see its banner.
        openViaPalette(title)
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
        XCTAssertTrue(bubble(note).waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(row(title).waitForExistence(timeout: 15))
        row(title).click()
        XCTAssertTrue(bubble(note).waitForExistence(timeout: 5), "note should survive a cold relaunch")
        contextAction("Settle need", on: title)
    }
}
