import Foundation
import CoreGraphics

/// Pure reflected 2D motion, in AppKit points, within one display's visible frame.
public struct DesktopWalk {
    public private(set) var origin: CGPoint
    public private(set) var velocity: CGPoint
    public init(origin: CGPoint, velocity: CGPoint = CGPoint(x: 42, y: 29)) {
        self.origin = origin; self.velocity = velocity
    }
    public mutating func move(elapsed: Double, windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        guard elapsed.isFinite, elapsed >= 0,
              [visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height,
               windowSize.width, windowSize.height, origin.x, origin.y, velocity.x, velocity.y].allSatisfy(\.isFinite),
              visibleFrame.width > 0, visibleFrame.height > 0, windowSize.width > 0, windowSize.height > 0 else { return origin }
        func reflect(_ point: CGFloat, _ velocity: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> (CGFloat, CGFloat) {
            let length = max(0, upper - lower)
            guard length > 0 else { return (lower, velocity) }
            let start = min(upper, max(lower, point)) - lower
            let phase = (start + velocity * elapsed).truncatingRemainder(dividingBy: 2 * length)
            let wrapped = phase < 0 ? phase + 2 * length : phase
            let result = wrapped <= length ? wrapped : 2 * length - wrapped
            let heading: CGFloat = wrapped == 0 ? abs(velocity) : wrapped == length ? -abs(velocity) : wrapped < length ? velocity : -velocity
            return (lower + result, heading)
        }
        let x = reflect(origin.x, velocity.x, visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let y = reflect(origin.y, velocity.y, visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        origin = CGPoint(x: x.0, y: y.0); velocity = CGPoint(x: x.1, y: y.1)
        return origin
    }
}
