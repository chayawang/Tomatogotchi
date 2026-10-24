import Foundation
import AppKit
import PetCore
import CareCore
import CareFlow
import AdoptionFlow

@MainActor
final class Clock {
    var date = Date(timeIntervalSince1970: 1000)
    var uptime: TimeInterval = 100
    func advance(_ n: TimeInterval) { date.addTimeInterval(n); uptime += n }
}
@MainActor
final class SilentCenter: CareReminderCenter {
    func permission() async -> ReminderPermission { .denied }
    func authorize() async throws -> Bool { false }
    func add(id: String, delay: TimeInterval) async throws { }
    func remove(id: String) { }
}
@main @MainActor
struct SurvivalChecks {
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw NSError(domain: "SurvivalChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<20000 { if condition() { return }; await Task.yield() }
        throw NSError(domain: "SurvivalChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Async state did not settle"])
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("survival-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1000), id = UUID()
        let displayClock = Clock()
        let displayCare = CareModel(directory: root.appendingPathComponent("countdown"), ownsSession: true,
            reminderCenter: SilentCenter(), workspaceNotifications: NotificationCenter(), lockNotifications: NotificationCenter(),
            chooseDemand: { .food }, automaticallyTicks: false, now: { displayClock.date }, uptime: { displayClock.uptime })
        displayCare.start(for: id); displayClock.advance(300); displayCare.refresh()
        try check(displayCare.needTime == "03:00", "Demand begins with a visible 03:00 countdown")
        displayClock.advance(1); displayCare.refresh(); try check(displayCare.needTime == "02:59", "Demand display ticks down")
        displayCare.pause(); displayClock.advance(600); displayCare.refresh()
        try check(displayCare.needTime == "02:59", "Paused demand freezes its countdown")
        displayCare.resume(); displayClock.advance(179); displayCare.refresh()
        try check(displayCare.needTime == "03:00" && displayCare.cycle.needProgress?.steps == 1, "Countdown reset and penalty share the same clock")
        for demand in [CareActivity.food, .walk] {
            var cycle = try CareCycle(workDuration: 10)
            cycle.bind(to: id); cycle.start(demand: demand)
            cycle.advance(workElapsed: 189.999, now: date)
            try check(cycle.needProgress?.steps == 0, "Work portion must not count toward first penalty")
            try check(CountdownDisplay.text(seconds: cycle.nextPenaltyRemaining) == "00:01", "Countdown shows the final fractional second before a penalty")
            cycle.advance(workElapsed: 0.001, now: date)
            try check(cycle.needProgress?.steps == 1, "First penalty at exactly 180 effective seconds")
            cycle.advance(workElapsed: 180, now: date)
            try check(cycle.needProgress?.steps == 2, "Second penalty at 360 seconds")
            try check(CountdownDisplay.text(seconds: cycle.nextPenaltyRemaining) == "03:00", "Each penalty resets the displayed countdown for the next cell")
            let need = cycle.needProgress!
            cycle.pause(); cycle.advance(workElapsed: 86400, now: date.addingTimeInterval(86400))
            try check(cycle.needProgress == need, "Pause freezes need ID, kind and fractional progress")
            let bytes = try JSONEncoder().encode(cycle)
            var reopened = try JSONDecoder().decode(CareCycle.self, from: bytes)
            reopened.recoverAfterLaunch(now: date.addingTimeInterval(864000))
            try check(reopened.needProgress == need && reopened.phase == .paused, "Offline reopen never charges or redraws need")
            reopened.resume(); reopened.rest(demand == .food ? .walk : .food, now: date)
            try check(reopened.phase == .needsCare, "Only the selected need can be answered")
            reopened.rest(demand, now: date)
            try check(reopened.phase == .resting && reopened.activity == demand, "Correct care enters one rest")

            let folder = root.appendingPathComponent(demand.rawValue), repo = PetRepository(directory: folder)
            _ = try await repo.adopt(Pet(id: id, name: "保留我", now: date))
            var pet = try await repo.applyNeed(petID: id, needID: need.id, food: demand == .food, steps: 2, responding: false, now: date)
            try check(pet.growth.health == (demand == .food ? 3 : 5) && pet.growth.mood == (demand == .walk ? 3 : 5), "Only corresponding vital loses two cells")
            pet = try await repo.applyNeed(petID: id, needID: need.id, food: demand == .food, steps: 2, responding: false, now: date)
            try check((demand == .food ? pet.growth.health : pet.growth.mood) == 3, "Replay cannot double-charge")
            let other = PetRepository(directory: folder)
            async let a = repo.applyNeed(petID: id, needID: need.id, food: demand == .food, steps: 2, responding: true, now: date)
            async let b = other.applyNeed(petID: id, needID: need.id, food: demand == .food, steps: 2, responding: true, now: date)
            _ = try await (a,b)
            pet = try await repo.load()!
            try check((demand == .food ? pet.growth.health : pet.growth.mood) == 4, "Concurrent response recovers only one cell")
            pet = try await repo.applyNeed(petID: id, needID: need.id, food: demand == .food, steps: 5, responding: false, now: date)
            try check(pet.growth.stage == .egg, "Late stale demand cannot kill a responded pet")
            let nextID = UUID()
            pet = try await repo.applyNeed(petID: id, needID: nextID, food: demand == .food, steps: 4, responding: true, now: date)
            try check(pet.growth.stage == .departed && pet.growth.deathReason == (demand == .food ? .hunger : .sadness), "Zero vital dies before response; eggs follow latest survival rule")
            let dead = pet
            pet = try await repo.applyNeed(petID: id, needID: nextID, food: demand == .food, steps: 4, responding: true, now: date)
            try check(pet == dead, "Response cannot revive")
            let fresh = try await repo.farewell(id: id, replacement: Pet())
            do {
                _ = try await repo.applyNeed(petID: id, needID: nextID, food: true, steps: 5, responding: false, now: date)
                throw CareError.invalidState
            } catch PetError.stalePet { }
            let afterReplacement = try await repo.load()
            try check(afterReplacement == fresh, "Old need cannot charge replacement pet")
        }
        // Shared App coordinator, not a duplicate simulation of the UI code.
        let folder = root.appendingPathComponent("app"), repo = PetRepository(directory: folder)
        let initial = try await repo.adopt(Pet(name: "實機模型"))
        let model = AdoptionModel(repository: repo)
        model.load(); try await until { model.screen == .home }
        let clock = Clock(), events = NotificationCenter(), locks = NotificationCenter()
        let care = CareModel(directory: folder, ownsSession: true, reminderCenter: SilentCenter(),
            workspaceNotifications: events, lockNotifications: locks, chooseDemand: { .walk }, automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        CareActions.connect(model: model, care: care)
        try check(care.startTitle == "開始工作", "No ambiguous 5/5 or evolution choice")
        care.start(for: initial.id)
        clock.advance(300 + 179); care.refresh()
        try check(model.pet?.growth.mood == 5, "No loss one second before grace boundary")
        clock.advance(1); CareActions.respond(model: model, care: care)
        try await until { !model.saving && care.cycle.phase == .resting }
        try check(model.pet?.growth.mood == 5, "Boundary click atomically charges then restores exactly once")
        clock.advance(300); care.refresh()
        model.recordRest(care.cycle.completedReceipt!); try await until { !model.saving }
        care.stop(afterSaving: care.cycle.completedReceipt)
        care.start(for: initial.id); clock.advance(300+100); care.refresh()
        let before = care.cycle.needProgress
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            // A delayed inactivity event cannot count its delayed interval.
            clock.advance(86400); events.post(name: name, object: nil); care.refresh()
            try check(care.cycle.needProgress == before, "System event freezes rather than charging delayed inactive interval")
            care.resume()
        }
        clock.advance(86400); locks.post(name: CareModel.screenLocked, object: nil); care.refresh()
        try check(care.cycle.needProgress == before && care.cycle.phase == .paused, "Lock adapter freezes and requires explicit resume")
        clock.advance(86400); care.prepareToQuit()
        let reopened = CareModel(directory: folder, ownsSession: true, reminderCenter: SilentCenter(),
            workspaceNotifications: events, lockNotifications: locks, automaticallyTicks: false,
            now: { clock.date }, uptime: { clock.uptime })
        try check(reopened.cycle.needProgress == before && reopened.cycle.phase == .paused, "Quit/reopen preserves progress without offline penalty")
        care.resume(); clock.advance(80); care.refresh(); try await until { !model.saving }
        try check(model.pet?.growth.mood == 4, "App coordinator applies one mood cell at 180 seconds")
        // Fail a backup write; timer pauses and retry uses same need ID.
        let backup = folder.appendingPathComponent("pet.backup.json")
        try FileManager.default.removeItem(at: backup)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        clock.advance(180); care.refresh(); try await until { !model.saving && model.progressError != nil }
        try check(care.cycle.phase == .paused && model.pet?.growth.mood == 4, "Storage failure freezes and leaves pet unchanged")
        try FileManager.default.removeItem(at: backup)
        CareActions.respond(model: model, care: care); try await until { !model.saving && care.cycle.phase == .resting }
        try check(model.pet?.growth.mood == 4, "Retry commits one pending loss plus one response, no duplication")
        // A timer write failure must not allow a successful care response.
        let timerFile = folder.appendingPathComponent("care.json")
        try FileManager.default.removeItem(at: timerFile)
        try FileManager.default.createDirectory(at: timerFile, withIntermediateDirectories: false)
        let stablePet = model.pet
        care.stop(afterSaving: care.cycle.completedReceipt)
        try check(care.needsReset, "Timer save failure blocks further time and requires explicit preserved reset")
        CareActions.respond(model: model, care: care)
        try check(model.pet == stablePet && !model.saving, "Timer failure cannot acknowledge or recover pet care")
        try FileManager.default.removeItem(at: timerFile)
        care.reset()
        try check(!care.needsReset && care.cycle.phase == .idle, "Explicit timer reset safely releases storage failure")
        // Version migration, exact original and strict v3 required fields.
        let legacyFolder = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        let file = legacyFolder.appendingPathComponent("pet.json")
        var v2 = try JSONSerialization.jsonObject(with: JSONEncoder().encode(initial)) as! [String: Any]
        v2["saveVersion"] = 2
        var growth = v2["growth"] as! [String: Any]
        growth["species"] = PetSpecies.forPet(initial.id).rawValue
        for key in ["health", "mood", "needs", "deathReason"] { growth.removeValue(forKey: key) }
        v2["growth"] = growth
        let oldBytes = try JSONSerialization.data(withJSONObject: v2)
        try oldBytes.write(to: file)
        let legacyRepo = PetRepository(directory: legacyFolder)
        let migrated = try await legacyRepo.load()!
        try check(migrated.id == initial.id && migrated.growth.health == 5 && (try Data(contentsOf: file)) == oldBytes, "v2 read preserves identity and original bytes, no retroactive loss")
        _ = try await legacyRepo.applyNeed(petID: initial.id, needID: UUID(), food: true, steps: 1, responding: false, now: date)
        try check(try Data(contentsOf: legacyFolder.appendingPathComponent("pet-v2-original-\(initial.id).json")) == oldBytes, "First v3 mutation preserves exact original")
        var broken = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var brokenGrowth = broken["growth"] as! [String: Any]; brokenGrowth.removeValue(forKey: "health"); broken["growth"] = brokenGrowth
        try JSONSerialization.data(withJSONObject: broken).write(to: file)
        do { _ = try await legacyRepo.load(); throw CareError.invalidState } catch is DecodingError { } catch PetError.damagedSave { }
        // Full shared App coordinator flow for every species and each real demand.
        for species in PetSpecies.allCases {
            for activity in [CareActivity.walk, .food] {
                let directory = root.appendingPathComponent("five-species-\(species.rawValue)-\(activity.rawValue)")
                let repository = PetRepository(directory: directory)
                var pet = try Pet(name: "Five species QA", species: species)
                for n in 0..<12 { try pet.completeRest(id: "seed-\(n)", food: true, now: date) }
                _ = try await repository.adopt(pet)
                let adoption = AdoptionModel(repository: repository)
                adoption.load(); try await until { adoption.screen == .home }
                let clock = Clock()
                let timer = CareModel(directory: directory, ownsSession: true, reminderCenter: SilentCenter(),
                    workspaceNotifications: NotificationCenter(), lockNotifications: NotificationCenter(),
                    chooseDemand: { activity }, automaticallyTicks: false, now: { clock.date }, uptime: { clock.uptime })
                CareActions.connect(model: adoption, care: timer)
                try check(timer.configureSchedule(workMinutes: "1", breakMinutes: "1") == nil, "Every species uses custom timing")
                timer.start(for: pet.id)
                clock.advance(60); timer.refresh()
                try await until { !adoption.saving }
                try check(timer.cycle.phase == .needsCare && timer.cycle.demand == activity, "Correct real need at work deadline")
                CareActions.respond(model: adoption, care: timer)
                try await until { timer.cycle.phase == .resting && !adoption.saving }
                try check(timer.cycle.activity == activity && timer.cycle.restRemaining(now: clock.date) == 60,
                          "Shared response starts the selected real rest")
                clock.advance(60); timer.refresh()
                let receipt = timer.cycle.completedReceipt!
                adoption.recordRest(receipt)
                try await until { adoption.hasSavedRest(receipt) && !adoption.saving }
                adoption.recordRest(receipt)
                try await until { !adoption.saving }
                try check(adoption.pet!.growth.completedRests.count == 13 && adoption.pet!.growth.species == species,
                          "Each species receives exactly one growth receipt without identity change")
                timer.start(for: pet.id, afterSaving: receipt)
                timer.prepareToQuit()
                let stored = try await repository.load()!
                let reopened = CareModel(directory: directory, ownsSession: false, reminderCenter: SilentCenter(),
                    workspaceNotifications: NotificationCenter(), automaticallyTicks: false,
                    now: { clock.date.addingTimeInterval(86400) }, uptime: { clock.uptime })
                try check(stored.id == pet.id && stored.growth.species == species && stored.growth.health == 5 && stored.growth.mood == 5,
                          "All five identities/vitals survive response and restart")
                try check(reopened.cycle.phase == .paused && reopened.cycle.remainingWork == 60,
                          "Reopen preserves next-round custom timing without offline charge")
                var departed = stored
                try departed.applyNeed(id: UUID(), food: true, steps: 5, responding: false, now: clock.date)
                let deadRoundTrip = try JSONDecoder().decode(Pet.self, from: JSONEncoder().encode(departed))
                try check(deadRoundTrip.growth.stage == .departed && deadRoundTrip.growth.species == species,
                          "All five share the same persistent death rules")
            }
        }
        print("PASS SurvivalChecks: 180/360 boundaries, work overshoot, food/walk isolation, pause/offline, atomic idempotent penalties and response, zero-vital death/no revival, replacement isolation, App coordinator, delayed sleep/lock, failure/retry, v2→v3 original preservation and corrupt-v3 protection")
    }
}
