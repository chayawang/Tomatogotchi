import Foundation
import PetCore

@main
struct CoreChecks {
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "CoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func expectFailure(_ message: String, _ action: () async throws -> Void) async throws {
        do { try await action() } catch { return }
        throw NSError(domain: "CoreChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected failure: \(message)"])
    }
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Tomatogotchi-Checks-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("save")
        let repository = PetRepository(directory: folder)
        let initial = try await repository.load()
        try require(initial == nil, "Fresh store must be empty")
        let unnamed = try Pet(name: "   ")
        try require(unnamed.name == nil && unnamed.displayName == "小傢伙", "Skip stores nil, not a fabricated name")
        let pet = try await repository.adopt(unnamed)
        let cold = try await PetRepository(directory: folder).load()
        try require(cold == pet, "A new repository must restore exact identity and dates")
        let retry = try await repository.adopt(unnamed)
        try require(retry == pet, "Retry after committed save must be idempotent")
        try await expectFailure("second adoption") { _ = try await repository.adopt(Pet(name: "另一隻")) }
        let emoji = "小葉👨‍👩‍👧‍👦"
        let renamed = try await repository.rename(id: pet.id, to: "  \(emoji)  ")
        try require(renamed.id == pet.id && renamed.name == emoji && renamed.createdAt == pet.createdAt, "Rename preserves identity and Unicode")
        let blank = try await repository.rename(id: pet.id, to: " ")
        try require(blank.name == nil && blank.id == pet.id, "Clear name keeps the pet unnamed")
        try await expectFailure("newline") { _ = try Pet(name: "小葉\n晚安") }
        try await expectFailure("trailing newline") { _ = try Pet(name: "小葉\n") }
        try await expectFailure("tab") { _ = try Pet(name: "小\t葉") }
        try await expectFailure("stale identity") { _ = try await repository.rename(id: UUID(), to: "錯誤") }
        let primary = folder.appendingPathComponent("pet.json")
        let invalid = Data("{bad data".utf8)
        try invalid.write(to: primary)
        try await expectFailure("corrupt load") { _ = try await repository.load() }
        try await expectFailure("corrupt adoption must never overwrite") { _ = try await repository.adopt(Pet()) }
        try require(try Data(contentsOf: primary) == invalid, "Invalid primary must be preserved")
        let canRestore = await repository.hasValidBackup()
        try require(canRestore, "Last valid revision must be recoverable")
        let restored = try await repository.restoreBackup()
        try require(restored.id == pet.id && restored.name == emoji, "Recovery uses validated backup and same pet")
        let preserved = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("pet-damaged-") }
        try require(preserved.count == 1, "Recovery preserves broken original")
        var newer = try JSONSerialization.jsonObject(with: Data(contentsOf: primary)) as! [String: Any]
        newer["saveVersion"] = 99
        let newerData = try JSONSerialization.data(withJSONObject: newer)
        try newerData.write(to: primary)
        try await expectFailure("future version") { _ = try await repository.load() }
        try await expectFailure("no downgrade from backup") { _ = try await repository.restoreBackup() }
        try require(try Data(contentsOf: primary) == newerData, "Unsupported data cannot be replaced")
        // A newer format may remove fields required by version 1. Inspect version first.
        let changedSchema = Data("{\"saveVersion\":99,\"newFormat\":true}".utf8)
        try changedSchema.write(to: primary)
        do {
            _ = try await repository.load()
            try require(false, "Changed future schema must not load")
        } catch PetError.unsupportedVersion { }
        try await expectFailure("changed future schema must not restore old backup") { _ = try await repository.restoreBackup() }
        try require(try Data(contentsOf: primary) == changedSchema, "Future schema bytes must remain unchanged")
        try fm.removeItem(at: primary)
        try await expectFailure("missing primary with backup is not a fresh install") { _ = try await repository.load() }
        let orphan = try await repository.restoreBackup()
        try require(orphan.id == pet.id, "Orphan backup restoration retains identity")
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to: blocked)
        try await expectFailure("unwritable location") { _ = try await PetRepository(directory: blocked).adopt(Pet()) }
        try require(try Data(contentsOf: blocked) == Data("keep".utf8), "Failure does not replace an unrelated file")
        let concurrent = root.appendingPathComponent("concurrent")
        let first = PetRepository(directory: concurrent), second = PetRepository(directory: concurrent)
        let a = try Pet(name: "A"), b = try Pet(name: "B")
        async let resultA: Pet? = try? first.adopt(a)
        async let resultB: Pet? = try? second.adopt(b)
        let results = await [resultA, resultB].compactMap { $0 }
        try require(results.count == 1, "Two repositories cannot create two pets")
        let winner = try await first.load()
        try require(winner == results.first, "Concurrent winner persists")
        try require(Set(PetSpecies.availableForAdoption) == Set(PetSpecies.allCases), "All five completed species must be available")
        var assigned = Set<PetSpecies>()
        for byte in 0..<256 {
            let uuid = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", byte))!
            let species = PetSpecies.assign(uuid, available: PetSpecies.allCases)
            assigned.insert(species)
            let candidate = try Pet(id: uuid, name: "Species QA", species: species)
            let reopened = try JSONDecoder().decode(Pet.self, from: JSONEncoder().encode(candidate))
            try require(reopened == candidate && reopened.growth.species == species && reopened.saveVersion == 4,
                        "Every new species is stable across v4 round trips")
        }
        try require(assigned == Set(PetSpecies.allCases), "Injected five-species availability covers all species")
        for version in [1, 2, 3] {
            let legacyID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            var legacyPet = try Pet(id: legacyID, name: "Legacy", species: .cat)
            if version > 1 { for n in 0..<3 { try legacyPet.completeRest(id: "legacy-\(n)", food: true, now: Date(timeIntervalSince1970: 1)) } }
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyPet)) as! [String: Any]
            object["saveVersion"] = version
            if version == 1 { object.removeValue(forKey: "growth") }
            let bytes = try JSONSerialization.data(withJSONObject: object)
            let legacyFolder = root.appendingPathComponent("legacy-v\(version)")
            try fm.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
            let legacyFile = legacyFolder.appendingPathComponent("pet.json")
            try bytes.write(to: legacyFile)
            let legacyRepo = PetRepository(directory: legacyFolder)
            let migrated = try await legacyRepo.load()!
            try require(migrated.growth.species == .cat && migrated.id == legacyID && migrated.name == "Legacy",
                        "Legacy UUID two-species assignment remains unchanged")
            try require(try Data(contentsOf: legacyFile) == bytes, "Read must not rewrite original legacy bytes")
            _ = try await legacyRepo.rename(id: legacyID, to: "Legacy preserved")
            let original = legacyFolder.appendingPathComponent("pet-v\(version)-original-\(legacyID.uuidString).json")
            try require(try Data(contentsOf: original) == bytes, "First mutation preserves exact v1-v3 original")
            let stored = try await legacyRepo.load()!
            try require(stored.saveVersion == 4 && stored.growth.species == .cat && stored.growth.completedRests == migrated.growth.completedRests,
                        "Migration preserves stable species and growth history")
        }
        print("PASS: fresh/skip, cold restart, idempotency, duplicate adoption, Unicode rename, clear name, invalid input, stale identity, corrupt-save protection, recovery, future versions, orphan backup, write failure, concurrent adoption")
    }
}
