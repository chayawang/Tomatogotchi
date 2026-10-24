import CareFlow
import AdoptionFlow
import AppKit
import SwiftUI
import PetCore
import UserNotifications
import DesktopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AdoptionModel?
    weak var care: CareModel?
    weak var desktop: DesktopController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let session = AppSession.shared
        guard session.ownsSession else {
            if let error = session.startupError {
                let alert = NSAlert()
                alert.messageText = "暫時無法開啟 Tomatogotchi"
                alert.informativeText = error
                alert.addButton(withTitle: "關閉")
                alert.runModal()
            } else if let pid = SessionLease.ownerProcessID(directory: session.directory),
                      let existing = NSRunningApplication(processIdentifier: pid),
                      existing.bundleIdentifier == Bundle.main.bundleIdentifier {
                existing.activate(options: [.activateIgnoringOtherApps])
            }
            if session.startupError == nil {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.showNotification, object: session.directory.standardizedFileURL.path,
                    userInfo: nil, deliverImmediately: true)
            }
            NSApp.terminate(nil)
            return
        }
        _ = ApplicationIcon.install()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked),
            name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showExistingWindow),
            name: Self.showNotification, object: session.directory.standardizedFileURL.path)
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
        if ProcessInfo.processInfo.environment["TOMATOGOTCHI_NOTIFICATION_PROBE"] == "1",
           ProcessInfo.processInfo.environment["TOMATOGOTCHI_DATA_DIR"]?.isEmpty == false {
            Task { await NativeNotificationProbe.run(directory: session.directory) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    private static let showNotification = Notification.Name("work.shiroi.tomatogotchi.show")
    @objc private func screenLocked() { NotificationCenter.default.post(name: CareModel.screenLocked, object: nil) }
    @objc private func showExistingWindow() { desktop?.show() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        desktop?.show()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.saving == true { NSSound.beep(); return .terminateCancel }
        care?.prepareToQuit()
        return .terminateNow
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.desktop?.show() }
        completionHandler()
    }
}

@main
struct TomatogotchiApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var memorial: MemorialModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AdoptionModel
    @StateObject private var desktop: DesktopController
    @StateObject private var care: CareModel
    init() {
        Theme.registerFont()
        let session = AppSession.shared
        let directory = session.directory
        _memorial = StateObject(wrappedValue: MemorialModel(repository: PetRepository(directory: directory)))
        _model = StateObject(wrappedValue: AdoptionModel(repository: PetRepository(directory: directory)))
        _desktop = StateObject(wrappedValue: DesktopController(directory: directory, ownsSession: session.ownsSession))
        _care = StateObject(wrappedValue: CareModel(directory: directory, ownsSession: session.ownsSession))
    }
    var body: some Scene {
        Window("Tomatogotchi", id: "main") {
            if AppSession.shared.ownsSession {
                DesktopRootView(model: model, desktop: desktop, care: care).onAppear {
                    delegate.model = model; delegate.care = care; delegate.desktop = desktop
                    CareActions.connect(model: model, care: care)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("修改名字") { model.edit() }.disabled(model.screen != .home || model.saving)
            }
        }
        Window("死亡寵物紀錄", id: "memorial") {
            if AppSession.shared.ownsSession { MemorialWindowView(adoption: model, memorial: memorial) }
        }.defaultSize(width: 460, height: 540)
        MenuBarExtra {
            Button("死亡寵物紀錄") { openWindow(id: "memorial") }
            Button("顯示電子蛋") { desktop.show() }
            Button(desktop.compact ? "回到一般視窗" : "只顯示寵物") { desktop.toggleCompact() }
                .disabled(model.screen != .home || model.saving)
            Toggle("置頂視窗", isOn: Binding(get: { desktop.alwaysOnTop }, set: { desktop.setOnTop($0) }))
            Divider()
            Text(care.compactStatus)
            Group {
                if care.cycle.phase == .idle {
                    Button(care.startTitle) { care.start(for: model.pet?.id) }
                } else if care.cycle.phase == .restComplete {
                    Button("我回來了，繼續陪伴") { care.start(for: model.pet?.id, afterSaving: care.cycle.completedReceipt) }
                } else if care.cycle.phase == .paused {
                    if care.cycle.hasPendingNeed {
                        Button(care.cycle.demand?.title ?? "照顧牠") { CareActions.respond(model: model, care: care) }
                    }
                    Button("繼續陪伴") { care.resume() }.disabled(model.progressError != nil)
                } else if care.cycle.phase == .working {
                    Button("暫停陪伴") { care.pause() }
                } else if care.cycle.phase == .needsCare {
                    Button(care.cycle.demand?.title ?? "照顧牠") { CareActions.respond(model: model, care: care) }
                    Button("暫停陪伴") { care.pause() }
                }
                if care.cycle.phase != .idle {
                    Button("今天先收工") {
                        care.stop(afterSaving: model.hasSavedRest(care.cycle.completedReceipt) ? care.cycle.completedReceipt : nil)
                    }
                }
            }.disabled(model.screen != .home || model.saving || care.needsReset || model.pet?.growth.stage == .departed
                || (care.cycle.phase == .restComplete && !model.hasSavedRest(care.cycle.completedReceipt)))
            Divider()
            Button("結束 Tomatogotchi") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Text(care.cycle.phase == .working ? "🥚 \(care.workTime)" : "🥚")
                .monospacedDigit()
                .accessibilityLabel(care.cycle.phase == .working ? "Tomatogotchi，工作剩餘 \(care.workTime)" : "Tomatogotchi")
        }
    }
}
