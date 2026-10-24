import AppKit
import DesktopCore
import SwiftUI

/// Tests the real controller against an undisplayed AppKit window. Does not
/// send keyboard/mouse events, inspect other apps or simulate OS sleep/lock.
@main @MainActor
struct WindowContractChecks {
    static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let controller = DesktopController(directory: directory)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        defer { window.delegate = nil; window.close() }
        func diagnostics(_ label: String) {
            let line = "\(label): key=\(window.canBecomeKey), main=\(window.canBecomeMain), visible=\(window.isVisible), mask=\(window.styleMask.rawValue), policy=\(NSApp.activationPolicy().rawValue)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
        diagnostics("before attach")
        let baselineMainEligibility = window.canBecomeMain
        controller.attach(window)
        diagnostics("after attach")
        precondition(!window.isVisible, "Contract tests must not show a native window")
        precondition(window.canBecomeKey && window.canBecomeMain == baselineMainEligibility,
                     "Hidden title bar must retain key eligibility and not change main-window eligibility")
        precondition(window.titleVisibility == .hidden && window.titlebarAppearsTransparent,
                     "Device title bar must be hidden/transparent")
        precondition(window.styleMask.contains(.fullSizeContentView), "Content must fill title-bar area")
        precondition(!window.isOpaque && window.backgroundColor?.alphaComponent == 0 && !window.hasShadow,
                     "Opaque background or OS shadow would expose a rectangular shell")
        precondition(window.isMovable && !window.isMovableByWindowBackground, "Explicit drag regions must be the only drag owner")
        let drag = WindowDragRegion.DragView(region: .device)
        drag.frame = CGRect(x: 0, y: 0, width: 288, height: 360)
        precondition(drag.acceptsDrag(at: NSPoint(x: 144, y: 40)) && drag.acceptsDrag(at: NSPoint(x: 144, y: 170)),
                     "Shell header and LCD must route to native dragging")
        precondition(!drag.acceptsDrag(at: NSPoint(x: 144, y: 310)) && !drag.acceptsDrag(at: .zero),
                     "Drag region must exclude action keys and transparent shell corners")
        drag.frame = CGRect(x: 0, y: 0, width: 172.8, height: 216)
        precondition(drag.acceptsDrag(at: NSPoint(x: 86.4, y: 102)), "Scaled LCD retains native drag surface")
        precondition(!drag.acceptsDrag(at: NSPoint(x: 86.4, y: 186)) && !drag.acceptsDrag(at: .zero),
                     "Scaled keys and transparent corners must not be intercepted by dragging")
        drag.frame = CGRect(x: 0, y: 0, width: 230.4, height: 288)
        precondition(drag.acceptsDrag(at: NSPoint(x: 115.2, y: 136)), "80% LCD retains native dragging")
        precondition(!drag.acceptsDrag(at: NSPoint(x: 115.2, y: 248)) && !drag.acceptsDrag(at: .zero),
                     "80% keys and transparent corners remain excluded")
        drag.region = .pet
        drag.frame = CGRect(x: 0, y: 0, width: 128, height: 128)
        precondition(drag.acceptsDrag(at: NSPoint(x: 64, y: 64)), "Pet-only mode must have an explicit drag surface")
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            precondition(window.standardWindowButton(button)?.isHidden == true, "Native traffic lights must be hidden")
        }
        controller.setOnTop(true)
        precondition(window.level == .floating, "On-top setting must select floating level")
        let topRestored = DesktopController(directory: directory)
        precondition(topRestored.alwaysOnTop, "Reopen must retain enabled on-top setting")
        controller.setOnTop(false)
        precondition(window.level == .normal, "Turning off on-top must restore normal level")
        controller.toggleCompact()
        controller.setShellColor(ShellColor(red: 0.93, green: 0.37, blue: 0.6))
        let saved = try JSONDecoder().decode(DesktopPreferences.self,
            from: Data(contentsOf: directory.appendingPathComponent("desktop.json")))
        precondition(saved.compact && !saved.alwaysOnTop && saved.frame != nil,
                     "Controller must persist mode, level and placement independently of pet")
        let restored = DesktopController(directory: directory)
        precondition(restored.compact && !restored.alwaysOnTop && restored.shellColor == controller.shellColor, "Reopen restores desktop preferences")
        controller.setShellColor(.default)
        let defaultRestored = DesktopController(directory: directory)
        precondition(defaultRestored.shellColor == .default && defaultRestored.compact && !defaultRestored.alwaysOnTop,
                     "Reset color must persist without changing mode or on-top setting")
        let moved = NSPoint(x: window.frame.minX - 40, y: window.frame.minY - 40)
        window.setFrameOrigin(moved)
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: window))
        controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(window.frame.origin == moved, "Layout refresh must not reset a user's moved position")
        let preferenceFile = directory.appendingPathComponent("desktop.json")
        let before = try Data(contentsOf: preferenceFile)
        let modified = try preferenceFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let afterLayout = try preferenceFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        precondition(afterLayout == modified, "Unchanged layout must not repeatedly rewrite desktop preferences")
        let secondary = DesktopController(directory: directory, ownsSession: false)
        secondary.toggleCompact(); secondary.setShellColor(.default); secondary.setOnTop(true); secondary.attach(window)
        let afterSecondary = try Data(contentsOf: directory.appendingPathComponent("desktop.json"))
        precondition(afterSecondary == before,
                     "Secondary controller cannot persist or attach")
        precondition(window.delegate === controller, "Secondary must not steal primary window delegate")
        precondition(!controller.windowShouldClose(window) && !controller.animationVisible,
                     "Close routes to hidden state rather than destroying the window")
        precondition(window.delegate === controller, "Hide must retain the same reusable window")
        let walkingFolder = directory.appendingPathComponent("walk")
        let walker = DesktopController(directory: walkingFolder, automaticallyRoams: false)
        let visibleScreen = NSScreen.main!.visibleFrame
        let origin = CGPoint(x: visibleScreen.midX, y: visibleScreen.midY)
        let roamingWindow = NSWindow(contentRect: CGRect(origin: origin, size: CGSize(width: 128, height: 128)),
            styleMask: [.borderless], backing: .buffered, defer: false)
        roamingWindow.isReleasedWhenClosed = false
        walker.attach(roamingWindow)
        let start = roamingWindow.frame
        let now = Date(), deadline = now.addingTimeInterval(5)
        let prefsURL = walkingFolder.appendingPathComponent("desktop.json")
        let beforeWalking = try Data(contentsOf: prefsURL)
        walker.setRoaming(active: true, deadline: deadline, reduced: false)
        for _ in 0..<20 { walker.advanceRoaming(now: now, elapsed: 0.05, visible: true) }
        precondition(roamingWindow.frame.origin != start.origin && visibleScreen.contains(roamingWindow.frame), "Production AppKit adapter moves only within its chosen screen")
        let afterWalking = try Data(contentsOf: prefsURL)
        precondition(afterWalking == beforeWalking, "Walking ticks must not write desktop preferences")
        NotificationCenter.default.post(name: DesktopController.petWillDrag, object: roamingWindow)
        let held = roamingWindow.frame
        walker.advanceRoaming(now: now, elapsed: 0.1, visible: true)
        precondition(roamingWindow.frame == held, "User dragging takes priority over autonomous movement")
        NotificationCenter.default.post(name: DesktopController.petDidDrag, object: roamingWindow)
        walker.setRoaming(active: true, deadline: deadline, reduced: true)
        walker.advanceRoaming(now: now, elapsed: 0.1, visible: true)
        precondition(roamingWindow.frame == held, "Reduced motion freezes the actual native window")
        walker.setRoaming(active: true, deadline: deadline, reduced: false)
        walker.advanceRoaming(now: deadline, elapsed: 0.1, visible: true)
        precondition(!walker.isRoaming && roamingWindow.frame == start && !roamingWindow.ignoresMouseEvents,
                     "Deadline stops and returns to original position, restoring input")
        walker.setRoaming(active: true, deadline: Date().addingTimeInterval(5), reduced: false)
        walker.advanceRoaming(now: Date(), elapsed: 0.1, visibleFrames: [], visible: true)
        precondition(!walker.isRoaming && visibleScreen.contains(roamingWindow.frame), "Removing active display stops and safely returns")
        roamingWindow.delegate = nil; roamingWindow.close()
        print("PASS WindowContractChecks: actual DesktopController, undisplayed AppKit window; key eligibility and unchanged main eligibility, clear background/titlebar, hidden traffic lights, drag flag, levels, preference restore, secondary isolation, close-to-hide")
        print("Not verified: physical keyboard input, actual dragging/click-through, popover placement, menu-bar activation, real OS lock/sleep.")
    }
}
