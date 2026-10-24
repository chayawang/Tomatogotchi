import Foundation
import CryptoKit

public enum ReminderPermission { case unknown, allowed, denied }

@MainActor
public protocol CareReminderCenter: AnyObject {
    func permission() async -> ReminderPermission
    func authorize() async throws -> Bool
    func add(id: String, delay: TimeInterval) async throws
    func remove(id: String)
    func existingIDs() async -> [String]
}

public extension CareReminderCenter {
    func existingIDs() async -> [String] { [] }
}

/// A generation owns each asynchronous scheduling attempt. A cancelled attempt
/// may finish later, but can only remove its own request, never a newer one.
@MainActor
public final class CareReminder {
    public private(set) var requestID: String?
    public var onHint: ((String) -> Void)?
    private let center: CareReminderCenter
    private let now: () -> Date
    private let requestPrefix: String
    private var generation = UUID()
    private var authorization: Task<Bool, Error>?
    public static let prefix = "work.shiroi.tomatogotchi.care."

    public static func namespace(directory: URL) -> String {
        let path = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return prefix + digest + "."
    }

    public static func isLegacyRequest(_ id: String) -> Bool {
        guard id.hasPrefix(prefix) else { return false }
        return UUID(uuidString: String(id.dropFirst(prefix.count))) != nil
    }

    public init(center: CareReminderCenter, now: @escaping () -> Date = Date.init, namespace: String? = nil) {
        self.center = center
        self.now = now
        self.requestPrefix = namespace ?? Self.prefix
    }

    public func cancel() {
        generation = UUID()
        if let id = requestID { center.remove(id: id) }
        requestID = nil
    }

    public func schedule(after seconds: TimeInterval, mayAuthorize: Bool) {
        cancel()
        let token = generation
        let deadline = now().addingTimeInterval(max(0, seconds))
        Task { await schedule(token: token, deadline: deadline, mayAuthorize: mayAuthorize) }
    }

    private func schedule(token: UUID, deadline: Date, mayAuthorize: Bool) async {
        var permission = await center.permission()
        guard generation == token else { return }
        if permission == .unknown, mayAuthorize || authorization != nil {
            // Keep an already visible OS permission request shared across rounds.
            // Cancellation cannot dismiss the OS prompt, but prevents scheduling.
            let task: Task<Bool, Error>
            if let existing = authorization { task = existing }
            else {
                task = Task {
                    defer { self.authorization = nil }
                    guard self.generation == token else { return false }
                    return try await center.authorize()
                }
                authorization = task
            }
            do {
                let allowed = try await task.value
                guard generation == token else { return }
                permission = allowed ? .allowed : .denied
            } catch {
                guard generation == token else { return }
                onHint?("系統通知暫時無法開啟，仍可使用 App 內提示。")
                return
            }
        }
        guard generation == token else { return }
        guard permission == .allowed else {
            onHint?("系統通知未開啟；回來時仍會看到照顧提示。")
            return
        }
        // Time spent in the permission dialog belongs to the current work round.
        let id = requestPrefix + UUID().uuidString
        requestID = id
        do {
            try await center.add(id: id, delay: max(1, deadline.timeIntervalSince(now())))
            guard generation == token else { center.remove(id: id); return }
            onHint?("照顧牠的時候，會用系統通知提醒你。")
        } catch {
            guard generation == token else { center.remove(id: id); return }
            center.remove(id: id)
            requestID = nil
            onHint?("系統提醒暫時無法排程，仍可使用 App 內提示。")
        }
    }
}
