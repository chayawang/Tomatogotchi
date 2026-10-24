import Foundation

public struct PetMemorial: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let metAt: Date?
    public let departedAt: Date?

    public init?(pet: Pet) {
        guard pet.growth.stage == .departed else { return nil }
        id = pet.id; name = pet.displayName
        metAt = pet.createdAt; departedAt = pet.growth.departedAt
    }

    public static func timestamp(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "未記錄" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

public struct PetMemorialSnapshot: Equatable, Sendable {
    public let records: [PetMemorial]
    public let unreadableCount: Int
    public init(records: [PetMemorial] = [], unreadableCount: Int = 0) {
        self.records = records.sorted {
            let a = $0.departedAt ?? .distantPast, b = $1.departedAt ?? .distantPast
            return a == b ? $0.id.uuidString < $1.id.uuidString : a > b
        }
        self.unreadableCount = unreadableCount
    }
    public var countLabel: String {
        unreadableCount == 0 ? "共 \(records.count) 隻" : "已讀取 \(records.count) 隻（紀錄未完整載入）"
    }
}
