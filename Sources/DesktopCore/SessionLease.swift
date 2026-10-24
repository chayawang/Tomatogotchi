import Foundation
import Darwin

/// A process-lifetime, non-blocking lease scoped to one data directory.
/// Never unlink the lock file: doing so would allow two different locked inodes.
public final class SessionLease {
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }

    public static func acquire(directory: URL) throws -> SessionLease? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(".session.lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw failure() }
        var retained = false
        defer { if !retained { close(fd) } }
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if errno == EINTR { continue }
            if errno == EWOULDBLOCK { return nil }
            throw failure()
        }
        let data = Array("\(getpid())\n".utf8)
        guard ftruncate(fd, 0) == 0 else { throw failure() }
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { bytes in
                Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw failure() }
            offset += written
        }
        retained = true
        return SessionLease(descriptor: fd)
    }

    /// Used only to activate the lock holder, never to decide lock ownership.
    public static func ownerProcessID(directory: URL) -> Int32? {
        guard let text = try? String(contentsOf: directory.appendingPathComponent(".session.lock"), encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        return pid
    }
    private static func failure() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
