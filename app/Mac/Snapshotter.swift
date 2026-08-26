import AppKit
import SwiftUI

/// Headless review aid: `INBOXZERO_PREVIEW=1 INBOXZERO_SNAPSHOT_DIR=/path`
/// runs the window on in-memory preview data, renders a set of states to
/// PNG (no screen or Reminders access needed) and quits.
@MainActor
enum Snapshotter {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["INBOXZERO_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(model: AppModel, ui: UIState) async {
        guard let directory else { return }
        FileHandle.standardError.write(Data("snapshotter: start → \(directory.path)\n".utf8))
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(1))
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
            FileHandle.standardError.write(Data("snapshotter: no window (\(NSApp.windows.count))\n".utf8))
            return
        }

        func shoot(_ name: String) async {
            try? await Task.sleep(for: .milliseconds(400))
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
            do {
                try data.write(to: directory.appendingPathComponent("\(name).png"))
                FileHandle.standardError.write(Data("snapshotter: wrote \(name)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("snapshotter: write failed \(error)\n".utf8))
            }
        }

        window.appearance = NSAppearance(named: .darkAqua)
        ui.selection = model.inbox.first.map { .need($0.id) }
        await shoot("01-thread-dark")
        ui.snoozedExpanded = true
        await shoot("02-shelves-open")
        ui.paletteOpen = true
        await shoot("03-palette")
        ui.paletteQuery = "passport"
        await shoot("03b-palette-query")
        ui.paletteQuery = ""
        ui.paletteHighlighted = 1
        await shoot("03c-palette-highlight")
        ui.paletteOpen = false
        ui.newDraft(model: model)
        await shoot("04-draft-hero")
        ui.open(.need(model.settled.first!.id), model: model)
        await shoot("05-settled-banner")
        ui.open(.need(model.snoozed.first!.id), model: model)
        await shoot("06-snoozed-banner")
        ui.sidebarVisible = false
        await shoot("07-sidebar-hidden")
        ui.sidebarVisible = true
        ui.commandHeld = true
        await shoot("08-jump-badges")
        ui.commandHeld = false
        window.appearance = NSAppearance(named: .aqua)
        ui.selection = model.inbox.first.map { .need($0.id) }
        await shoot("09-thread-light")
        NSApp.terminate(nil)
    }
}
