import Foundation
import CoreGraphics
import DesktopCore

@main
struct DesktopChecks {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "DesktopChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func main() throws {
        let main = CGRect(x: 0, y: 24, width: 1440, height: 850)
        let left = CGRect(x: -1280, y: -100, width: 1280, height: 780)
        let size = CGSize(width: 400, height: 509)
        let fresh = WindowPlacement.restore(saved: nil, size: size, visibleFrames: [main])!
        try require(main.contains(fresh), "Default window must fit visible frame")
        let negative = CGRect(x: -1200, y: -50, width: 400, height: 509)
        let restored = WindowPlacement.restore(saved: negative, size: size, visibleFrames: [main, left])!
        try require(restored == negative && left.contains(restored), "Negative-coordinate monitor must restore")
        let unplugged = WindowPlacement.restore(saved: negative, size: size, visibleFrames: [main])!
        try require(main.contains(unplugged), "Removed monitor must not strand the window")
        let huge = WindowPlacement.restore(saved: CGRect(x: 5000, y: 5000, width: 9000, height: 9000), size: CGSize(width: 9000, height: 9000), visibleFrames: [main])!
        try require(huge == main, "Oversized window clamps to available screen")
        let invalid = WindowPlacement.restore(saved: CGRect(x: CGFloat.nan, y: 0, width: 200, height: 220), size: CGSize(width: CGFloat.infinity, height: -1), visibleFrames: [main])!
        try require(main.contains(invalid), "Nonfinite geometry must recover safely")
        try require(WindowPlacement.restore(saved: nil, size: size, visibleFrames: []) == nil, "No display must be handled")
        let small = WindowPlacement.restore(saved: fresh, size: CGSize(width: 200, height: 220), visibleFrames: [main])!
        try require(small.maxY == fresh.maxY && main.contains(small), "Compacting keeps the top edge")
        let preferences = DesktopPreferences(compact: true, alwaysOnTop: true, frame: negative)
        let decoded = try JSONDecoder().decode(DesktopPreferences.self, from: JSONEncoder().encode(preferences))
        try require(decoded == preferences, "Window preferences round-trip independently of a pet")
        let legacy = Data(#"{"compact":true,"alwaysOnTop":true}"#.utf8)
        let upgraded = try JSONDecoder().decode(DesktopPreferences.self, from: legacy)
        try require(upgraded.compact && upgraded.alwaysOnTop && upgraded.shellColor == nil, "Old window preferences retain mode and level without a color")
        let color = ShellColor(red: 0.92, green: 0.3, blue: 0.55)
        let colored = DesktopPreferences(compact: true, alwaysOnTop: true, frame: negative, shellColor: color)
        try require(try JSONDecoder().decode(DesktopPreferences.self, from: JSONEncoder().encode(colored)) == colored, "Custom color survives reopen with existing preferences")
        try require(ShellColor(red: -1, green: 2, blue: .nan) == ShellColor(red: 0, green: 1, blue: 0), "Invalid color input is normalized")
        var colors = 0
        for r in 0...10 {
            for g in 0...10 {
                for b in 0...10 {
                    let c = ShellColor(red: Double(r)/10, green: Double(g)/10, blue: Double(b)/10)
                    let p = c.buttonPalette
                    try require(p.primary.contrast(with: p.primaryInk) >= 4.5, "Primary key icon contrast")
                    try require(p.secondary.contrast(with: p.secondaryInk) >= 4.5, "Secondary key icon contrast")
                    try require(c.contrast(with: c.contrastingInk) >= 4.5, "Shell label contrast")
                    colors += 1
                }
            }
        }
        let reopenedColor = try JSONDecoder().decode(DesktopPreferences.self, from: JSONEncoder().encode(colored)).shellColor!
        try require(reopenedColor.buttonPalette == color.buttonPalette, "Reopen derives the same three key colors")
        try require(color.buttonPalette != ShellColor.default.buttonPalette, "All button surfaces follow a changed shell")
        for screen in [CGRect(x: 0, y: 40, width: 900, height: 650), CGRect(x: -1200, y: -500, width: 1000, height: 800)] {
            for velocity in [CGPoint(x: 42, y: 29), CGPoint(x: -42, y: -29)] {
                var walk = DesktopWalk(origin: CGPoint(x: screen.midX, y: screen.midY), velocity: velocity)
                var positions = Set<String>()
                for _ in 0..<3000 {
                    let point = walk.move(elapsed: 0.05, windowSize: CGSize(width: 128, height: 128), visibleFrame: screen)
                    try require(screen.contains(CGRect(origin: point, size: CGSize(width: 128, height: 128))), "Reflected pet window never leaves current visible desktop")
                    positions.insert("\(Int(point.x)),\(Int(point.y))")
                }
                try require(positions.count > 500, "Desktop walking covers a 2D path")
            }
        }
        print("PASS ShellButtonPalette: \(colors) RGB samples, all icons/labels >=4.5:1; derived colors survive existing preference round-trip")
        print("PASS DesktopChecks: visible bounds, negative monitor, unplugged display, huge/nonfinite geometry, no display, compact anchor, preferences round-trip")
    }
}
