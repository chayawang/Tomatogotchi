import AppKit
import SwiftUI
import PetCore
import AdoptionFlow
import CareFlow
import CareCore

@MainActor final class AdoptionQAReminder: CareReminderCenter {
    func permission() async -> ReminderPermission { .denied }
    func authorize() async throws -> Bool { false }
    func add(id: String, delay: TimeInterval) async throws {}
    func remove(id: String) {}
}
@main @MainActor struct AdoptionPresentationChecks: App {
    @StateObject private var model: AdoptionModel
    @StateObject private var desktop: DesktopController
    @StateObject private var care: CareModel
    private let folder: URL
    init() {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QA_ADOPTION_DIRECTORY"]!)
        folder = directory
        Theme.registerFont()
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _model = StateObject(wrappedValue: AdoptionModel(repository: PetRepository(directory: directory)))
        _desktop = StateObject(wrappedValue: DesktopController(directory: directory, automaticallyRoams: false))
        _care = StateObject(wrappedValue: CareModel(directory: directory, ownsSession: true,
            reminderCenter: AdoptionQAReminder(), workspaceNotifications: NotificationCenter(),
            lockNotifications: NotificationCenter(), automaticallyTicks: false))
    }
    var body: some Scene {
        Window("Adoption QA", id: "main") {
            DesktopRootView(model: model, desktop: desktop, care: care)
                .onAppear { Task { await verify() } }
        }.windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "AdoptionQA", code: 1)
    }
    private func snapshot(_ name: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        let window = NSApp.windows.first { $0.title == "Adoption QA" }!
        let host = window.contentView!
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        precondition(abs(host.bounds.width - 400) < 1, "Original rectangular form width must be preserved")
        precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 1, "Original rectangular form must fill its corners")
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name+".png"))
    }
    private func verify() async {
        do {
            try await settle { model.screen == .welcome }
            try await snapshot("01-welcome")
            model.receive()
            try await snapshot("02-naming")
            model.draft = "名字不可\n換行"
            precondition(model.nameError != nil)
            try await snapshot("03-invalid")
            model.draft = "這是一個很長的中文寵物名字也能輸入"
            model.save()
            precondition(model.saving)
            model.save() // Duplicate submission must remain harmless.
            try await settle { !model.saving }
            precondition(model.screen == .home && model.pet?.growth.stage == .egg)
            precondition(care.cycle.phase == .idle, "Adoption must never start work")
            let original = model.pet!
            model.edit(); model.draft = "取消這個名字"; model.cancelEdit()
            precondition(model.pet == original)
            model.edit()
            try await snapshot("04-editing")
            let primary = folder.appendingPathComponent("pet.json")
            let bytes = try Data(contentsOf: primary)
            try FileManager.default.removeItem(at: primary)
            try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: false)
            model.draft = "失敗保留名字"; model.save()
            try await settle { !model.saving }
            precondition(model.saveError != nil && model.draft == "失敗保留名字" && model.pet == original)
            try await snapshot("05-save-error")
            try FileManager.default.removeItem(at: primary)
            try bytes.write(to: primary)
            model.retrySave()
            try await settle { !model.saving }
            precondition(model.pet?.id == original.id && model.pet?.name == "失敗保留名字")
            try Data("damaged-isolated-fixture".utf8).write(to: primary)
            model.load()
            try await settle { model.screen == .loadFailed }
            precondition(model.canRestore)
            try await snapshot("06-load-error")
            model.restore()
            try await settle { !model.saving }
            precondition(model.screen == .home && model.pet?.id == original.id && care.cycle.phase == .idle)
            care.prepareToQuit()
            print("PASS AdoptionPresentationChecks: native device snapshots, optional Chinese names, duplicate save, cancel, failed write retention/retry, backup recovery, stable ID and no automatic timer; actual IME/mouse pending")
            exit(0)
        } catch { fatalError("\(error)") }
    }
}
