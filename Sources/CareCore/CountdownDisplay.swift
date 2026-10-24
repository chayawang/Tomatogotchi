import Foundation

public enum CountdownDisplay {
    public static func text(seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let rounded = Int(ceil(min(86400, max(0, seconds))))
        return String(format: "%02d:%02d", rounded / 60, rounded % 60)
    }
}
