import Foundation
import Darwin

/// Disk access is serialized by the actor and an advisory lock across processes.
public actor PetRepository {
    public let directory: URL
    private let manager = FileManager()
    private var primary: URL { directory.appendingPathComponent("pet.json") }
    private var backup: URL { directory.appendingPathComponent("pet.backup.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> Pet? {
        try locked {
            if !manager.fileExists(atPath: primary.path) {
                if manager.fileExists(atPath: backup.path) { throw PetError.backupAvailable }
                return nil
            }
            return try decode(primary)
        }
    }

    public func hasValidBackup() -> Bool { (try? decode(backup)) != nil }

    public func adopt(_ pet: Pet) throws -> Pet {
        try locked {
            _ = try pet.validated()
            if manager.fileExists(atPath: primary.path) {
                let existing = try decode(primary)
                if existing.id == pet.id { return existing } // Retry after a successful write.
                throw PetError.alreadyAdopted(existing)
            }
            guard !manager.fileExists(atPath: backup.path) else { throw PetError.backupAvailable }
            try write(pet, to: primary)
            return pet
        }
    }

    public func rename(id: UUID, to rawName: String) throws -> Pet {
        let name = try Pet.normalizedName(rawName)
        return try locked {
            var pet = try decode(primary)
            guard pet.id == id else { throw PetError.stalePet }
            let oldData = try Data(contentsOf: primary)
            try preserveLegacy(oldData)
            try writeData(oldData, to: backup) // Only validated previous data becomes a backup.
            pet.name = name
            pet.updatedAt = Date()
            try write(pet, to: primary)
            return pet
        }
    }

    public func completeRest(id: UUID, receipt: String, food: Bool, now: Date) throws -> Pet {
        try locked {
            var pet = try decode(primary)
            guard pet.id == id else { throw PetError.stalePet }
            let previous = pet
            try pet.completeRest(id: receipt, food: food, now: now)
            guard pet != previous else { return pet }
            let bytes = try Data(contentsOf: primary)
            try preserveLegacy(bytes)
            try writeData(bytes, to: backup)
            try write(pet, to: primary)
            return pet
        }
    }

    public func applyNeed(petID: UUID, needID: UUID, food: Bool, steps: Int, responding: Bool, now: Date) throws -> Pet {
        try locked {
            var pet = try decode(primary)
            guard pet.id == petID else { throw PetError.stalePet }
            let previous = pet
            try pet.applyNeed(id: needID, food: food, steps: steps, responding: responding, now: now)
            guard pet != previous else { return pet }
            let bytes = try Data(contentsOf: primary)
            try preserveLegacy(bytes)
            try writeData(bytes, to: backup)
            try write(pet, to: primary)
            return pet
        }
    }

    /// Archive first, then atomically replace. A retry after commit returns the same new pet.
    public func farewell(id: UUID, replacement: Pet) throws -> Pet {
        try locked {
            let current = try decode(primary)
            _ = try replacement.validated()
            guard replacement.id != id, replacement.growth.stage == .egg,
                  replacement.growth.completedRests.isEmpty else { throw PetError.stalePet }
            if current.id == replacement.id { return current }
            guard current.id == id, current.growth.stage == .departed else { throw PetError.stalePet }
            let bytes = try Data(contentsOf: primary)
            let history = directory.appendingPathComponent("pet-history", isDirectory: true)
            try manager.createDirectory(at: history, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try writeData(bytes, to: history.appendingPathComponent("\(current.id.uuidString).json"))
            try writeData(bytes, to: backup)
            try write(replacement, to: primary)
            return replacement
        }
    }

    /// Snapshot under the same lock as farewell, so archive + current cannot be double-counted.
    /// Reading history never rewrites pet saves or legacy archives.
    public func memorials() throws -> PetMemorialSnapshot {
        guard manager.fileExists(atPath: directory.path) else { return PetMemorialSnapshot() }
        return try locked {
            var records: [UUID: PetMemorial] = [:]
            var unreadable = 0
            let history = directory.appendingPathComponent("pet-history", isDirectory: true)
            if manager.fileExists(atPath: history.path) {
                let files = try manager.contentsOfDirectory(at: history,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                for file in files where file.pathExtension.lowercased() == "json" {
                    do {
                        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                              let expectedID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                            throw PetError.damagedSave
                        }
                        let pet = try decode(file)
                        guard pet.id == expectedID else { throw PetError.damagedSave }
                        if let record = PetMemorial(pet: pet) { records[record.id] = record }
                    } catch { unreadable += 1 }
                }
            }
            if manager.fileExists(atPath: primary.path) {
                do {
                    let properties = try primary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard properties.isRegularFile == true, properties.isSymbolicLink != true else {
                        throw PetError.damagedSave
                    }
                    if let record = PetMemorial(pet: try decode(primary)) { records[record.id] = record }
                } catch { unreadable += 1 }
            }
            return PetMemorialSnapshot(records: Array(records.values), unreadableCount: unreadable)
        }
    }

    private func preserveLegacy(_ data: Data) throws {
        struct Header: Decodable { let saveVersion: Int; let id: UUID }
        let h = try JSONDecoder().decode(Header.self, from: data)
        guard h.saveVersion < 4 else { return }
        let original = directory.appendingPathComponent("pet-v\(h.saveVersion)-original-\(h.id.uuidString).json")
        if !manager.fileExists(atPath: original.path) { try writeData(data, to: original) }
    }

    public func restoreBackup() throws -> Pet {
        try locked {
            // Never downgrade or overwrite a readable newer-version primary.
            if manager.fileExists(atPath: primary.path) {
                do { return try decode(primary) }
                catch PetError.unsupportedVersion { throw PetError.unsupportedVersion }
                catch { /* User explicitly chose recovery after an unreadable primary. */ }
            }
            guard let pet = try? decode(backup) else { throw PetError.noBackup }
            try preserveLegacy(Data(contentsOf: backup))
            if manager.fileExists(atPath: primary.path) {
                let preserved = directory.appendingPathComponent("pet-damaged-\(UUID().uuidString).json")
                try manager.copyItem(at: primary, to: preserved)
            }
            try write(pet, to: primary)
            return pet
        }
    }

    private func decode(_ url: URL) throws -> Pet {
        let data = try Data(contentsOf: url) // Read/permission errors are not treated as missing saves.
        do {
            // Future formats can remove fields required by Pet v1. Reject their version
            // before decoding the old schema, so recovery cannot downgrade future data.
            struct Header: Decodable { let saveVersion: Int }
            let decoder = JSONDecoder()
            guard [1, 2, 3, 4].contains(try decoder.decode(Header.self, from: data).saveVersion) else {
                throw PetError.unsupportedVersion
            }
            return try decoder.decode(Pet.self, from: data).validated()
        }
        catch let error as PetError { throw error }
        catch { throw PetError.damagedSave }
    }

    private func write(_ pet: Pet, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeData(encoder.encode(pet), to: url)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        // Failure to update optional metadata must not report a successful commit as failed.
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func locked<T>(_ action: () throws -> T) throws -> T {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent(".pet.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw PetError.storageUnavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw PetError.storageUnavailable }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
}
