import Foundation
import AppKit
import CareCore
import CareFlow

@MainActor
final class TestClock {
    var date = Date(timeIntervalSince1970: 1000)
    var uptime: TimeInterval = 100
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds); uptime += seconds }
}

@MainActor
final class TestCenter: CareReminderCenter {
    var status: ReminderPermission = .allowed
    var requests: [String: TimeInterval] = [:]
    var additions = 0
    var removed: [String] = []
    var queried = false
    var extraIDs: [String] = [CareReminder.prefix + "stale", "another-app-request"]
    func permission() async -> ReminderPermission { status }
    func authorize() async throws -> Bool { status == .allowed }
    func add(id: String, delay: TimeInterval) async throws { requests[id] = delay; additions += 1 }
    func remove(id: String) { requests[id] = nil; removed.append(id) }
    func existingIDs() async -> [String] {
        queried = true
        return Array(requests.keys) + extraIDs
    }
}

@main
@MainActor
struct CareFlowChecks {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "CareFlowChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 {
            if condition() { return }
            await Task.yield()
        }
        throw NSError(domain: "CareFlowChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Asynchronous model did not settle"])
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("care-flow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = TestClock(), center = TestCenter(), events = NotificationCenter()
        let rootPrefix = CareReminder.namespace(directory: root)
        center.extraIDs = [rootPrefix + "stale", "another-app-request"]
        try check(CareReminder.namespace(directory: root.appendingPathComponent("child/..")) == rootPrefix,
                  "Equivalent paths use stable notification namespace")
        try check(CareReminder.isLegacyRequest(CareReminder.prefix + UUID().uuidString), "Legacy UUID recognized")
        try check(!CareReminder.isLegacyRequest(rootPrefix + UUID().uuidString), "Scoped request is not legacy")
        let model = CareModel(directory: root, ownsSession: true, reminderCenter: center,
            workspaceNotifications: events, chooseDemand: { .food }, automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        try check(model.reminderMode == .gentle, "New sessions default to gentle reminders")
        model.setReminderMode(.strong)
        let preferenceCopy = CareModel(directory: root, ownsSession: false, reminderCenter: TestCenter(),
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false)
        try check(preferenceCopy.reminderMode == .strong, "Reminder preference persists in this isolated directory")
        let other = CareModel(directory: root.appendingPathComponent("other"), ownsSession: false,
            reminderCenter: TestCenter(), workspaceNotifications: NotificationCenter(), automaticallyTicks: false)
        try check(other.reminderMode == .gentle, "Separate directory has independent reminder preference")
        preferenceCopy.setReminderMode(.gentle)
        try check(preferenceCopy.reminderMode == .strong, "Secondary session cannot write preferences")
        let owner = UUID()
        model.start(for: owner)
        model.start(for: owner)
        try await until { center.additions == 1 && center.queried }
        try check(model.workTime == "05:00" && center.requests.values.first == 300, "App starts one five-minute reminder despite repeated start")
        try check(!center.removed.contains("another-app-request"), "Startup cleanup cannot touch other apps")
        try check(center.removed.contains(rootPrefix + "stale"), "Startup cleans stale own requests")
        clock.advance(60); model.refresh()
        try check(model.workTime == "04:00", "App countdown uses injected elapsed clock")
        model.pause()
        clock.advance(10); model.refresh()
        try check(model.workTime == "04:00" && center.requests.isEmpty, "Paused countdown freezes and reminder is removed")
        model.resume()
        try await until { center.additions == 2 }
        try check(center.requests.values.first == 240, "Resume schedules only remaining work")

        // These are the exact observers installed by the App, with an isolated
        // notification center. They verify event handling, not OS event delivery.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            events.post(name: name, object: nil)
            try check(model.cycle.phase == .paused && center.requests.isEmpty, "System event adapter pauses and cancels")
            clock.advance(3600); model.refresh()
            try check(model.workTime == "04:00", "System pause cannot accumulate away time")
            let previous = center.additions
            model.resume()
            try await until { center.additions == previous + 1 }
        }
        clock.advance(240); model.refresh()
        try check(model.cycle.phase == .needsCare && model.workTime == "00:00", "Model becomes due at exact deadline")
        let notice = model.completionNoticeID
        try check(notice == model.cycle.demandID, "Exact completion produces attention event")
        model.acknowledgeCompletion(); model.refresh()
        try check(model.completionNoticeID == nil && model.cycle.phase == .needsCare,
                  "Acknowledgment stops presentation without clearing need; refresh does not replay")
        events.post(name: NSWorkspace.willSleepNotification, object: nil)
        try check(model.cycle.phase == .paused && center.requests.isEmpty, "Due care need also pauses")
        model.resume()
        try check(model.completionNoticeID == nil, "Resume never replays completion alert")
        try check(model.cycle.phase == .needsCare, "Resume preserves due need without granting new work")
        model.rest(.food)
        let deadline = model.cycle.restDeadline
        events.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        clock.advance(300); model.refresh()
        try check(model.cycle.phase == .restComplete && model.cycle.restDeadline == deadline, "Rest completes across system pause event")
        let receipt = model.cycle.completedReceipt
        try check(receipt?.petID == owner && center.requests.isEmpty, "Rest keeps correct owner and no reminder")
        model.stop()
        try check(model.cycle.phase == .restComplete, "Cannot discard an uncommitted growth receipt")
        model.stop(afterSaving: receipt)
        try check(model.cycle.phase == .idle, "Explicit receipt acknowledgment permits stop")

        model.start(for: owner)
        try await until { !center.requests.isEmpty }
        clock.advance(25); model.refresh()
        model.prepareToQuit()
        try check(center.requests.isEmpty, "Quit cancels active reminder")
        let saved = try CareStore(directory: root).load()!
        try check(saved.phase == .paused && saved.remainingWork == 275, "Quit persists paused remaining time")
        clock.advance(86400)
        let reopened = CareModel(directory: root, ownsSession: true, reminderCenter: TestCenter(),
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        try check(reopened.cycle.phase == .paused && reopened.workTime == "04:35", "Cold reopen excludes offline work")

        let beforeSecondary = try Data(contentsOf: root.appendingPathComponent("care.json"))
        let secondaryCenter = TestCenter(), secondaryEvents = NotificationCenter()
        let secondary = CareModel(directory: root, ownsSession: false, reminderCenter: secondaryCenter,
            workspaceNotifications: secondaryEvents, automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        secondary.start(for: owner); secondary.resume(); secondary.reset(); secondary.prepareToQuit()
        secondaryEvents.post(name: NSWorkspace.willSleepNotification, object: nil)
        clock.advance(1000); secondary.refresh()
        try check(try Data(contentsOf: root.appendingPathComponent("care.json")) == beforeSecondary,
                  "Secondary model cannot mutate stored timer")
        try check(secondaryCenter.additions == 0 && !secondaryCenter.queried && secondaryCenter.removed.isEmpty,
                  "Secondary cannot schedule or clean primary notifications")

        let deniedCenter = TestCenter(); deniedCenter.status = .denied
        let denied = CareModel(directory: root.appendingPathComponent("denied"), ownsSession: true,
            reminderCenter: deniedCenter, workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        denied.start(for: UUID())
        try await until { denied.notificationHint.contains("未開啟") }
        clock.advance(300); denied.refresh()
        try check(denied.cycle.phase == .needsCare && deniedCenter.requests.isEmpty,
                  "Notification denial still reaches in-app care prompt")
        let brokenFolder = root.appendingPathComponent("future")
        try FileManager.default.createDirectory(at: brokenFolder, withIntermediateDirectories: true)
        let future = Data("{\"version\":99,\"newFormat\":true}".utf8)
        let petBytes = Data("protected real-pet stand-in".utf8)
        try future.write(to: brokenFolder.appendingPathComponent("care.json"))
        try petBytes.write(to: brokenFolder.appendingPathComponent("pet.json"))
        let blocked = CareModel(directory: brokenFolder, ownsSession: true, reminderCenter: TestCenter(),
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        blocked.start(for: UUID()); blocked.stop(); blocked.prepareToQuit()
        try check(blocked.needsReset && (try Data(contentsOf: brokenFolder.appendingPathComponent("care.json"))) == future,
                  "Future timer blocks model actions without overwrite")
        blocked.reset()
        let originals = try FileManager.default.contentsOfDirectory(at: brokenFolder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("care-previous-") }
        try check(!blocked.needsReset && blocked.cycle.workDuration == 300 && blocked.workTime == "05:00",
                  "Explicit reset preserves existing App default")
        try check(originals.count == 1 && (try Data(contentsOf: originals[0])) == future,
                  "Reset preserves exact unsupported timer")
        try check(try Data(contentsOf: brokenFolder.appendingPathComponent("pet.json")) == petBytes,
                  "Model recovery never modifies pet data")
        // Multiple owners in separate data folders share the same macOS bundle
        // notification center. QA startup must not cancel a real user's timer.
        let shared = TestCenter()
        shared.extraIDs = []
        let folderA = root.appendingPathComponent("owner-a")
        let folderB = root.appendingPathComponent("owner-b")
        let ownerA = CareModel(directory: folderA, ownsSession: true, reminderCenter: shared,
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        ownerA.start(for: UUID())
        try await until { shared.requests.count == 1 }
        let requestA = shared.requests.keys.first!
        let staleB = CareReminder.namespace(directory: folderB) + "stale"
        let legacyID = CareReminder.prefix + UUID().uuidString
        shared.extraIDs = [staleB, legacyID]
        let ownerB = CareModel(directory: folderB, ownsSession: true, reminderCenter: shared,
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        try await until { shared.removed.contains(staleB) }
        try check(shared.requests[requestA] != nil, "QA startup must preserve another data directory's active reminder")
        try check(!shared.removed.contains(legacyID), "QA cannot clean an old production reminder")
        ownerB.start(for: UUID())
        try await until { shared.requests.count == 2 }
        ownerB.pause()
        try check(shared.requests.count == 1 && shared.requests[requestA] != nil,
                  "QA pause cannot remove production reminder")
        ownerA.stop()
        try check(shared.requests.isEmpty, "Each owner can remove only its own reminder")
        // User-selected durations persist and drive both reminder and rest deadlines.
        let customRoot = root.appendingPathComponent("custom")
        let customClock = TestClock(), customCenter = TestCenter()
        let custom = CareModel(directory: customRoot, ownsSession: true, reminderCenter: customCenter,
            workspaceNotifications: NotificationCenter(), chooseDemand: { .food }, automaticallyTicks: false,
            now: { customClock.date }, uptime: { customClock.uptime })
        for (work, rest) in [(10, 5), (20, 10), (30, 15), (60, 5), (7, 3), (1, 1440), (1440, 1)] {
            try check(custom.configureSchedule(workMinutes: String(work), breakMinutes: String(rest)) == nil,
                      "Presets and custom minute pairs are accepted")
            custom.start(for: owner)
            let additions = customCenter.additions
            try await until { customCenter.additions > additions }
            try check(customCenter.requests.values.first == Double(work * 60), "Reminder uses selected work duration")
            let snapshot = custom.cycle
            try check(custom.configureSchedule(workMinutes: "1", breakMinutes: "1") != nil && custom.cycle == snapshot,
                      "Active work cannot be changed through preferences")
            customClock.advance(Double(work * 60)); custom.refresh()
            try check(custom.cycle.phase == .needsCare, "Custom work becomes due at selected deadline")
            custom.rest(.food)
            try check(custom.cycle.restRemaining(now: customClock.date) == Double(rest * 60), "Rest uses selected minutes")
            customClock.advance(Double(rest * 60)); custom.refresh()
            let completed = custom.cycle.completedReceipt
            try check(completed != nil, "Custom rest produces growth receipt")
            try check(custom.configureSchedule(workMinutes: "7", breakMinutes: "3") != nil && custom.cycle.completedReceipt == completed,
                      "Settings cannot discard unsaved growth")
            try check(custom.configureSchedule(workMinutes: "7", breakMinutes: "3", afterSaving: completed) == nil,
                      "Saved growth permits next-round settings")
        }
        for input in ["", "0", "-1", "1.5", "abc", "1441", "999999999999999999999999"] {
            let snapshot = custom.cycle
            try check(custom.configureSchedule(workMinutes: input, breakMinutes: "5") != nil && custom.cycle == snapshot,
                      "Invalid work cannot mutate settings")
            try check(custom.configureSchedule(workMinutes: "10", breakMinutes: input) != nil && custom.cycle == snapshot,
                      "Invalid rest cannot mutate settings")
        }
        custom.start(for: owner)
        customClock.advance(13); custom.prepareToQuit()
        let customReopened = CareModel(directory: customRoot, ownsSession: true, reminderCenter: TestCenter(),
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
            now: { customClock.date.addingTimeInterval(86400) }, uptime: { customClock.uptime })
        try check(customReopened.cycle.workDuration == 420 && customReopened.cycle.breakDuration == 180 &&
                  customReopened.cycle.remainingWork == 407 && customReopened.cycle.phase == .paused,
                  "Reopen preserves custom preferences and paused countdown without offline charge")
        let customBytes = try Data(contentsOf: customRoot.appendingPathComponent("care.json"))
        let customSecondary = CareModel(directory: customRoot, ownsSession: false, reminderCenter: TestCenter(),
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false)
        try check(customSecondary.configureSchedule(workMinutes: "60", breakMinutes: "15") != nil &&
                  (try Data(contentsOf: customRoot.appendingPathComponent("care.json"))) == customBytes,
                  "Secondary session cannot change preferences")
        let nextFolder = root.appendingPathComponent("next-round")
        let nextClock = TestClock()
        let nextModel = CareModel(directory: nextFolder, ownsSession: true, reminderCenter: TestCenter(),
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
            now: { nextClock.date }, uptime: { nextClock.uptime })
        nextModel.start(for: owner); nextClock.advance(20); nextModel.rest(.food)
        let activeDeadline = nextModel.cycle.restDeadline
        let activeRestID = nextModel.cycle.restID
        try check(nextModel.canConfigureSchedule && nextModel.configureSchedule(workMinutes: "20", breakMinutes: "10") == nil,
                  "Settings can save next round during an active rest")
        try check(nextModel.cycle.restDeadline == activeDeadline && nextModel.cycle.restID == activeRestID && nextModel.restTime == "05:00",
                  "Saving next round cannot alter current rest deadline, ID or countdown")
        let reopenedRest = CareModel(directory: nextFolder, ownsSession: true, reminderCenter: TestCenter(),
            workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
            now: { nextClock.date }, uptime: { nextClock.uptime })
        try check(reopenedRest.cycle.configuredWorkDuration == 1200 && reopenedRest.cycle.configuredBreakDuration == 600 &&
                  reopenedRest.cycle.restDeadline == activeDeadline, "Restart retains pending preferences and original active rest")
        // The form is open while resting; its button click itself crosses the deadline.
        nextClock.advance(300)
        try check(nextModel.configureSchedule(workMinutes: "30", breakMinutes: "15") != nil && nextModel.cycle.phase == .restComplete,
                  "At deadline, configuration must wait for unsaved growth")
        let currentReceipt = nextModel.cycle.completedReceipt
        try check(currentReceipt != nil && nextModel.cycle.restID == activeRestID &&
                  nextModel.cycle.configuredWorkDuration == 1200, "Boundary failure preserves receipt and prior pending values")
        nextModel.start(for: owner)
        try check(nextModel.cycle.completedReceipt == currentReceipt && nextModel.cycle.phase == .restComplete,
                  "Pending settings never bypass growth-save guard")
        nextModel.start(for: owner, afterSaving: currentReceipt)
        try check(nextModel.cycle.remainingWork == 1200 && nextModel.cycle.breakDuration == 600,
                  "Manual start after saved receipt uses next round preferences")
        nextModel.pause()
        let pausedSchedule = nextModel.cycle
        try check(!nextModel.canConfigureSchedule && nextModel.configureSchedule(workMinutes: "1", breakMinutes: "1") != nil &&
                  nextModel.cycle == pausedSchedule, "Paused work settings remain disabled")
        nextModel.stop()
        try check(nextModel.configureSchedule(workMinutes: "1", breakMinutes: "1") == nil, "Stopped work can be configured")
        nextModel.start(for: owner); nextModel.rest(.walk)
        let timerFile = nextFolder.appendingPathComponent("care.json")
        let priorTimerBytes = try Data(contentsOf: timerFile)
        try FileManager.default.moveItem(at: timerFile, to: nextFolder.appendingPathComponent("care-preserved.json"))
        try FileManager.default.createDirectory(at: timerFile, withIntermediateDirectories: false)
        try check(nextModel.configureSchedule(workMinutes: "40", breakMinutes: "10") != nil && nextModel.needsReset,
                  "Pending preference write failure reports error and blocks further changes")
        try check(try Data(contentsOf: nextFolder.appendingPathComponent("care-preserved.json")) == priorTimerBytes,
                  "Write failure cannot overwrite previous isolated timer snapshot")
        // The visible-view handshake is cancellable; delayed UI callbacks cannot
        // commit care after stop, lock, reset or quit.
        var committedPresentation = false
        var presentationReveals = 0
        custom.revealForHatching = { presentationReveals += 1 }
        for action in ["stop", "lock", "quit"] {
            custom.prepareHatchingPresentation { committedPresentation = true }
            let request = custom.hatchingPresentationID!
            if action == "stop" { custom.stop() }
            else if action == "lock" { custom.pauseForSafety() }
            else { custom.prepareToQuit() }
            custom.confirmHatchingPresentation(request)
            try check(!committedPresentation && custom.hatchingPresentationID == nil,
                      "Cancelled first-care presentation cannot save from a stale callback")
        }
        try check(presentationReveals == 3, "Each preparation requests one reveal")
        print("PASS CareFlowChecks: shared App model countdown/pause/resume, duplicate start, notification cleanup, system event adapters, due/rest, receipt guard, quit/reopen, secondary isolation and denial fallback")
    }
}
