import Foundation
import CareCore

@main
struct CareChecks {
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw NSError(domain: "CareChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1000)
        try require(CountdownDisplay.text(seconds: 300) == "05:00", "Five-minute starting display")
        try require(CountdownDisplay.text(seconds: 299.01) == "05:00", "Round up fractional remaining seconds")
        try require(CountdownDisplay.text(seconds: 299) == "04:59", "Countdown changes at second boundary")
        try require(CountdownDisplay.text(seconds: 0.1) == "00:01", "Never show zero before actually due")
        try require(CountdownDisplay.text(seconds: -1) == "00:00", "Countdown clamps at zero")
        var short = try CareCycle()
        let owner = UUID()
        short.bind(to: owner)
        short.start()
        short.advance(workElapsed: 60, now: now)
        short.pause()
        try short.setWorkDuration(300)
        try require(short.phase == .paused && short.remainingWork == 300 && short.petID == owner,
                    "Short verification duration preserves paused work and owner")
        short.resume()
        short.advance(workElapsed: 299, now: now)
        try require(short.phase == .working && short.remainingWork == 1, "Five-minute round stays working before zero")
        short.advance(workElapsed: 1, now: now)
        try require(short.phase == .needsCare, "Five-minute round becomes due at zero")
        short.rest(.food, now: now)
        short.advance(workElapsed: 0, now: now.addingTimeInterval(300))
        let receipt = short.completedReceipt
        try short.setWorkDuration(1500)
        try require(short.completedReceipt == receipt && short.phase == .restComplete,
                    "Duration changes preserve completed growth receipt")
        _ = try short.validated()
        var idle = try CareCycle()
        try idle.setWorkDuration(300)
        try require(idle.remainingWork == 300 && idle.breakDuration == 300, "Only work shortened; rest remains five minutes")
        let unchanged = idle
        do { try idle.setWorkDuration(0); throw CareError.unsupportedVersion }
        catch CareError.invalidState { }
        try require(idle == unchanged, "Invalid duration does not mutate cycle")
        var c = try CareCycle(workDuration: 60, breakDuration: 20)
        c.start(demand: .food); c.start()
        c.advance(workElapsed: 59, now: now)
        try require(c.phase == .working && c.remainingWork == 1, "Elapsed work must not count callback invocations")
        c.advance(workElapsed: 1, now: now)
        try require(c.phase == .needsCare, "Exactly due at zero")
        c.advance(workElapsed: 3600, now: now)
        try require(c.phase == .needsCare, "Due is sticky, never auto-rests")
        c.pause()
        try require(c.phase == .paused && c.remainingWork == 0, "A pending care need must be pausable")
        c.advance(workElapsed: 99999, now: now.addingTimeInterval(99999))
        c.resume()
        try require(c.phase == .needsCare && c.remainingWork == 0, "Resuming a pending need must not grant free work time")
        var offlineNeed = c
        offlineNeed.recoverAfterLaunch(now: now.addingTimeInterval(86400 * 30))
        try require(offlineNeed.phase == .paused && offlineNeed.remainingWork == 0, "Offline pending care recovers paused")
        offlineNeed.resume()
        try require(offlineNeed.phase == .needsCare, "A month offline cannot clear or amplify a pending need")
        c.snooze(); try require(c.remainingWork == 0 && c.phase == .needsCare, "A need cannot be postponed for extra work time")
        c.pause(); c.advance(workElapsed: 9000, now: now)
        try require(c.phase == .paused && c.remainingWork == 0, "Pause excludes all elapsed work")
        c.resume(); c.rest(.food, now: now)
        let deadline = c.restDeadline
        c.rest(.walk, now: now.addingTimeInterval(10))
        try require(c.restDeadline == deadline && c.activity == .food, "Repeated interaction cannot restart rest")
        c.advance(workElapsed: 10, now: now.addingTimeInterval(19))
        try require(c.phase == .resting && c.restRemaining(now: now.addingTimeInterval(19)) == 1, "Rest uses real deadline")
        c.advance(workElapsed: 1, now: now.addingTimeInterval(3600))
        try require(c.phase == .restComplete, "Late return is safe and stays complete")
        c.advance(workElapsed: 9000, now: now.addingTimeInterval(7200))
        try require(c.phase == .restComplete, "Never automatically starts another work cycle")
        c.start(); c.advance(workElapsed: 10, now: now); c.recoverAfterLaunch(now: now.addingTimeInterval(10000))
        try require(c.phase == .paused && c.remainingWork == 50, "Offline time is not working time")
        c.resume(); c.rest(.walk, now: now)
        var restored = try JSONDecoder().decode(CareCycle.self, from: JSONEncoder().encode(c)).validated()
        restored.recoverAfterLaunch(now: now.addingTimeInterval(30))
        try require(restored.phase == .restComplete && restored.activity == .walk, "Rest recovers by deadline")
        restored.stop(); try require(restored.phase == .idle && restored.restDeadline == nil, "Stop clears session")
        var invalid = try CareCycle()
        invalid.start(); invalid.advance(workElapsed: .infinity, now: now)
        invalid.advance(workElapsed: -30, now: now)
        try require(invalid.remainingWork == 1500, "Invalid deltas never change work time")
        let valid = try invalid.validated()
        try require(valid == invalid, "Valid cycle validates")
        var movedClock = try CareCycle()
        movedClock.start()
        movedClock.advance(workElapsed: 10, now: now.addingTimeInterval(-86400))
        movedClock.advance(workElapsed: 10, now: now.addingTimeInterval(86400))
        try require(movedClock.remainingWork == 1480, "Calendar changes do not change elapsed work")
        var badState = try JSONSerialization.jsonObject(with: JSONEncoder().encode(movedClock)) as! [String: Any]
        badState["phase"] = "needsCare"
        let badData = try JSONSerialization.data(withJSONObject: badState)
        do {
            _ = try JSONDecoder().decode(CareCycle.self, from: badData).validated()
            throw NSError(domain: "CareChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Inconsistent phase must be rejected"])
        } catch CareError.invalidState { }
        var next = try CareCycle(workDuration: 3600, breakDuration: 600)
        next.bind(to: owner); next.start(); next.advance(workElapsed: 20, now: now)
        next.rest(.walk, now: now)
        let currentRest = next
        try next.configure(workMinutes: 1, breakMinutes: 2)
        try require(next.restDeadline == currentRest.restDeadline && next.restID == currentRest.restID &&
                    next.remainingWork == currentRest.remainingWork && next.workDuration == 3600 && next.breakDuration == 600,
                    "Early rest keeps current durations, unused work, deadline and receipt identity")
        try require(next.configuredWorkDuration == 60 && next.configuredBreakDuration == 120,
                    "Pending preferences are available to settings")
        next = try JSONDecoder().decode(CareCycle.self, from: JSONEncoder().encode(next)).validated()
        try require(next.nextWorkDuration == 60 && next.restRemaining(now: now) == 600,
                    "Pending settings and current rest independently round-trip")
        let invalidNext = next
        do { try next.configure(workMinutes: 0, breakMinutes: 2); throw CareError.unsupportedVersion }
        catch CareError.invalidState { }
        try require(next == invalidNext, "Invalid pending preferences never change rest")
        var legacyRest = try JSONSerialization.jsonObject(with: JSONEncoder().encode(currentRest)) as! [String: Any]
        legacyRest.removeValue(forKey: "restID")
        var legacyNext = try JSONDecoder().decode(CareCycle.self, from: JSONSerialization.data(withJSONObject: legacyRest))
        var originalLegacy = legacyNext
        try legacyNext.configure(workMinutes: 20, breakMinutes: 15)
        originalLegacy.advance(workElapsed: 0, now: now.addingTimeInterval(600))
        legacyNext.advance(workElapsed: 0, now: now.addingTimeInterval(600))
        try require(legacyNext.completedReceipt == originalLegacy.completedReceipt,
                    "Legacy receipt derived from break duration remains identical after preference edits")
        next.advance(workElapsed: 0, now: now.addingTimeInterval(600))
        try require(next.completedReceipt?.completedAt == currentRest.restDeadline,
                    "Current rest completes at its original deadline")
        next.start()
        try require(next.remainingWork == 60 && next.workDuration == 60 && next.breakDuration == 120 &&
                    next.nextWorkDuration == nil, "Next manual work promotes pending preferences once")
        next.pause()
        let pausedNext = next
        do { try next.configure(workMinutes: 10, breakMinutes: 5); throw CareError.unsupportedVersion }
        catch CareError.invalidState { }
        try require(next == pausedNext, "Paused work remains protected")
        var cancelledRest = invalidNext
        cancelledRest.stop()
        try require(cancelledRest.workDuration == 60 && cancelledRest.breakDuration == 120 && cancelledRest.remainingWork == 60,
                    "Ending rest keeps saved preferences for next work")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Tomatogotchi-Care-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let petFile = root.appendingPathComponent("pet.json")
        let petBytes = Data("untouched pet fixture".utf8)
        try petBytes.write(to: petFile)
        let store = CareStore(directory: root)
        try require(try store.load() == nil, "Fresh timer has no stored session")
        try store.save(c)
        try require(try store.load() == c, "Timer round-trips independently")
        let future = Data("{\"version\":99,\"newFormat\":true}".utf8)
        let timerFile = root.appendingPathComponent("care.json")
        try future.write(to: timerFile)
        do { _ = try store.load(); throw CareError.invalidState }
        catch CareError.unsupportedVersion { }
        do { try store.save(c); throw CareError.invalidState }
        catch CareError.unsupportedVersion { }
        try require(try Data(contentsOf: timerFile) == future, "Future timer is not silently overwritten")
        _ = try store.reset()
        try require(try store.load()?.phase == .idle, "Explicit reset starts idle")
        let copies = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("care-previous-") }
        try require(copies.count == 1 && (try Data(contentsOf: copies[0])) == future, "Reset preserves original timer")
        try require(try Data(contentsOf: petFile) == petBytes, "Timer reset cannot modify pet bytes")
        print("PASS CareChecks: 25/5 defaults, elapsed boundaries, due sticky, snooze, pause/resume, single rest, real deadline, late return, offline recovery, stop, invalid deltas")
    }
}
