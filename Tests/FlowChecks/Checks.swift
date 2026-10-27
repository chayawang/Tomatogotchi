import Foundation
import PetCore
import AdoptionFlow
import CareCore

/// Runs the same observable model as the app, with real disk I/O in disposable folders.
/// This verifies presentation state and persistence, not pixel layout or native clicks.
@main
@MainActor
struct FlowChecks {
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw NSError(domain: "FlowChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func settle(_ model: AdoptionModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.screen == .loading || model.saving {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "FlowChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model did not settle"])
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Tomatogotchi-Flow-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let namedFolder = root.appendingPathComponent("named")
        let named = AdoptionModel(repository: PetRepository(directory: namedFolder))
        named.load(); try await settle(named)
        try require(named.screen == .welcome && named.pet == nil, "Fresh app must welcome")
        named.edit()
        try require(named.screen == .welcome, "Menu cannot edit before adoption")
        named.receive(); named.draft = "  小葉👨‍👩‍👧‍👦  "
        named.save()
        try require(named.saving && named.screen == .naming, "No success screen before disk commit")
        named.save() // A second click must not create another operation.
        try await settle(named)
        try require(named.screen == .home && named.pet?.name == "小葉👨‍👩‍👧‍👦", "Named adoption normalizes Unicode")
        let original = named.pet!
        let primary = namedFolder.appendingPathComponent("pet.json")
        let beforeCancel = try Data(contentsOf: primary)
        named.edit(); named.draft = "不儲存這個"; named.cancelEdit()
        try require(named.screen == .home && named.pet == original, "Cancel keeps original pet")
        try require(try Data(contentsOf: primary) == beforeCancel, "Cancel must never touch the save")
        named.edit(); named.draft = "新名字"; named.save(); try await settle(named)
        let reopened = AdoptionModel(repository: PetRepository(directory: namedFolder))
        reopened.load(); try await settle(reopened)
        try require(reopened.screen == .home && reopened.pet?.id == original.id && reopened.pet?.name == "新名字", "Reopen after rename retains identity and name")
        reopened.edit(); reopened.draft = "   "; reopened.save(); try await settle(reopened)
        try require(reopened.pet?.name == nil && reopened.pet?.displayName == "小傢伙", "Clearing a name keeps an unnamed pet")

        let skipFolder = root.appendingPathComponent("skip")
        let skipped = AdoptionModel(repository: PetRepository(directory: skipFolder))
        skipped.load(); try await settle(skipped); skipped.receive()
        skipped.draft = "invalid\nname"
        try require(skipped.nameError != nil, "Invalid name must have validation feedback")
        skipped.save(skip: true); try await settle(skipped)
        try require(skipped.screen == .home && skipped.pet?.name == nil, "Skip ignores even an invalid draft")
        let cold = AdoptionModel(repository: PetRepository(directory: skipFolder))
        cold.load(); try await settle(cold)
        try require(cold.pet == skipped.pet, "Skipped adoption survives restart")

        let failedFolder = root.appendingPathComponent("failed")
        let failed = AdoptionModel(repository: PetRepository(directory: failedFolder))
        failed.load(); try await settle(failed); failed.receive(); failed.draft = "要保留的名字"
        let blockedPrimary = failedFolder.appendingPathComponent("pet.json")
        try fm.createDirectory(at: blockedPrimary, withIntermediateDirectories: true)
        failed.save(); try await settle(failed)
        try require(failed.screen == .naming && failed.pet == nil && failed.saveError != nil, "Failed write must not show adopted")
        try require(failed.draft == "要保留的名字", "Failure must preserve input")
        failed.backToInput()
        try require(failed.saveError == nil && failed.draft == "要保留的名字", "Back to input clears only error")
        failed.save(); try await settle(failed)
        try fm.removeItem(at: blockedPrimary)
        failed.retrySave(); try await settle(failed)
        try require(failed.screen == .home && failed.pet?.name == "要保留的名字", "Retry succeeds after storage is fixed")

        let invalidFolder = root.appendingPathComponent("invalid")
        let invalid = AdoptionModel(repository: PetRepository(directory: invalidFolder))
        invalid.load(); try await settle(invalid); invalid.receive(); invalid.draft = "bad\nname"; invalid.save()
        try require(invalid.screen == .naming && invalid.saveError != nil && !invalid.saving, "Invalid input never starts persistence")
        try require(!fm.fileExists(atPath: invalidFolder.appendingPathComponent("pet.json").path), "Invalid input never creates a save")

        // The named store has a valid previous-name backup from the clear-name edit.
        let broken = Data("{broken".utf8)
        try broken.write(to: primary)
        let recovery = AdoptionModel(repository: PetRepository(directory: namedFolder))
        recovery.load(); try await settle(recovery)
        try require(recovery.screen == .loadFailed && recovery.canRestore, "Corrupt primary offers valid backup")
        try require(try Data(contentsOf: primary) == broken, "Loading failure preserves original bytes")
        recovery.restore(); try await settle(recovery)
        try require(recovery.screen == .home && recovery.pet?.id == original.id && recovery.pet?.name == "新名字", "Explicit recovery restores backup identity and revision")
        var future = try JSONSerialization.jsonObject(with: Data(contentsOf: primary)) as! [String: Any]
        future["saveVersion"] = 99
        future.removeValue(forKey: "lifeStage")
        let futureData = try JSONSerialization.data(withJSONObject: future)
        try futureData.write(to: primary)
        recovery.load(); try await settle(recovery)
        try require(recovery.screen == .loadFailed && !recovery.canRestore, "Future version must hide downgrade recovery")
        recovery.edit()
        try require(recovery.screen == .loadFailed, "Menu cannot bypass a load failure with stale pet data")
        recovery.restore()
        try require(try Data(contentsOf: primary) == futureData, "Disabled recovery cannot overwrite future data")

        let growthFolder = root.appendingPathComponent("growth")
        let growthRepo = PetRepository(directory: growthFolder)
        let growing = AdoptionModel(repository: growthRepo)
        growing.load(); try await settle(growing); growing.receive(); growing.save(skip: true); try await settle(growing)
        let growthID = growing.pet!.id
        let date = Date(timeIntervalSince1970: 5000)
        var cycle = try CareCycle(workDuration: 10, breakDuration: 5)
        cycle.bind(to: growthID)
        for n in 1...3 {
            cycle.start()
            cycle.advance(workElapsed: 10, now: date.addingTimeInterval(Double(n) * 10))
            growing.recordNeed(cycle.needProgress!)
            try await settle(growing)
            try require(growing.pet?.growth.stage == (n == 1 ? .egg : .hatchling), "Work completion does not hatch a new egg")
            growing.recordNeed(cycle.needProgress!, responding: true)
            try await settle(growing)
            try require(growing.pet?.growth.stage == .hatchling, "First successful care response hatches")
            cycle.rest(.food, now: date.addingTimeInterval(Double(n) * 10))
            cycle.advance(workElapsed: 0, now: date.addingTimeInterval(Double(n) * 10 + 5))
            let receipt = cycle.completedReceipt!
            growing.recordRest(receipt); growing.recordRest(receipt)
            try require(growing.saving, "Rest has not committed before disk save returns")
            try await settle(growing)
            try require(growing.pet?.growth.completedRests.count == n && growing.hasSavedRest(receipt), "Model counts each rest once after commit")
        }
        try require(growing.pet?.growth.stage == .hatchling, "Completed rests retain the already hatched pet")
        let coldGrowth = AdoptionModel(repository: PetRepository(directory: growthFolder))
        coldGrowth.load(); try await settle(coldGrowth)
        try require(coldGrowth.pet == growing.pet, "Growth and species survive model restart")
        coldGrowth.recordRest(cycle.completedReceipt!); try await settle(coldGrowth)
        try require(coldGrowth.pet?.growth.completedRests.count == 3, "Recovered receipt is not rewarded again")
        let growthBackup = growthFolder.appendingPathComponent("pet.backup.json")
        try fm.removeItem(at: growthBackup); try fm.createDirectory(at: growthBackup, withIntermediateDirectories: false)
        cycle.start(); cycle.rest(.walk, now: date.addingTimeInterval(50)); cycle.advance(workElapsed: 0, now: date.addingTimeInterval(55))
        let pending = cycle.completedReceipt!
        coldGrowth.recordRest(pending); try await settle(coldGrowth)
        try require(coldGrowth.progressError != nil && !coldGrowth.hasSavedRest(pending), "Failed growth keeps result uncommitted with visible error")
        try fm.removeItem(at: growthBackup)
        coldGrowth.recordRest(pending); try await settle(coldGrowth)
        try require(coldGrowth.progressError == nil && coldGrowth.hasSavedRest(pending), "Growth retry resolves error once")
        var departed = coldGrowth.pet!
        departed.advanceNeglect(seconds: 4500, context: .awaitingCare, now: date)
        try JSONEncoder().encode(departed).write(to: growthFolder.appendingPathComponent("pet.json"))
        coldGrowth.load(); try await settle(coldGrowth)
        coldGrowth.farewell()
        try require(coldGrowth.pet?.id == growthID && !coldGrowth.saving, "Farewell requires explicit confirmation state")
        coldGrowth.farewellConfirming = true; coldGrowth.farewell(); coldGrowth.farewell(); try await settle(coldGrowth)
        try require(coldGrowth.pet?.id != growthID && coldGrowth.pet?.growth.stage == .egg && !coldGrowth.farewellConfirming, "Confirmed farewell creates one fresh egg")
        coldGrowth.recordRest(pending)
        try require(coldGrowth.pet?.growth.completedRests.isEmpty == true, "New pet cannot receive departed pet's pending rest")

        print("PASS FlowChecks: named/skip adoption, precommit state, duplicate click, rename/reopen, cancel bytes unchanged, clear name, input validation, failure/back/retry, explicit recovery, future-version protection, rest commit/retry, hatch/reopen, confirmed farewell, new-pet isolation")
    }
}
