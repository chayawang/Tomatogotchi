import Foundation
import CareCore

@MainActor
final class FakeCenter: CareReminderCenter {
    var permissions: [CheckedContinuation<ReminderPermission, Never>] = []
    var resolvedPermissions = 0
    var authorizations: [CheckedContinuation<Bool, Error>] = []
    var additions: [(String, TimeInterval, CheckedContinuation<Void, Error>)] = []
    var removed: [String] = []
    func permission() async -> ReminderPermission {
        let result = await withCheckedContinuation { permissions.append($0) }
        resolvedPermissions += 1
        return result
    }
    func authorize() async throws -> Bool {
        try await withCheckedThrowingContinuation { authorizations.append($0) }
    }
    func add(id: String, delay: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { additions.append((id, delay, $0)) }
    }
    func remove(id: String) { removed.append(id) }
}

@main
struct ReminderChecks {
    @MainActor
    static func until(_ predicate: () -> Bool) async {
        for _ in 0..<10000 {
            if predicate() { return }
            await Task.yield()
        }
        fatalError("Asynchronous test did not reach expected suspension point")
    }
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }
    @MainActor
    static func main() async {
        // Pause while settings are loading: no late permission dialog or add.
        let a = FakeCenter()
        let ra = CareReminder(center: a)
        ra.schedule(after: 1500, mayAuthorize: true)
        await until { a.permissions.count == 1 }
        ra.cancel()
        a.permissions[0].resume(returning: .unknown)
        // A new request serves as a deterministic barrier for the old continuation.
        ra.schedule(after: 1500, mayAuthorize: true)
        await until { a.permissions.count == 2 }
        a.permissions[1].resume(returning: .allowed)
        await until { a.additions.count == 1 }
        check(a.authorizations.isEmpty, "Cancelled settings request must not prompt")
        a.additions[0].2.resume()
        await until { ra.requestID != nil }
        ra.cancel()

        // Old add finishes after a newer round: remove only the old identifier,
        // and suppress a stale error that would overwrite the new round's hint.
        let b = FakeCenter()
        let r = CareReminder(center: b)
        var hints: [String] = []
        r.onHint = { hints.append($0) }
        r.schedule(after: 1500, mayAuthorize: false)
        await until { b.permissions.count == 1 }
        b.permissions[0].resume(returning: .allowed)
        await until { b.additions.count == 1 }
        let oldID = b.additions[0].0
        r.schedule(after: 300, mayAuthorize: false)
        await until { b.permissions.count == 2 }
        b.permissions[1].resume(returning: .allowed)
        await until { b.additions.count == 2 }
        let newID = b.additions[1].0
        b.additions[1].2.resume()
        await until { hints.count == 1 }
        struct Failure: Error {}
        b.additions[0].2.resume(throwing: Failure())
        await until { b.removed.filter { $0 == oldID }.count == 2 }
        check(r.requestID == newID, "Old completion cannot replace new request")
        check(!b.removed.contains(newID), "Old completion cannot remove new request")
        check(hints.count == 1, "Stale failure must not overwrite hint")
        r.cancel()
        check(b.removed.contains(newID), "Cancel removes active notification")

        // Permission request shared across stop/restart; elapsed permission time
        // counts toward the work deadline rather than resetting the duration.
        let c = FakeCenter()
        var date = Date(timeIntervalSince1970: 1000)
        let rc = CareReminder(center: c, now: { date })
        rc.schedule(after: 1500, mayAuthorize: true)
        await until { c.permissions.count == 1 }
        c.permissions[0].resume(returning: .unknown)
        await until { c.authorizations.count == 1 }
        rc.cancel()
        rc.schedule(after: 300, mayAuthorize: false)
        await until { c.permissions.count == 2 }
        c.permissions[1].resume(returning: .unknown)
        await until { c.resolvedPermissions == 2 }
        date = date.addingTimeInterval(120)
        c.authorizations[0].resume(returning: true)
        await until { c.additions.count == 1 }
        check(c.authorizations.count == 1, "Overlapping authorization must coalesce")
        check(c.additions[0].1 == 180, "Permission latency must not extend deadline")
        rc.cancel()
        c.additions[0].2.resume()
        await until { c.removed.filter { $0 == c.additions[0].0 }.count == 2 }
        check(rc.requestID == nil, "Paused late add must remain cancelled")

        // Denial produces an in-app fallback, with no OS request scheduled.
        let d = FakeCenter()
        let denied = CareReminder(center: d)
        var deniedHint: String?
        denied.onHint = { deniedHint = $0 }
        denied.schedule(after: 1500, mayAuthorize: false)
        await until { d.permissions.count == 1 }
        d.permissions[0].resume(returning: .denied)
        await until { deniedHint != nil }
        check(d.additions.isEmpty && d.authorizations.isEmpty, "Denied permission uses fallback")
        // A failed authorization must be released so a later explicit start can retry.
        let e = FakeCenter()
        let retry = CareReminder(center: e)
        var errors = 0
        retry.onHint = { _ in errors += 1 }
        retry.schedule(after: 1500, mayAuthorize: true)
        await until { e.permissions.count == 1 }
        e.permissions[0].resume(returning: .unknown)
        await until { e.authorizations.count == 1 }
        e.authorizations[0].resume(throwing: Failure())
        await until { errors == 1 }
        retry.schedule(after: 1500, mayAuthorize: true)
        await until { e.permissions.count == 2 }
        e.permissions[1].resume(returning: .unknown)
        await until { e.authorizations.count == 2 }
        e.authorizations[1].resume(returning: true)
        await until { e.additions.count == 1 }
        e.additions[0].2.resume(throwing: Failure())
        await until { errors == 2 }
        check(retry.requestID == nil, "Failed add must not retain active request")
        check(e.removed.contains(e.additions[0].0), "Failed add is cleaned up")
        print("PASS: notification cancellation, stale completion, authorization sharing, deadline, denial and failure retry")
    }
}
