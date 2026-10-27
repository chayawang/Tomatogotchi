import AppKit
import SwiftUI
import PetCore
import AdoptionFlow
import CareCore
import CareFlow

@MainActor final class HatchingClock {
    var date = Date(timeIntervalSince1970: 1000)
    var uptime: TimeInterval = 100
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds); uptime += seconds }
}
@MainActor final class HatchingReminder: CareReminderCenter {
    func permission() async -> ReminderPermission { .denied }
    func authorize() async throws -> Bool { false }
    func add(id: String, delay: TimeInterval) async throws {}
    func remove(id: String) {}
}
@MainActor final class HatchingDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main @MainActor struct FirstCareHatchingChecks: App {
    @NSApplicationDelegateAdaptor(HatchingDelegate.self) private var delegate
    @StateObject private var model: AdoptionModel
    @StateObject private var desktop: DesktopController
    @StateObject private var care: CareModel
    private let clock: HatchingClock
    private let folder: URL
    private let compact: Bool
    init() {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QA_HATCH_DIRECTORY"]!)
        folder = directory
        compact = ProcessInfo.processInfo.environment["QA_HATCH_COMPACT"] == "1"
        let activity: CareActivity = compact ? .walk : .food
        let clock = HatchingClock(); self.clock = clock
        Theme.registerFont()
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! JSONEncoder().encode(Pet(name: "首次照顧驗收")).write(to: directory.appendingPathComponent("pet.json"))
        _model = StateObject(wrappedValue: AdoptionModel(repository: PetRepository(directory: directory)))
        _desktop = StateObject(wrappedValue: DesktopController(directory: directory, automaticallyRoams: false))
        _care = StateObject(wrappedValue: CareModel(directory: directory, ownsSession: true,
            reminderCenter: HatchingReminder(), workspaceNotifications: NotificationCenter(),
            lockNotifications: NotificationCenter(), chooseDemand: { activity }, automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime }))
    }
    var body: some Scene {
        Window("First care hatching QA", id: "main") {
            DesktopRootView(model: model, desktop: desktop, care: care)
                .onAppear { Task { await verify() } }
        }.windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "HatchingQA", code: 1, userInfo: [NSLocalizedDescriptionKey: "UI did not settle"])
    }
    private func snapshot(_ name: String, window: NSWindow) throws {
        let host = window.contentView!
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name+".png"))
    }
    private func verify() async {
        do {
            try await settle { model.screen == .home }
            guard let window = NSApp.windows.first(where: { $0.title == "First care hatching QA" }) else { fatalError("Missing QA window") }
            CareActions.connect(model: model, care: care)
            if compact { desktop.toggleCompact() }
            try await Task.sleep(nanoseconds: 200_000_000)
            care.start(for: model.pet!.id)
            clock.advance(300); care.refresh()
            try await settle { !model.saving }
            precondition(model.pet!.growth.stage == .egg, "Work deadline must keep egg")
            try snapshot("work-complete-egg", window: window)
            desktop.hide()
            try await Task.sleep(nanoseconds: 100_000_000)
            precondition(!window.isVisible)
            let clicked = clock.date
            CareActions.respond(model: model, care: care)
            precondition(care.hatchingPresentationID != nil && !model.saving && model.pet!.growth.stage == .egg,
                         "Hidden menu-bar care must request visible egg before saving")
            try await settle { model.pet?.growth.stage == .hatchling && care.cycle.phase == .resting }
            precondition(window.isVisible && desktop.animationVisible && care.hatchingPresentationID == nil,
                         "Visible PetStage must acknowledge presentation before committing")
            precondition(care.cycle.restDeadline == clicked.addingTimeInterval(300), "Animation cannot reset the rest deadline")
            precondition(model.pet!.growth.completedRests.isEmpty, "Hatching cannot grant a rest receipt")
            try await Task.sleep(nanoseconds: 100_000_000)
            try snapshot("first-care-cracked", window: window)
            try await Task.sleep(nanoseconds: 1_500_000_000)
            try snapshot("first-care-hatchling", window: window)
            let stored = try await PetRepository(directory: folder).load()!
            precondition(stored.growth.hasHatched && stored.growth.stage == .hatchling)
            print("PASS FirstCareHatchingChecks: compact=\(compact), hidden first care reveals visible egg before atomic save, rest deadline unchanged, committed hatchling and native snapshots")
            care.prepareToQuit()
            exit(0)
        } catch { fatalError("\(error)") }
    }
}
