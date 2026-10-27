import Foundation
import PetCore
import AdoptionFlow

@main @MainActor
struct MemorialChecks {
    static let fm = FileManager.default
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw NSError(domain: "MemorialChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func bytes(_ root: URL) throws -> [String: Data] {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator where url.pathExtension == "json" {
            result[url.path] = try Data(contentsOf: url)
        }
        return result
    }
    static func dead(species: PetSpecies, rests: Int = 0, now: Date, name: String? = nil, id: UUID = UUID()) throws -> Pet {
        var pet = try Pet(id: id, name: name, now: now.addingTimeInterval(-600), species: species)
        for n in 0..<rests { try pet.completeRest(id: "r\(n)", food: true, now: now.addingTimeInterval(-500)) }
        try pet.applyNeed(id: UUID(), food: true, steps: 5, responding: false, now: now)
        return pet
    }
    static func main() async throws {
        let root = fm.temporaryDirectory.appendingPathComponent("Tomatogotchi-Memorial-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let repo = PetRepository(directory: root)
        let empty = try await repo.memorials()
        try check(empty.records.isEmpty && empty.countLabel == "共 0 隻", "Absent data has explicit empty count")
        try check(!fm.fileExists(atPath: root.path), "An empty history view does not create a home")
        let now = Date(timeIntervalSince1970: 1720000000)
        var current = try Pet(name: "尚未告別", now: now.addingTimeInterval(-600), species: .goblin)
        _ = try await repo.adopt(current)
        let living = try await repo.memorials()
        try check(living.records.isEmpty, "Living pets are excluded")
        current = try await repo.applyNeed(petID: current.id, needID: UUID(), food: false, steps: 5, responding: false, now: now)
        var snapshot = try await repo.memorials()
        try check(snapshot.records.count == 1 && snapshot.records[0].name == "尚未告別", "Death is visible before farewell")
        try check(snapshot.records[0].metAt == current.createdAt && snapshot.records[0].departedAt == now, "Meeting/death use original dates")
        let replacement = try Pet(now: now.addingTimeInterval(120))
        let next = try await repo.farewell(id: current.id, replacement: replacement)
        _ = try await repo.farewell(id: current.id, replacement: replacement)
        snapshot = try await PetRepository(directory: root).memorials()
        try check(snapshot.records.count == 1 && next.growth.stage == .egg, "Farewell retry/reopen keeps one memorial and a new living egg")
        let history = root.appendingPathComponent("pet-history")
        // Simulate archive committed but primary replacement interrupted: one ID remains one memorial.
        try JSONEncoder().encode(current).write(to: root.appendingPathComponent("pet.json"))
        snapshot = try await repo.memorials()
        try check(snapshot.records.count == 1, "Archive + current death deduplicate after interrupted farewell")
        try JSONEncoder().encode(next).write(to: root.appendingPathComponent("pet.json"))
        for (index, species) in PetSpecies.allCases.enumerated() {
            for rests in [0, 3, 12] {
                let pet = try dead(species: species, rests: rests, now: now.addingTimeInterval(Double(index * 10 + rests)), name: rests == 12 ? "很長的寵物名字也是完整保留" : nil)
                try JSONEncoder().encode(pet).write(to: history.appendingPathComponent("\(pet.id.uuidString).json"))
            }
        }
        // v2 legacy neglect death, v3 discrete death, v1 living egg are all read without rewriting.
        for version in [1, 2, 3] {
            let id = UUID();var pet = try Pet(id: id, name: "舊紀錄\(version)", now: now, species: .forPet(id))
            if version == 2 {
                try pet.applyNeed(id: UUID(), food: true, steps: 0, responding: true, now: now)
                for n in 0..<3 { try pet.completeRest(id: "old\(n)", food: true, now: now) }
                pet.advanceNeglect(seconds: 4500, context: .awaitingCare, now: now.addingTimeInterval(900))
            } else if version == 3 { try pet.applyNeed(id: UUID(), food: true, steps: 5, responding: false, now: now.addingTimeInterval(800)) }
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pet)) as! [String: Any]
            object["saveVersion"] = version
            if version == 1 { object.removeValue(forKey: "growth") }
            try JSONSerialization.data(withJSONObject: object).write(to: history.appendingPathComponent("\(id.uuidString).json"))
        }
        // Invalid, unknown, misnamed and symlink files are reported, never interpreted as a complete zero.
        let bad = history.appendingPathComponent("\(UUID().uuidString).json")
        try Data("broken".utf8).write(to: bad)
        let future = history.appendingPathComponent("\(UUID().uuidString).json")
        try Data("{\"saveVersion\":999}".utf8).write(to: future)
        try JSONEncoder().encode(current).write(to: history.appendingPathComponent("\(UUID().uuidString).json"))
        let link = history.appendingPathComponent("\(UUID().uuidString).json")
        try fm.createSymbolicLink(at: link, withDestinationURL: bad)
        let before = try bytes(root)
        snapshot = try await repo.memorials()
        try check(snapshot.records.count == 18 && snapshot.unreadableCount == 4, "All species/stages/legacy records coexist with partial-read diagnostics")
        try check(snapshot.countLabel == "已讀取 18 隻（紀錄未完整載入）", "Partial total is explicitly incomplete")
        try check(snapshot.records.first?.name == "舊紀錄2", "Newest death first, not archive/farewell time")
        try check(snapshot.records.contains { $0.name == "小傢伙" }, "Unnamed pets retain display fallback")
        try check(try bytes(root) == before, "All original saves/archives remain byte-for-byte unchanged")
        let model = MemorialModel(repository: repo)
        await model.load()
        try check(model.snapshot == snapshot && !model.loading && model.error == nil, "Shared UI model exposes partial result")
        try fm.removeItem(at: history)
        try Data("blocked-directory".utf8).write(to: history)
        await model.load()
        try check(model.snapshot == nil && model.error != nil && !model.loading, "Directory failure is visible, not a fake zero")
        try fm.removeItem(at: history)
        await model.load()
        try check(model.error == nil && model.snapshot?.records.isEmpty == true, "Retry recovers without changing live pet")
        try check(PetMemorial.timestamp(nil) == "未記錄", "Missing dates never invented")
        try check(PetMemorial.timestamp(Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 28800)!) == "1970/01/01 08:00", "Stable Gregorian local 24h minute formatting")
        print("PASS MemorialChecks: current death, farewell/retry/interruption/reopen, 5 species × 3 stages, v1–v4 read-only compatibility, malformed/future/symlink partial totals, model error/retry and dates")
    }
    static func awaitResultLive(repo: PetRepository) async throws -> Bool {
        try await repo.memorials().records.isEmpty
    }
}
