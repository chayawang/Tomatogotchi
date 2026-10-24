import AppKit
import SwiftUI
import PetCore

@MainActor final class LiveDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor final class LiveDriver: ObservableObject {
    @Published var visible = true
    @Published var reduced = false
    @Published var context: PetVisualContext = .walking
    @Published var pet: Pet
    init() {
        var p = try! Pet(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "QA")
        for n in 0..<3 { try! p.completeRest(id: "live-\(n)", food: true, now: Date(timeIntervalSince1970: 0)) }
        pet = p
    }
}
@main @MainActor struct LivePresentationChecks: App {
    @NSApplicationDelegateAdaptor(LiveDelegate.self) private var delegate
    @StateObject private var driver = LiveDriver()
    private let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QA_LIVE_OUTPUT"]!)
    var body: some Scene {
        Window("Live presentation QA", id: "live") {
            PetStage(pet: driver.pet, height: 112, framed: false, visualContext: driver.context, reduceMotion: driver.reduced)
                .environment(\.petMotionVisible, driver.visible)
                .frame(width: 128, height: 128).background(Color.white)
                .onAppear { Task { await verify() } }
        }.windowResizability(.contentSize)
    }
    private func verify() async {
        do {
            FileHandle.standardOutput.write(Data("Live QA started\n".utf8))
            for _ in 0..<100 {
                if NSApp.windows.contains(where: { $0.title == "Live presentation QA" }) { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard let window = NSApp.windows.first(where: { $0.title == "Live presentation QA" }), let host = window.contentView else { fatalError("No QA host") }
            window.orderOut(nil)
            func snapshot(_ name: String) throws -> Data {
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = bitmap.representation(using: .png, properties: [:])!
                try png.write(to: output.appendingPathComponent(name+".png"))
                return png
            }
            func frames(_ name: String, count: Int = 10, delay: UInt64 = 100_000_000) async throws -> Set<Data> {
                var result = Set<Data>()
                for n in 0..<count {
                    try await Task.sleep(nanoseconds: delay)
                    result.insert(try snapshot("\(name)-\(n)"))
                }
                return result
            }
            let walking = try await frames("walk")
            precondition(walking.count >= 2, "Actual SwiftUI task must animate walking")
            let centers = walking.map { data -> Double in
                let bitmap = NSBitmapImageRep(data: data)!
                var xs: [Int] = []
                for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    if color.redComponent < 0.5 && color.greenComponent < 0.5 && color.blueComponent < 0.5 { xs.append(x) }
                } }
                precondition(!xs.isEmpty)
                return Double(xs.min()! + xs.max()!) / 2
            }
            precondition(centers.max()! - centers.min()! > 4, "Real SwiftUI walking must change screen position, not only frames")
            driver.visible = false
            try await Task.sleep(nanoseconds: 100_000_000)
            let hidden = try await frames("hidden", count: 5)
            precondition(hidden.count == 1, "Invisible motion must stop")
            driver.visible = true; driver.reduced = true
            try await Task.sleep(nanoseconds: 100_000_000)
            let reduced = try await frames("reduced", count: 5)
            precondition(reduced == hidden, "Reduce Motion must use the exact static idle")
            driver.reduced = false; driver.context = .eating
            let eating = try await frames("eat")
            precondition(eating.count >= 2, "Context must restart actual eating playback")
            driver.context = .sleeping
            let sleeping = try await frames("sleep", count: 7, delay: 250_000_000)
            precondition(sleeping.count >= 2, "Sleep must animate breathing")
            var dead = driver.pet
            try dead.applyNeed(id: UUID(), food: true, steps: 5, responding: false, now: Date(timeIntervalSince1970: 1))
            driver.pet = dead
            try await Task.sleep(nanoseconds: 100_000_000)
            let grave = try await frames("grave", count: 5)
            precondition(grave.count == 1 && grave != hidden, "Death must cancel live motion and show tombstone")
            precondition(ApplicationIcon.install(), "The actual application icon must load from bundled icns")
            let icon = NSApp.applicationIconImage!
            var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
            guard let cg = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { fatalError("No native icon") }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            var bluePixels = 0
            var eggPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.9 else { continue }
                    if c.blueComponent > c.redComponent + 0.15 { bluePixels += 1 }
                    if c.redComponent > 0.8 && c.greenComponent > 0.8 && c.blueComponent > 0.65 && c.blueComponent < 0.95 { eggPixels += 1 }
                }
            }
            precondition(bluePixels > 20 && eggPixels > 20, "Native application icon must contain the blue shell and cream egg, not generic artwork")
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("app-icon-native.png"))
            print("PASS LivePresentationChecks: real SwiftUI task produces walking/eating/sleeping frames; injected invisible and Reduce Motion states stop to exact idle; death cancels to static grave; actual application icon has verified blue and egg pixels")
            print("Synthetic environment inputs and hidden QA window do not verify physical clicks, Dock, true OS preference toggles or actual lock/sleep.")
            exit(0)
        } catch { fatalError("\(error)") }
    }
}
