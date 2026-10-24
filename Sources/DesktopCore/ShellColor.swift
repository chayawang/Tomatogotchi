import Foundation

/// Device appearance only; never part of a pet or care snapshot.
public struct ShellColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public static let `default` = ShellColor(red: 131/255, green: 157/255, blue: 242/255)
    public init(red: Double, green: Double, blue: Double) {
        func channel(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        self.red = channel(red); self.green = channel(green); self.blue = channel(blue)
    }
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrast(with other: ShellColor) -> Double {
        (max(relativeLuminance, other.relativeLuminance) + 0.05) / (min(relativeLuminance, other.relativeLuminance) + 0.05)
    }
    public var contrastingInk: ShellColor {
        let white = ShellColor(red: 1, green: 1, blue: 1)
        let black = ShellColor(red: 0, green: 0, blue: 0)
        return contrast(with: white) > contrast(with: black) ? white : black
    }
    public var needsLightLabels: Bool { contrastingInk.red == 1 }
    public var buttonPalette: ShellButtonPalette {
        ShellButtonPalette(
            secondary: ShellColor(red: red * 0.55 + 0.45, green: green * 0.55 + 0.45, blue: blue * 0.55 + 0.45),
            primary: ShellColor(red: red * 0.35, green: green * 0.35, blue: blue * 0.35),
            border: ShellColor(red: red * 0.20, green: green * 0.20, blue: blue * 0.20))
    }
}

/// Derived only; no new persisted fields and no separate button color preference.
public struct ShellButtonPalette: Equatable, Sendable {
    public let secondary: ShellColor
    public let primary: ShellColor
    public let border: ShellColor
    public var secondaryInk: ShellColor { secondary.contrastingInk }
    public var primaryInk: ShellColor { primary.contrastingInk }
}
