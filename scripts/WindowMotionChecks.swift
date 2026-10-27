import AppKit
import SwiftUI
import PetCore
import AdoptionFlow
import CareCore
import CareFlow
import DesktopCore

@MainActor final class MotionReminder: CareReminderCenter {
    func permission() async -> ReminderPermission { .denied }
    func authorize() async throws -> Bool { false }
    func add(id: String, delay: TimeInterval) async throws { }
    func remove(id: String) { }
}

@MainActor final class MotionDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
private struct QAReduceMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var qaReduceMotion: Bool {
        get { self[QAReduceMotionKey.self] }
        set { self[QAReduceMotionKey.self] = newValue }
    }
}
@MainActor final class MotionInput: ObservableObject { @Published var reduced = false }
@MainActor struct MotionRootHarness: View {
    @ObservedObject var input: MotionInput
    @ObservedObject var model: AdoptionModel
    @ObservedObject var desktop: DesktopController
    @ObservedObject var care: CareModel
    var body: some View {
        DesktopRootView(model: model, desktop: desktop, care: care)
            .environment(\.qaReduceMotion, input.reduced)
    }
}
@main @MainActor struct WindowMotionChecks: App {
    @NSApplicationDelegateAdaptor(MotionDelegate.self) private var delegate
    @StateObject private var motionInput = MotionInput()
    @StateObject private var model: AdoptionModel
    @StateObject private var desktop: DesktopController
    @StateObject private var care: CareModel
    private let folder: URL
    init() {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QA_MOTION_DIRECTORY"]!)
        folder = directory
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var pet = try! Pet(name: "視窗隔離測試")
        try! pet.applyNeed(id: UUID(), food: true, steps: 0, responding: true, now: Date(timeIntervalSince1970: 0))
        for n in 0..<3 { try! pet.completeRest(id: "motion-hatch-\(n)", food: true, now: Date()) }
        try! JSONEncoder().encode(pet).write(to: folder.appendingPathComponent("pet.json"))
        Theme.registerFont()
        _model = StateObject(wrappedValue: AdoptionModel(repository: PetRepository(directory: directory)))
        _desktop = StateObject(wrappedValue: DesktopController(directory: directory, automaticallyRoams: false))
        _care = StateObject(wrappedValue: CareModel(directory: directory, ownsSession: true, reminderCenter: MotionReminder(),
            workspaceNotifications: NotificationCenter(), lockNotifications: NotificationCenter(), automaticallyTicks: false))
    }
    var body: some Scene {
        Window("Isolated window motion checks", id: "main") {
            MotionRootHarness(input: motionInput, model: model, desktop: desktop, care: care)
                .onAppear { Task { await verify() } }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
    private func verify() async {
        do {
            for _ in 0..<100 {
                if model.screen == .home && NSApp.windows.contains(where: { $0.title == "Isolated window motion checks" }) { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard let window = NSApp.windows.first(where: { $0.title == "Isolated window motion checks" }) else { fatalError("No SwiftUI window") }
            FileHandle.standardOutput.write(Data("Host Reduce Motion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion); QA positive case explicitly injects false, then checks true/false root changes.\n".utf8))
            window.orderOut(nil)
            var resizeCount = 0
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in resizeCount += 1 }
            defer { NotificationCenter.default.removeObserver(observer) }
            func record(_ label: String) {
                let text = "\(label): frame=\(window.frame), content=\(window.contentView!.frame), resizeEvents=\(resizeCount), titlebarInset=\(desktop.titlebarInset), layout=\(window.contentLayoutRect), safe=\(window.contentView!.safeAreaInsets), titleView=\(String(describing: window.standardWindowButton(.closeButton)?.superview?.frame))\n"
                FileHandle.standardOutput.write(Data(text.utf8))
            }
            func snapshot(_ name: String) throws {
                let host = window.contentView!
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name+".png"))
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            record("normal settled")
            try snapshot("normal-root")
            precondition(window.contentView!.frame.size == CGSize(width: 247, height: 304), "Normal size including hidden-titlebar compensation")
            let beforeMove = resizeCount
            let screen = NSScreen.main!.visibleFrame
            // Use integral screen points: AppKit may round a fractional origin immediately.
            // The assertion still requires the moved origin to stay exactly unchanged.
            let target = CGPoint(x: floor(screen.midX - window.frame.width/2), y: floor(screen.midY - window.frame.height/2))
            window.setFrameOrigin(target)
            try await Task.sleep(nanoseconds: 300_000_000)
            record("normal moved")
            precondition(window.frame.origin == target, "SwiftUI layout pulled moved window back")
            precondition(resizeCount - beforeMove <= 2, "Continuous resize loop during movement")
            desktop.toggleCompact()
            try await Task.sleep(nanoseconds: 300_000_000)
            record("pet settled")
            try snapshot("pet-root")
            precondition(window.contentView!.frame.size == CGSize(width: 160, height: 128), "Pet-only size")
            let petTarget = CGPoint(x: target.x - 80, y: target.y + 80)
            let beforePetMove = resizeCount
            window.setFrameOrigin(petTarget)
            try await Task.sleep(nanoseconds: 300_000_000)
            record("pet moved")
            precondition(window.frame.origin == petTarget && resizeCount - beforePetMove <= 2, "Pet-only layout pulled moved window back")
            desktop.toggleCompact()
            try await Task.sleep(nanoseconds: 300_000_000)
            record("normal restored")
            precondition(window.contentView!.frame.size == CGSize(width: 247, height: 304), "Normal size after restore")
            let stable = window.frame
            let beforeIdle = resizeCount
            try await Task.sleep(nanoseconds: 300_000_000)
            precondition(window.frame == stable && resizeCount == beforeIdle, "Window keeps resizing when idle")
            let prefs = try JSONDecoder().decode(DesktopPreferences.self, from: Data(contentsOf: folder.appendingPathComponent("desktop.json")))
            precondition(prefs.frame == window.frame, "Saved position matches live SwiftUI window")
            care.start(for: model.pet!.id)
            care.rest(.walk)
            desktop.toggleCompact()
            try await Task.sleep(nanoseconds: 300_000_000)
            precondition(desktop.isRoaming && window.contentView!.frame.size == CGSize(width: 128, height: 128),
                         "Real root enters sprite-sized desktop walk only for compact walking rest")
            let roamStart = window.frame
            desktop.advanceRoaming(now: Date(), elapsed: 0.1, visible: true)
            precondition(window.frame.origin != roamStart.origin, "Root-connected walking adapter translates its actual window")
            motionInput.reduced = true
            try snapshot("reduced-motion-on")
            try await Task.sleep(nanoseconds: 300_000_000)
            let reducedFrame = window.frame
            desktop.advanceRoaming(now: Date(), elapsed: 0.1, visible: true)
            precondition(window.frame == reducedFrame, "Real root Reduce Motion stops displacement")
            motionInput.reduced = false
            try snapshot("reduced-motion-off")
            try await Task.sleep(nanoseconds: 300_000_000)
            desktop.advanceRoaming(now: Date(), elapsed: 0.1, visible: true)
            precondition(window.frame.origin != reducedFrame.origin, "Real root resumes displacement after Reduce Motion is disabled")
            desktop.toggleCompact()
            try await Task.sleep(nanoseconds: 300_000_000)
            precondition(!desktop.isRoaming && window.contentView!.frame.size == CGSize(width: 247, height: 304),
                         "Switching back to device ends desktop movement without discarding rest")
            precondition(care.cycle.phase == .resting && care.cycle.activity == .walk,
                         "Mode switch must preserve the actual rest")
            care.stop()
            FileHandle.standardOutput.write(Data("PASS WindowMotionChecks: actual SwiftUI Window/contentSize + DesktopRootView, normal/pet movement, mode sizes, stable idle and saved placement; no physical mouse events\n".utf8))
            exit(0)
        } catch { fatalError("\(error)") }
    }
}
