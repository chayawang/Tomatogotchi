import Foundation
import PetCore
import CareCore

@main
struct GrowthChecks {
    static func require(_ ok: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try ok() else { throw NSError(domain: "GrowthChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func fail(_ action: () async throws -> Void) async throws {
        do { try await action() } catch { return }
        throw NSError(domain: "GrowthChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected failure"])
    }
    static func main() async throws {
        let fm = FileManager.default, now = Date(timeIntervalSince1970: 1000)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var p = try Pet(id: id, name: "小葉", now: now, species: .cat)
        p.advanceNeglect(seconds: 999999, context: .awaitingCare, now: now)
        try require(p.growth.stage == .egg && p.growth.neglectedSeconds == 0, "Eggs cannot starve")
        for n in 1...3 { try p.completeRest(id: "rest-\(n)", food: true, now: now) }
        try require(p.growth.stage == .hatchling && p.growth.species == .cat, "Three rests hatch a stable cat")
        try p.completeRest(id: "rest-3", food: true, now: now)
        try require(p.growth.completedRests.count == 3, "Receipt retries cannot duplicate growth")
        for context in [CareContext.working, .resting, .paused, .offline, .idle] {
            p.advanceNeglect(seconds: 999999, context: context, now: now)
        }
        try require(p.growth.neglectedSeconds == 0, "Work, rest, pause, offline and idle never starve")
        p.advanceNeglect(seconds: 50 * 60, context: .awaitingCare, now: now)
        try require(p.growth.isWeak && p.growth.stage == .hatchling, "Weak threshold without early death")
        try p.completeRest(id: "walk", food: false, now: now)
        try require(p.growth.isWeak, "Walk does not silently count as food")
        try p.completeRest(id: "food", food: true, now: now)
        try require(p.growth.neglectedSeconds == 0, "Completed food care resolves hunger")
        for n in 6...12 { try p.completeRest(id: "rest-\(n)", food: true, now: now) }
        try require(p.growth.stage == .adult, "Twelve unique rests grow adult")
        p.advanceNeglect(seconds: 75 * 60 - 1, context: .awaitingCare, now: now)
        try require(p.growth.stage == .adult, "No death before boundary")
        p.advanceNeglect(seconds: 1, context: .awaitingCare, now: now)
        try require(p.growth.stage == .departed, "Death at boundary")
        let dead = p
        try p.completeRest(id: "cannot-revive", food: true, now: now)
        try require(p == dead, "Care cannot revive a departed pet")
        let root = fm.temporaryDirectory.appendingPathComponent("Tomatogotchi-Growth-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let primary = root.appendingPathComponent("pet.json")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Pet(id: id, name: "舊蛋", now: now))) as! [String: Any]
        legacy["saveVersion"] = 1; legacy.removeValue(forKey: "growth")
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacy)
        try legacyBytes.write(to: primary)
        let repo = PetRepository(directory: root)
        let migrated = try await repo.load()!
        try require(migrated.id == id && migrated.name == "舊蛋" && migrated.saveVersion == 4, "Legacy migration preserves identity/name")
        try require(try Data(contentsOf: primary) == legacyBytes, "Loading never silently rewrites legacy bytes")
        let other = PetRepository(directory: root)
        async let a = repo.completeRest(id: id, receipt: "same", food: true, now: now)
        async let b = other.completeRest(id: id, receipt: "same", food: true, now: now)
        _ = try await (a, b)
        let once = try await repo.load()!
        try require(once.growth.completedRests.count == 1, "Concurrent actors commit a receipt only once")
        let original = root.appendingPathComponent("pet-v1-original-\(id.uuidString).json")
        try require(try Data(contentsOf: original) == legacyBytes, "First mutation preserves exact v1 original")
        var restored = try JSONDecoder().decode(Pet.self, from: Data(contentsOf: primary))
        try require(restored.growth.species == .cat, "Species survives cold decode")
        var cycle = try CareCycle(workDuration: 10, breakDuration: 5)
        cycle.bind(to: id); cycle.start(); cycle.rest(.food, now: now)
        try require(cycle.completedReceipt == nil, "No reward before rest completes")
        cycle.advance(workElapsed: 0, now: now.addingTimeInterval(5))
        let receipt = cycle.completedReceipt!
        try require(!cycle.canLeaveCompletedRest(afterSaving: nil), "A stop at the deadline must preserve the uncommitted receipt")
        try require(cycle.canLeaveCompletedRest(afterSaving: receipt), "Only the current committed receipt may release rest")
        let decodedCycle = try JSONDecoder().decode(CareCycle.self, from: JSONEncoder().encode(cycle))
        try require(decodedCycle.completedReceipt == receipt, "Receipt remains identical after restart")
        cycle.bind(to: UUID())
        try require(cycle.phase == .idle && cycle.completedReceipt == nil, "A new pet cannot inherit old pet's reward")
        var oldCycle = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decodedCycle)) as! [String: Any]
        oldCycle.removeValue(forKey: "restID"); oldCycle.removeValue(forKey: "petID")
        let oldBytes = try JSONSerialization.data(withJSONObject: oldCycle)
        var legacyCycle = try JSONDecoder().decode(CareCycle.self, from: oldBytes)
        legacyCycle.bind(to: id)
        let oldReceipt = legacyCycle.completedReceipt
        let legacyReloaded = try JSONDecoder().decode(CareCycle.self, from: JSONEncoder().encode(legacyCycle))
        try require(oldReceipt != nil && oldReceipt == legacyReloaded.completedReceipt, "Legacy rest migration uses stable receipt")
        cycle.start(); cycle.rest(.food, now: now); cycle.stop()
        try require(cycle.completedReceipt == nil, "Cancelled rest has no reward")
        let previousBytes = try Data(contentsOf: primary)
        let backup = root.appendingPathComponent("pet.backup.json")
        try fm.removeItem(at: backup); try fm.createDirectory(at: backup, withIntermediateDirectories: false)
        try await fail { _ = try await repo.completeRest(id: id, receipt: "retry", food: true, now: now) }
        try require(try Data(contentsOf: primary) == previousBytes, "Failed backup leaves growth uncommitted")
        try fm.removeItem(at: backup)
        restored = try await repo.completeRest(id: id, receipt: "retry", food: true, now: now)
        try require(restored.growth.completedRests.count == 2, "Retry after failure counts once")
        let newPet = try Pet(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, now: now, species: .dinosaur)
        try await fail { _ = try await repo.farewell(id: id, replacement: newPet) }
        try await fail { _ = try await repo.farewell(id: id, replacement: restored) }
        try JSONEncoder().encode(dead).write(to: primary)
        let deadBytes = try Data(contentsOf: primary)
        let history = root.appendingPathComponent("pet-history")
        try Data("blocked".utf8).write(to: history)
        try await fail { _ = try await repo.farewell(id: id, replacement: newPet) }
        try require(try Data(contentsOf: primary) == deadBytes, "Archive failure preserves departed pet")
        try fm.removeItem(at: history)
        let fresh = try await repo.farewell(id: id, replacement: newPet)
        let retry = try await repo.farewell(id: id, replacement: newPet)
        try require(fresh == retry && fresh.id != id && fresh.growth.stage == .egg && fresh.growth.species == .dinosaur, "Farewell yields one new unknown egg, not revival")
        try require(try Data(contentsOf: history.appendingPathComponent("\(id.uuidString).json")) == deadBytes, "Farewell archives exact old pet bytes")
        try await fail { _ = try await repo.completeRest(id: id, receipt: "late-old-pet", food: true, now: now) }
        var invalidV2 = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh)) as! [String: Any]
        invalidV2.removeValue(forKey: "growth")
        let invalidBytes = try JSONSerialization.data(withJSONObject: invalidV2)
        try invalidBytes.write(to: primary)
        try await fail { _ = try await repo.load() }
        try await fail { _ = try await repo.completeRest(id: fresh.id, receipt: "invalid", food: true, now: now) }
        try require(try Data(contentsOf: primary) == invalidBytes, "Missing v2 growth is corrupt, never reset to an egg")
        let future = Data("{\"saveVersion\":99,\"differentSchema\":true}".utf8)
        try future.write(to: primary)
        try await fail { _ = try await repo.completeRest(id: fresh.id, receipt: "x", food: true, now: now) }
        try await fail { _ = try await repo.farewell(id: fresh.id, replacement: Pet()) }
        try require(try Data(contentsOf: primary) == future, "New mutations cannot overwrite future formats")
        print("PASS GrowthChecks: thresholds, deduplication, frozen contexts, no revival, v1 migration, atomic concurrent receipts, legacy rest recovery, failure/retry, archive and new identity, future protection")
    }
}
