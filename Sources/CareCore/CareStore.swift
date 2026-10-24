import Foundation

/// Independent timer data. A damaged timer never overwrites the pet or its backup.
public struct CareStore {
    public let directory: URL
    private var file: URL { directory.appendingPathComponent("care.json") }
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> CareCycle? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        guard [1, 2].contains(try decoder.decode(Header.self, from: data).version) else { throw CareError.unsupportedVersion }
        return try decoder.decode(CareCycle.self, from: data).validated()
    }
    public func save(_ cycle: CareCycle) throws {
        _ = try cycle.validated()
        if FileManager.default.fileExists(atPath: file.path) { _ = try load() }
        if FileManager.default.fileExists(atPath: file.path) {
            struct Header: Decodable { let version: Int }
            let bytes = try Data(contentsOf: file)
            if try JSONDecoder().decode(Header.self, from: bytes).version == 1 {
                let original = directory.appendingPathComponent("care-v1-original.json")
                if !FileManager.default.fileExists(atPath: original.path) { try bytes.write(to: original, options: .atomic) }
            }
        }
        try write(cycle)
    }
    /// Only used after the user explicitly chooses to reset this timer.
    public func reset() throws -> CareCycle {
        let cycle = try CareCycle()
        if FileManager.default.fileExists(atPath: file.path) {
            let preserved = directory.appendingPathComponent("care-previous-\(UUID()).json")
            try FileManager.default.copyItem(at: file, to: preserved)
        }
        try write(cycle)
        return cycle
    }
    private func write(_ cycle: CareCycle) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(cycle).write(to: file, options: .atomic)
    }
}
