import Foundation
import CoreGraphics

public enum WindowPlacement {
    /// AppKit coordinates in points. First frame is the preferred fallback display.
    public static func restore(saved: CGRect?, size: CGSize, visibleFrames: [CGRect]) -> CGRect? {
        let screens = visibleFrames.filter(valid)
        guard !screens.isEmpty else { return nil }
        let previous = saved.flatMap { valid($0) ? $0 : nil }
        let screen = previous.flatMap { rect in
            screens.max { overlap(rect, $0) < overlap(rect, $1) }
                .flatMap { overlap(rect, $0) > 0 ? $0 : nil }
        } ?? screens[0]
        let width = min(size.width.isFinite && size.width > 0 ? size.width : 400, screen.width)
        let height = min(size.height.isFinite && size.height > 0 ? size.height : 509, screen.height)
        let x = previous?.minX ?? screen.maxX - width - 24
        let y = previous?.maxY.advanced(by: -height) ?? screen.maxY - height - 24
        return CGRect(x: min(max(x, screen.minX), screen.maxX - width),
                      y: min(max(y, screen.minY), screen.maxY - height), width: width, height: height)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }
}

public struct DesktopPreferences: Codable, Equatable {
    public var compact: Bool
    public var alwaysOnTop: Bool
    public var frame: CGRect?
    public var shellColor: ShellColor?
    public init(compact: Bool = false, alwaysOnTop: Bool = false, frame: CGRect? = nil, shellColor: ShellColor? = nil) {
        self.compact = compact; self.alwaysOnTop = alwaysOnTop; self.frame = frame; self.shellColor = shellColor
    }
}
