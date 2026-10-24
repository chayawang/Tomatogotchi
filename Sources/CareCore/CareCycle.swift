import Foundation

public enum CarePhase: String, Codable, Sendable { case idle, working, needsCare, resting, restComplete, paused }
public enum CareActivity: String, Codable, Sendable {
    case food, walk
    public var title: String { self == .food ? "餵牠吃飯" : "帶牠晃晃" }
    public var needTitle: String { self == .food ? "牠肚子餓了。" : "牠想出去晃晃。" }
}

public struct CareNeedProgress: Equatable, Sendable {
    public let id: UUID
    public let petID: UUID
    public let activity: CareActivity
    public let elapsed: TimeInterval
    public var steps: Int { Int(min(900, max(0, elapsed)) / 180) }
    public init(id: UUID, petID: UUID, activity: CareActivity, elapsed: TimeInterval) {
        self.id = id; self.petID = petID; self.activity = activity; self.elapsed = elapsed
    }
}

public struct CompletedRest: Equatable, Sendable {
    public let id: String
    public let petID: UUID
    public let activity: CareActivity
    public let completedAt: Date
}

public struct CareCycle: Codable, Equatable, Sendable {
    public private(set) var version: Int
    public private(set) var phase: CarePhase
    public private(set) var remainingWork: TimeInterval
    public private(set) var restDeadline: Date?
    public private(set) var activity: CareActivity?
    public private(set) var petID: UUID?
    public private(set) var restID: UUID?
    public private(set) var workDuration: TimeInterval
    public private(set) var breakDuration: TimeInterval
    public private(set) var demand: CareActivity?
    public private(set) var demandID: UUID?
    public private(set) var demandElapsed: TimeInterval = 0
    public var hasPendingNeed: Bool { phase == .needsCare || (phase == .paused && remainingWork == 0) }
    public var needProgress: CareNeedProgress? {
        guard hasPendingNeed, let id = demandID, let petID, let demand else { return nil }
        return CareNeedProgress(id: id, petID: petID, activity: demand, elapsed: demandElapsed)
    }
    public var nextPenaltyRemaining: TimeInterval { 180 - demandElapsed.truncatingRemainder(dividingBy: 180) }
    private enum CodingKeys: String, CodingKey {
        case version, phase, remainingWork, restDeadline, activity, petID, restID, workDuration, breakDuration
        case demand, demandID, demandElapsed
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try c.decode(Int.self, forKey: .version)
        guard [1, 2].contains(storedVersion) else { throw CareError.unsupportedVersion }
        version = 2
        phase = try c.decode(CarePhase.self, forKey: .phase)
        remainingWork = try c.decode(TimeInterval.self, forKey: .remainingWork)
        workDuration = try c.decode(TimeInterval.self, forKey: .workDuration)
        breakDuration = try c.decode(TimeInterval.self, forKey: .breakDuration)
        restDeadline = try c.decodeIfPresent(Date.self, forKey: .restDeadline)
        activity = try c.decodeIfPresent(CareActivity.self, forKey: .activity)
        petID = try c.decodeIfPresent(UUID.self, forKey: .petID)
        restID = try c.decodeIfPresent(UUID.self, forKey: .restID)
        if storedVersion == 2 {
            demand = try c.decodeIfPresent(CareActivity.self, forKey: .demand)
            demandID = try c.decodeIfPresent(UUID.self, forKey: .demandID)
            demandElapsed = try c.decode(TimeInterval.self, forKey: .demandElapsed)
        } else {
            // Migrate existing pending work without charging historical waiting.
            demand = phase == .idle || phase == .resting || phase == .restComplete ? nil : .food
            demandID = demand == nil ? nil : UUID()
            demandElapsed = 0
        }
        _ = try validated()
    }

    public init(workDuration: TimeInterval = 25 * 60, breakDuration: TimeInterval = 5 * 60) throws {
        guard workDuration.isFinite, breakDuration.isFinite, workDuration > 0, breakDuration > 0 else { throw CareError.invalidState }
        version = 2; phase = .idle; remainingWork = workDuration
        restDeadline = nil; activity = nil
        self.workDuration = workDuration; self.breakDuration = breakDuration
    }
    /// Change the next work round without discarding a rest or its growth receipt.
    /// Existing work can be shortened, but increasing the duration never grants
    /// extra time to a round already in progress.
    public mutating func setWorkDuration(_ seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds > 0 else { throw CareError.invalidState }
        guard workDuration != seconds else { return }
        workDuration = seconds
        remainingWork = phase == .idle ? seconds : min(remainingWork, seconds)
    }
    /// User preferences can only change an idle round, never an active deadline.
    public mutating func configure(workMinutes: Int, breakMinutes: Int) throws {
        guard phase == .idle, (1...1440).contains(workMinutes), (1...1440).contains(breakMinutes) else {
            throw CareError.invalidState
        }
        workDuration = Double(workMinutes) * 60
        breakDuration = Double(breakMinutes) * 60
        remainingWork = workDuration
    }
    public mutating func bind(to id: UUID) {
        if let petID, petID != id { stop() }
        petID = id
    }
    public var completedReceipt: CompletedRest? {
        guard phase == .restComplete, let petID, let deadline = restDeadline, let activity else { return nil }
        // Old v1 timer saves have no UUID; the persisted deadline gives a stable receipt.
        let key = restID?.uuidString ?? "legacy-\(deadline.timeIntervalSinceReferenceDate.bitPattern)-\(activity.rawValue)-\(breakDuration.bitPattern)"
        return CompletedRest(id: key, petID: petID, activity: activity, completedAt: deadline)
    }
    public func canLeaveCompletedRest(afterSaving receipt: CompletedRest?) -> Bool {
        guard phase == .restComplete else { return true }
        guard let receipt, let current = completedReceipt else { return false }
        return receipt == current
    }
    public mutating func start(demand: CareActivity = .food) {
        guard phase == .idle || phase == .restComplete else { return }
        phase = .working; remainingWork = workDuration; restDeadline = nil; activity = nil; restID = nil
        self.demand = demand; demandID = UUID(); demandElapsed = 0
    }
    public mutating func advance(workElapsed: TimeInterval, now: Date) {
        guard now.timeIntervalSince1970.isFinite else { return }
        if phase == .working && workElapsed.isFinite && workElapsed >= 0 {
            let overdue = max(0, workElapsed - remainingWork)
            remainingWork = max(0, remainingWork - workElapsed)
            if remainingWork == 0 { phase = .needsCare; demandElapsed = min(900, demandElapsed + overdue) }
        } else if phase == .needsCare, workElapsed.isFinite, workElapsed >= 0 {
            demandElapsed = min(900, demandElapsed + workElapsed)
        } else if phase == .resting, let deadline = restDeadline, now >= deadline {
            phase = .restComplete
        }
    }
    public mutating func rest(_ activity: CareActivity, now: Date, id: UUID = UUID()) {
        guard phase == .working || phase == .needsCare || phase == .paused,
              now.timeIntervalSince1970.isFinite else { return }
        if hasPendingNeed && demand != activity { return }
        self.activity = activity; restID = id; restDeadline = now.addingTimeInterval(breakDuration); phase = .resting
    }
    public mutating func snooze() {
        guard phase == .needsCare else { return }
        // A pending need cannot be exchanged for extra work time.
        return
    }
    public mutating func pause() {
        if phase == .working || phase == .needsCare { phase = .paused }
    }
    public mutating func resume() {
        if phase == .paused { phase = remainingWork == 0 ? .needsCare : .working }
    }
    public mutating func stop() {
        phase = .idle; remainingWork = workDuration; restDeadline = nil; activity = nil; restID = nil
        demand = nil; demandID = nil; demandElapsed = 0
    }
    public func restRemaining(now: Date) -> TimeInterval {
        guard phase == .resting, let deadline = restDeadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }
    public func validated() throws -> CareCycle {
        guard version == 2 else { throw CareError.unsupportedVersion }
        guard workDuration.isFinite, breakDuration.isFinite, remainingWork.isFinite,
              workDuration > 0, breakDuration > 0, remainingWork >= 0,
              remainingWork <= max(workDuration, 5 * 60),
              restDeadline?.timeIntervalSince1970.isFinite ?? true else { throw CareError.invalidState }
        if phase == .resting || phase == .restComplete {
            guard restDeadline != nil && activity != nil else { throw CareError.invalidState }
        } else if restDeadline != nil || activity != nil || restID != nil { throw CareError.invalidState }
        guard demandElapsed.isFinite, demandElapsed >= 0, demandElapsed <= 900 else { throw CareError.invalidState }
        guard (demand == nil) == (demandID == nil) else { throw CareError.invalidState }
        if phase == .idle && (demand != nil || demandElapsed != 0) { throw CareError.invalidState }
        if phase == .working && demandElapsed != 0 { throw CareError.invalidState }
        if phase == .working || hasPendingNeed {
            guard demand != nil && demandID != nil else { throw CareError.invalidState }
        }
        if phase == .needsCare && remainingWork != 0 { throw CareError.invalidState }
        if phase == .working && remainingWork == 0 { throw CareError.invalidState }
        return self
    }
    public mutating func recoverAfterLaunch(now: Date) {
        pause()
        advance(workElapsed: 0, now: now)
    }
}

public enum CareError: Error { case invalidState, unsupportedVersion }
