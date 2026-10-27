import Foundation

public struct Pet: Codable, Equatable, Sendable {
    public let saveVersion: Int
    public let id: UUID
    public var name: String?
    public var lifeStage: String { growth.stage.rawValue }
    public private(set) var growth: PetGrowth
    public let createdAt: Date
    public var updatedAt: Date
    public var displayName: String { name ?? "小傢伙" }

    public init(id: UUID = UUID(), name: String? = nil, now: Date = Date(), species: PetSpecies? = nil) throws {
        self.saveVersion = 4
        self.id = id
        self.name = try Self.normalizedName(name ?? "")
        self.growth = PetGrowth(petID: id, species: species)
        self.createdAt = now
        self.updatedAt = now
    }

    private enum CodingKeys: String, CodingKey { case saveVersion, id, name, lifeStage, createdAt, updatedAt, growth }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .saveVersion)
        guard [1, 2, 3, 4].contains(version) else { throw PetError.unsupportedVersion }
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        let storedStage = try c.decode(String.self, forKey: .lifeStage)
        if version == 1 {
            guard storedStage == "egg" else { throw PetError.damagedSave }
            growth = PetGrowth(petID: id, species: .forPet(id))
        } else {
            if version >= 3 {
                enum VitalsKeys: String, CodingKey { case health, mood, needs }
                let vitals = try c.nestedContainer(keyedBy: VitalsKeys.self, forKey: .growth)
                _ = try vitals.decode(Int.self, forKey: .health)
                _ = try vitals.decode(Int.self, forKey: .mood)
                _ = try vitals.decode([String: NeedRecord].self, forKey: .needs)
            }
            growth = try c.decode(PetGrowth.self, forKey: .growth)
            enum HatchingKeys: String, CodingKey { case hasCompletedWork }
            let hatching = try c.nestedContainer(keyedBy: HatchingKeys.self, forKey: .growth)
            if hatching.contains(.hasCompletedWork) {
                guard storedStage == growth.stage.rawValue else { throw PetError.damagedSave }
            } else {
                // Validate the original format's stage before applying the new
                // threshold in memory. Never accept an arbitrary stage mismatch.
                let previousStage: GrowthStage = growth.departedAt != nil ? .departed
                    : growth.completedRests.count >= 12 ? .adult
                    : growth.completedRests.count >= 3 ? .hatchling : .egg
                guard storedStage == previousStage.rawValue else { throw PetError.damagedSave }
            }
            if version < 4, growth.species != .forPet(id) { throw PetError.damagedSave }
        }
        saveVersion = 4
        _ = try validated()
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(saveVersion, forKey: .saveVersion); try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name); try c.encode(lifeStage, forKey: .lifeStage)
        try c.encode(createdAt, forKey: .createdAt); try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(growth, forKey: .growth)
    }
    public mutating func completeRest(id: String, food: Bool, now: Date) throws {
        guard now.timeIntervalSince1970.isFinite else { throw PetError.damagedSave }
        let previous = growth
        try growth.completeRest(id: id, food: food)
        if growth != previous { updatedAt = now }
    }
    public mutating func advanceNeglect(seconds: TimeInterval, context: CareContext, now: Date) {
        let previous = growth
        growth.advanceNeglect(seconds: seconds, context: context, now: now)
        if growth != previous { updatedAt = now }
    }

    public mutating func applyNeed(id: UUID, food: Bool, steps: Int, responding: Bool, now: Date) throws {
        let previous = growth
        try growth.applyNeed(id: id, food: food, steps: steps, responding: responding, now: now)
        if growth != previous { updatedAt = now }
    }

    public static func normalizedName(_ raw: String) throws -> String? {
        // Validate before trimming: pasted newlines must not disappear silently.
        guard !raw.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0)
        }) else { throw PetError.invalidName }
        let name = raw.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    public func validated() throws -> Pet {
        guard saveVersion == 4 else { throw PetError.unsupportedVersion }
        try growth.validate(petID: id)
        guard createdAt.timeIntervalSince1970.isFinite,
              updatedAt.timeIntervalSince1970.isFinite,
              name == (try Self.normalizedName(name ?? "")) else { throw PetError.damagedSave }
        return self
    }
}

public enum PetError: Error, LocalizedError {
    case invalidName, unsupportedVersion, damagedSave, backupAvailable, noBackup
    case alreadyAdopted(Pet), stalePet, storageUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "名字請寫成一行，不要換行或使用控制字元。"
        case .unsupportedVersion: return "這份存檔來自不同版本，請保留檔案並使用相容版本開啟。"
        case .damagedSave: return "目前無法讀取存檔。原檔會保留，不會建立新的蛋覆蓋它。"
        case .backupAvailable: return "找到之前的存檔備份，可以選擇恢復。"
        case .noBackup: return "目前沒有可用的備份。請保留原檔，再試一次。"
        case .alreadyAdopted: return "這台 Mac 已經有一顆蛋，會繼續陪著你。"
        case .stalePet: return "存檔已經改變，請重新讀取後再試。"
        case .storageUnavailable: return "暫時無法存取保存位置，請再試一次。"
        }
    }
}
