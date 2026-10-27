import Foundation

public enum PetSpecies: String, Codable, CaseIterable, Sendable {
    case cat, dinosaur, dog, daruma, goblin
    public var label: String {
        switch self {
        case .cat: return "小貓"
        case .dinosaur: return "小恐龍"
        case .dog: return "小狗"
        case .daruma: return "達摩"
        case .goblin: return "哥布林"
        }
    }
    /// Existing saves without a species keep this original two-species rule forever.
    public static func forPet(_ id: UUID) -> PetSpecies { id.uuid.15 % 2 == 0 ? .cat : .dinosaur }
    /// Enable a species only in the commit that includes its complete production artwork.
    public static let availableForAdoption: [PetSpecies] = [.cat, .dinosaur, .dog, .daruma, .goblin]
    public static func assign(_ id: UUID, available: [PetSpecies] = availableForAdoption) -> PetSpecies {
        guard !available.isEmpty else { return .forPet(id) }
        return available[Int(id.uuid.15) % available.count]
    }
}
public enum DeathReason: String, Codable, Sendable { case hunger, sadness }
public struct NeedRecord: Codable, Equatable, Sendable {
    public var steps: Int
    public var food: Bool
    public var responded: Bool
}
public enum GrowthStage: String, Codable, Sendable { case egg, hatchling, adult, departed }
public enum CareContext: Sendable { case awaitingCare, working, resting, paused, offline, idle }

/// Stored with the pet in a single atomic transaction, including receipt deduplication.
public struct PetGrowth: Codable, Equatable, Sendable {
    public let species: PetSpecies
    public static let maximumVital = 5
    public private(set) var health = 5
    public private(set) var mood = 5
    public private(set) var deathReason: DeathReason?
    public private(set) var needs: [String: NeedRecord] = [:]
    private enum CodingKeys: String, CodingKey {
        case species, hasCompletedWork, hasHatched, completedRests, neglectedSeconds, departedAt, health, mood, deathReason, needs
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        species = try c.decode(PetSpecies.self, forKey: .species)
        completedRests = try c.decode(Set<String>.self, forKey: .completedRests)
        neglectedSeconds = try c.decode(TimeInterval.self, forKey: .neglectedSeconds)
        departedAt = try c.decodeIfPresent(Date.self, forKey: .departedAt)
        health = try c.decodeIfPresent(Int.self, forKey: .health) ?? 5
        mood = try c.decodeIfPresent(Int.self, forKey: .mood) ?? 5
        deathReason = try c.decodeIfPresent(DeathReason.self, forKey: .deathReason)
        needs = try c.decodeIfPresent([String: NeedRecord].self, forKey: .needs) ?? [:]
        // Earlier saves only recorded rests and pending care; derive eligibility
        // without rewriting their original bytes or counting new early rests.
        let storedWork = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedWork)
        hasCompletedWork = storedWork ?? (!completedRests.isEmpty || !needs.isEmpty)
        // build33/34 already hatched on completed work. Older files retain
        // their original three-rest stage until the next explicit care response.
        hasHatched = try c.decodeIfPresent(Bool.self, forKey: .hasHatched)
            ?? storedWork ?? (completedRests.count >= 3)
    }
    public func hasProcessedNeed(id: UUID, steps: Int, responding: Bool = false) -> Bool {
        guard let record = needs[id.uuidString] else { return false }
        return record.responded || (record.steps >= steps && !responding)
    }
    /// Cumulative steps + response live in pet.json, so a timer replay cannot
    /// double-charge or double-recover after an interruption between two files.
    public mutating func applyNeed(id: UUID, food: Bool, steps: Int, responding: Bool, now: Date) throws {
        guard (0...5).contains(steps), now.timeIntervalSince1970.isFinite else { throw PetError.damagedSave }
        let key = id.uuidString
        var record = needs[key] ?? NeedRecord(steps: 0, food: food, responded: false)
        guard record.food == food else { throw PetError.damagedSave }
        guard departedAt == nil, !record.responded else { return }
        let loss = max(0, steps - record.steps)
        if food { health = max(0, health - loss) } else { mood = max(0, mood - loss) }
        record.steps = max(record.steps, steps)
        if health == 0 || mood == 0 {
            departedAt = now; deathReason = health == 0 ? .hunger : .sadness
        } else if responding {
            if food { health = min(Self.maximumVital, health + 1) }
            else { mood = min(Self.maximumVital, mood + 1) }
            record.responded = true
        }
        needs[key] = record
        hasCompletedWork = true
        if record.responded { hasHatched = true }
    }
    public private(set) var hasCompletedWork = false
    public private(set) var hasHatched = false
    public private(set) var completedRests: Set<String> = []
    public private(set) var neglectedSeconds: TimeInterval = 0
    public private(set) var departedAt: Date?
    public var stage: GrowthStage {
        if departedAt != nil { return .departed }
        if completedRests.count >= 12 { return .adult }
        return hasHatched ? .hatchling : .egg
    }
    public var isWeak: Bool { departedAt == nil && (health <= 2 || mood <= 2 || (stage != .egg && neglectedSeconds >= 50 * 60)) }
    public var label: String {
        switch stage {
        case .egg: return "未知蛋"
        case .hatchling: return "幼體 · \(species.label)"
        case .adult: return "成體 · \(species.label)"
        case .departed: return "這段陪伴會保留。"
        }
    }
    public init(petID: UUID, species: PetSpecies? = nil) { self.species = species ?? .assign(petID) }
    public mutating func completeRest(id: String, food: Bool) throws {
        guard !id.isEmpty, id.utf8.count <= 160 else { throw PetError.damagedSave }
        guard departedAt == nil, !completedRests.contains(id) else { return }
        completedRests.insert(id)
        if food { neglectedSeconds = 0 }
    }
    /// Legacy 50/75-minute simulation, retained only for old-format checks.
    /// The App uses discrete applyNeed transactions instead.
    public mutating func advanceNeglect(seconds: TimeInterval, context: CareContext, now: Date) {
        guard context == .awaitingCare, stage != .egg, departedAt == nil,
              seconds.isFinite, seconds >= 0, now.timeIntervalSince1970.isFinite else { return }
        neglectedSeconds = min(75 * 60, neglectedSeconds + seconds)
        if neglectedSeconds >= 75 * 60 { departedAt = now }
    }
    public func validate(petID: UUID) throws {
        guard neglectedSeconds.isFinite,
              neglectedSeconds >= 0, neglectedSeconds <= 75 * 60,
              completedRests.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 160 }),
              departedAt?.timeIntervalSince1970.isFinite ?? true else { throw PetError.damagedSave }
        guard (0...5).contains(health), (0...5).contains(mood),
              needs.allSatisfy({ UUID(uuidString: $0.key) != nil && (0...5).contains($0.value.steps) }) else { throw PetError.damagedSave }
        if !hasCompletedWork && completedRests.count < 12 && neglectedSeconds != 0 { throw PetError.damagedSave }
        if let reason = deathReason {
            guard departedAt != nil, reason == .hunger ? health == 0 : mood == 0 else { throw PetError.damagedSave }
        } else if (departedAt != nil) != (neglectedSeconds == 75 * 60) { throw PetError.damagedSave }
        if departedAt == nil && (health == 0 || mood == 0) { throw PetError.damagedSave }
    }
}
