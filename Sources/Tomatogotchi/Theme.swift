import AppKit
import SwiftUI
import CoreText
import ImageIO
import PetCore

enum AppResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Tomatogotchi_Tomatogotchi.bundle"),
           let bundled = Bundle(url: url) { return bundled }
        return Bundle.module
    }()
}

enum ApplicationIcon {
    /// Set the Dock image from the bundled artwork even when Launch Services has a stale icon.
    @MainActor static func install() -> Bool {
        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? AppResources.bundle.url(forResource: "AppIcon", withExtension: "icns")
        guard let url, let image = NSImage(contentsOf: url), image.isValid else { return false }
        NSApp.applicationIconImage = image
        return true
    }
}

enum Theme {
    // Character palette retains the original gray study; shell colors are local design defaults.
    static let canvas = Color(red: 241/255, green: 241/255, blue: 239/255)
    static let surface = Color.white
    static let ink = Color(red: 41/255, green: 45/255, blue: 43/255)
    static let muted = Color(red: 114/255, green: 120/255, blue: 114/255)
    static let line = Color(red: 217/255, green: 220/255, blue: 215/255)
    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "NotoSansTC-Bold" : "NotoSansTC-Regular", size: size)
    }
    static func registerFont() {
        if let url = AppResources.bundle.url(forResource: "NotoSansTC", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct PetButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.font(14)).frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(secondary ? Theme.ink : enabled ? Theme.surface : Theme.muted)
            .background(secondary ? Color.clear : enabled ? Theme.ink : Theme.line)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

struct EggStage: View {
    var height: CGFloat = 144
    var framed = true
    private static let egg: CGImage? = {
        guard let url = AppResources.bundle.url(forResource: "egg", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
    var body: some View {
        Group {
            if let egg = Self.egg {
                Image(decorative: egg, scale: 1).resizable().interpolation(.none).frame(width: 80, height: 100)
                    .padding(.top, 6).padding(.bottom, 6).padding(.horizontal, 8)
            } else { Text("蛋圖載入失敗").foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .background(framed ? Theme.canvas : Color.clear).clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore).accessibilityLabel("一顆尚未孵化的未知像素蛋")
    }
}

/// Uses the original pixel artwork with nearest-neighbor rendering.
private struct PetMotionVisibleKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var petMotionVisible: Bool {
        get { self[PetMotionVisibleKey.self] }
        set { self[PetMotionVisibleKey.self] = newValue }
    }
}

struct TombstoneStage: View {
    var height: CGFloat = 144
    var framed = true
    private static let image: CGImage? = {
        guard let url = AppResources.bundle.url(forResource: "tombstone", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
    var body: some View {
        Group {
            if let image = Self.image {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).frame(width: 72, height: 72)
            } else { Text("墓碑圖載入失敗").font(Theme.font(12)) }
        }.frame(maxWidth: .infinity).frame(height: height)
            .background(framed ? Theme.canvas : Color.clear).clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore).accessibilityLabel("墓碑，這段陪伴會保留。")
    }
}

struct PetStage: View {
    let pet: Pet?
    var height: CGFloat = 144
    var framed = true
    var visualContext: PetVisualContext = .wandering
    var movesWithinContainer = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.petMotionVisible) private var motionVisible
    @State private var blinking = false
    @State var plan = PetAnimationPlan()
    @State private var walkElapsed: Double = 0
    private var animates: Bool {
        guard let pet else { return false }
        return motionVisible && !reduceMotion &&
            (pet.growth.stage == .hatchling || pet.growth.stage == .adult)
    }
    private var motionID: String {
        "\(pet?.id.uuidString ?? "none")-\(pet?.growth.stage.rawValue ?? "none")-\(animates)-\(visualContext.rawValue)-\(pet?.growth.mood ?? 5)"
    }
    private static let animals: [String: CGImage] = {
        var result: [String: CGImage] = [:]
        for species in PetSpecies.allCases.map(\.rawValue) {
            for action in PetAction.allCases {
                for expression in PetExpression.allCases {
                    for frame in [0, 1] {
                        let key = "\(species)-\(action.rawValue)-\(expression.rawValue)-\(frame)"
                        if let url = AppResources.bundle.url(forResource: key, withExtension: "png"),
                           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { result[key] = image }
                    }
                }
            }
        }
        return result
    }()
    var body: some View {
        if pet?.growth.stage == .departed {
            TombstoneStage(height: height, framed: framed)
        } else if let pet, pet.growth.stage != .egg {
            GeometryReader { geometry in
                ZStack {
                if let image = Self.animals[(animates ? plan : PetAnimationPlan()).asset(species: pet.growth.species, secondFrame: animates && blinking)] {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: pet.growth.stage == .hatchling ? 72 : 96,
                               height: pet.growth.stage == .hatchling ? 72 : 96)
                } else { Text("角色圖載入失敗").font(Theme.font(12)).foregroundStyle(Theme.muted) }
                }
                .offset(x: animates && movesWithinContainer ? PetTravel.offset(elapsed: walkElapsed, availableWidth: geometry.size.width,
                    spriteWidth: pet.growth.stage == .hatchling ? 72 : 96) : 0)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .background(framed ? Theme.canvas : Color.clear).clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore).accessibilityLabel(pet.growth.label)
            .task(id: motionID) {
                blinking = false
                walkElapsed = 0
                plan = PetAnimationPlan()
                guard animates else { return }
                var sequence = PetAnimationSequence()
                do {
                    while !Task.isCancelled {
                        plan = sequence.next(context: visualContext, mood: pet.growth.mood) { Int.random(in: 0..<$0) }
                        var previous = ProcessInfo.processInfo.systemUptime
                        let end = previous + Double(plan.seconds)
                        blinking = false
                        var nextFrame = previous + Double(plan.frameDuration(secondFrame: false)) / 1_000_000_000
                        while ProcessInfo.processInfo.systemUptime < end {
                            try await Task.sleep(nanoseconds: 50_000_000)
                            try Task.checkCancellation()
                            let tick = ProcessInfo.processInfo.systemUptime
                            if plan.action == .walk { walkElapsed += min(0.1, max(0, tick - previous)) }
                            previous = tick
                            if tick >= nextFrame {
                                blinking.toggle()
                                nextFrame = tick + Double(plan.frameDuration(secondFrame: blinking)) / 1_000_000_000
                            }
                        }
                    }
                } catch { /* Cancellation never writes pet/care data or replays missed frames. */ }
            }
        } else { EggStage(height: height, framed: framed) }
    }
}
