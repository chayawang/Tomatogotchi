import AppKit
import SwiftUI
import PetCore
import AdoptionFlow
import CareCore
import CareFlow
import DesktopCore

@MainActor final class RenderCenter: CareReminderCenter {
    func permission() async -> ReminderPermission { .denied }
    func authorize() async throws -> Bool { false }
    func add(id: String, delay: TimeInterval) async throws { }
    func remove(id: String) { }
}
@main @MainActor
struct DeviceRenderChecks {
    final class ClearHost<Content: View>: NSHostingView<Content> {
        override var isOpaque: Bool { false }
    }
    static func nativeBitmap<Content: View>(_ content: Content, size: CGSize, scale: Int) -> NSBitmapImageRep {
        let host = ClearHost(rootView: content.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width)*scale, pixelsHigh: Int(size.height)*scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        precondition(!window.isVisible, "Native rendering must not show test windows")
        window.close()
        return bitmap
    }
    static func main() async throws {
        _ = NSApplication.shared
        Theme.registerFont()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let now = Date(timeIntervalSince1970: 1000)
        var memorialPets: [PetMemorial] = []
        for n in 0..<30 {
            var pet = try Pet(name: n == 0 ? "這是一個很長的死亡寵物名字也要完整換行保留" : "陪伴\(n)", now: now)
            try pet.applyNeed(id: UUID(), food: false, steps: 5, responding: false, now: now.addingTimeInterval(Double(n)))
            memorialPets.append(PetMemorial(pet: pet)!)
        }
        for scale in [1, 2] {
            let states: [(String, PetMemorialSnapshot?, String?)] = [
                ("empty", PetMemorialSnapshot(), nil),
                ("one", PetMemorialSnapshot(records: [memorialPets[0]]), nil),
                ("many", PetMemorialSnapshot(records: memorialPets), nil),
                ("partial", PetMemorialSnapshot(records: [memorialPets[0]], unreadableCount: 2), nil),
                ("unreadable", PetMemorialSnapshot(unreadableCount: 2), nil),
                ("error", nil, "死亡寵物紀錄暫時無法讀取。原本的紀錄仍保留，請再試一次。")]
            for (name, snapshot, error) in states {
                let bitmap = nativeBitmap(MemorialContent(snapshot: snapshot, error: error), size: CGSize(width: 460, height: 540), scale: scale)
                precondition(bitmap.pixelsWide == 460 * scale && bitmap.pixelsHigh == 540 * scale)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("memorial-\(name)-\(scale)x.png"))
            }
        }
        print("PASS MemorialContent: 12 actual SwiftUI renders for empty/one/30/partial/unreadable/error at 1x and 2x; native scroll/click pending")
        var count = 0
        for state in ["idle", "work", "food", "walk", "paused", "rest", "complete", "dead", "confirm", "long-name", "white-shell", "black-shell", "green-shell"] {
            for compact in [false, true] {
                let folder = output.appendingPathComponent("data-\(state)-\(compact)")
                let repo = PetRepository(directory: folder)
                var pet = try Pet(name: state == "long-name" ? "這是一個非常非常長的名字也要能夠顯示" : "小葉")
                if state != "idle" && state != "long-name" {
                    for i in 0..<3 { try pet.completeRest(id: "qa-\(i)", food: true, now: now) }
                }
                if state == "dead" || state == "confirm" {
                    try pet.applyNeed(id: UUID(), food: false, steps: 5, responding: false, now: now)
                }
                _ = try await repo.adopt(pet)
                var cycle = try CareCycle(workDuration: 300)
                cycle.bind(to: pet.id)
                if state != "idle" && state != "long-name" {
                    cycle.start(demand: state == "walk" ? .walk : .food)
                    if ["food", "walk", "paused"].contains(state) { cycle.advance(workElapsed: 300, now: now) }
                    if state == "rest" || state == "complete" {
                        cycle.rest(.food, now: now)
                        if state == "complete" {
                            cycle.advance(workElapsed: 0, now: now.addingTimeInterval(300))
                            let receipt = cycle.completedReceipt!
                            _ = try await repo.completeRest(id: pet.id, receipt: receipt.id, food: true, now: receipt.completedAt)
                        }
                    }
                }
                try CareStore(directory: folder).save(cycle)
                let model = AdoptionModel(repository: repo)
                model.load()
                for _ in 0..<10000 { if model.screen == .home { break }; await Task.yield() }
                precondition(model.screen == .home)
                if state == "confirm" { model.farewellConfirming = true }
                let care = CareModel(directory: folder, ownsSession: true, reminderCenter: RenderCenter(),
                    workspaceNotifications: NotificationCenter(), lockNotifications: NotificationCenter(), automaticallyTicks: false,
                    now: { state == "complete" ? now.addingTimeInterval(300) : now }, uptime: { 100 })
                if state == "work" || state == "food" || state == "walk" { care.resume() }
                let desktop = DesktopController(directory: folder, ownsSession: false)
                if compact { desktop.toggleCompact() }
                if state == "walk" { desktop.setShellColor(ShellColor(red: 0.94, green: 0.52, blue: 0.65)) }
                if state == "confirm" { desktop.setShellColor(ShellColor(red: 0.12, green: 0.16, blue: 0.22)) }
                if state == "white-shell" { desktop.setShellColor(ShellColor(red: 1, green: 1, blue: 1)) }
                if state == "black-shell" { desktop.setShellColor(ShellColor(red: 0, green: 0, blue: 0)) }
                if state == "green-shell" { desktop.setShellColor(ShellColor(red: 0, green: 1, blue: 0)) }
                if state == "food" { precondition(care.needTime == "03:00") }
                if state == "idle" && !compact {
                    let menu = DeviceMenuView(desktop: desktop, care: care, savedReceipt: nil, canRename: true, canStop: true, rename: {}, stop: {}, dismiss: {})
                    // Native NSColorWell/NSSwitch cannot be drawn by ImageRenderer.
                    // Host only this fake-data menu in an undisplayed AppKit window.
                    let host = NSHostingView(rootView: menu.background(Color.white))
                    let size = host.fittingSize
                    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    host.frame = CGRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                    guard let menuBitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Menu bitmap") }
                    host.cacheDisplay(in: host.bounds, to: menuBitmap)
                    precondition(!window.isVisible, "Menu snapshot cannot show a window")
                    try menuBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("settings-menu-native.png"))
                    window.close()
                }
                let view = PetDeviceView(model: model, care: care, desktop: desktop)
                    .environment(\.petMotionVisible, false)
                for scale in [1,2] {
                    let size = compact ? CGSize(width: 160, height: 128) : CGSize(width: 247, height: 304)
                    let bitmap = nativeBitmap(view, size: size, scale: scale)
                    let w = Int(size.width)*scale, h = Int(size.height)*scale
                    precondition(bitmap.pixelsWide == w && bitmap.pixelsHigh == h, "Device has stable bounds")
                    for (x,y) in [(0,0),(w-1,0),(0,h-1),(w-1,h-1),(w/2,0)] {
                        precondition(bitmap.colorAt(x: x, y: y)!.alphaComponent == 0, "Outside shell must be transparent")
                    }
                    if !compact { precondition(bitmap.colorAt(x: w/2, y: h/2)!.alphaComponent == 1, "LCD must be visible") }
                    let opaque = (0..<h).contains { y in (0..<w).contains { x in bitmap.colorAt(x: x, y: y)!.alphaComponent > 0 } }
                    precondition(opaque, "Every mode must show the pet")
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG") }
                    try png.write(to: output.appendingPathComponent("\(state)-\(compact ? "compact" : "full")-\(scale)x.png"))
                    count += 1
                }
            }
        }
        for color in [ShellColor.default, ShellColor(red: 0.94, green: 0.52, blue: 0.65),
                      ShellColor(red: 0, green: 0, blue: 0), ShellColor(red: 1, green: 1, blue: 1),
                      ShellColor(red: 0, green: 1, blue: 0)] {
            for primary in [false, true] {
                for scale in [1, 2] {
                    let key = DeviceKey(title: "選單", symbol: "stop.fill", primary: primary, shellColor: color, lightLabel: color.needsLightLabels) { }
                    let bitmap = nativeBitmap(key, size: CGSize(width: 48, height: 59), scale: scale)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("latest-key.png"))
                    let palette = color.buttonPalette
                    for (x,y,expected) in [(12,10,primary ? palette.primary : palette.secondary), (2,20,palette.border), (20,16,primary ? palette.primaryInk : palette.secondaryInk)] {
                        guard let actual = bitmap.colorAt(x: x*scale, y: y*scale)?.usingColorSpace(.sRGB) else { fatalError("No key pixel") }
                        precondition(abs(actual.redComponent-expected.red) < 0.01 && abs(actual.greenComponent-expected.green) < 0.01 && abs(actual.blueComponent-expected.blue) < 0.01, "Key pixel (\(x),\(y)) scale=\(scale) primary=\(primary) expected=\(expected) actual=\(actual)")
                    }
                    count += 1
                }
            }
        }
        print("PASS DeviceRenderChecks: \(count) actual PetDeviceView renders, 13 states plus 20 actual key palette samples, normal/pet-only, 1x/2x, transparent outer corners, custom colors, visible pet and settings menu; OS interactions remain separate")
    }
}
