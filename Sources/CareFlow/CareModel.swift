import AppKit
import Combine
import UserNotifications
import CareCore

@MainActor
public final class CareModel: NSObject, ObservableObject {
    // Preserve the existing App default for new users; stored preferences take precedence.
    public static let defaultWorkDuration: TimeInterval = 5 * 60
    @Published public private(set) var cycle: CareCycle
    @Published public private(set) var clock = Date()
    @Published public private(set) var storageError: String?
    @Published public private(set) var needsReset = false
    @Published public private(set) var notificationHint = "開始陪伴後，可選擇開啟系統通知。"
    public var onNeedUpdate: ((CareNeedProgress) -> Void)?
    private let chooseDemand: () -> CareActivity
    private let lockNotifications: NotificationCenter
    public static let screenLocked = Notification.Name("Tomatogotchi.screenLocked")
    private let store: CareStore
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var lastCheckpoint: TimeInterval = 0
    private let reminder: CareReminder
    private let reminderCenter: CareReminderCenter
    private let workspaceNotifications: NotificationCenter
    private let now: () -> Date
    private let uptimeNow: () -> TimeInterval
    private let notificationPrefix: String
    // Secondary launches only activate the existing process. They must not
    // cancel its reminders or persist their own snapshot while terminating.
    private let ownsSession: Bool

    public init(directory: URL, ownsSession: Bool,
                reminderCenter: CareReminderCenter? = nil,
                workspaceNotifications: NotificationCenter? = nil,
                lockNotifications: NotificationCenter = .default,
                chooseDemand: @escaping () -> CareActivity = { Bool.random() ? .food : .walk },
                automaticallyTicks: Bool = true,
                now: @escaping () -> Date = Date.init,
                uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        let center = reminderCenter ?? SystemCareReminderCenter()
        self.reminderCenter = center
        let namespace = CareReminder.namespace(directory: directory)
        self.notificationPrefix = namespace
        self.reminder = CareReminder(center: center, now: now, namespace: namespace)
        let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("work.shiroi.tomatogotchi", isDirectory: true)
        let canCleanLegacy = directory.standardizedFileURL.resolvingSymlinksInPath()
            == defaultDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.workspaceNotifications = workspaceNotifications ?? NSWorkspace.shared.notificationCenter
        self.now = now; self.uptimeNow = uptime
        self.chooseDemand = chooseDemand; self.lockNotifications = lockNotifications
        store = CareStore(directory: directory)
        self.ownsSession = ownsSession
        var initial = try! CareCycle(workDuration: Self.defaultWorkDuration)
        var loadFailure: String?
        do {
            initial = try store.load() ?? initial
            initial.recoverAfterLaunch(now: now())
        }
        catch { loadFailure = "計時資料暫時無法讀取。原檔與寵物會保留，可重設這次計時。" }
        cycle = initial
        storageError = loadFailure
        needsReset = loadFailure != nil
        super.init()
        clock = now(); lastTick = uptime(); lastCheckpoint = uptime()
        guard ownsSession else { return }
        reminder.onHint = { [weak self] in self?.notificationHint = $0 }
        if automaticallyTicks {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                guard let model = self else { return }
                Task { @MainActor in model.refresh() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            self.workspaceNotifications.addObserver(self, selector: #selector(systemPaused), name: name, object: nil)
        }
        lockNotifications.addObserver(self, selector: #selector(systemPaused), name: Self.screenLocked, object: nil)
        Task { [weak self] in
            let existing = await center.existingIDs()
            guard let self else { return }
            for id in existing where id != self.reminder.requestID &&
                (id.hasPrefix(self.notificationPrefix) || (canCleanLegacy && CareReminder.isLegacyRequest(id))) {
                center.remove(id: id)
            }
        }
    }

    public var compactStatus: String {
        switch cycle.phase {
        case .idle: return "先一起待著吧。"
        case .working: return "牠在旁邊陪你。"
        case .needsCare: return cycle.demand?.needTitle ?? "牠需要你。"
        case .resting: return "去休息，回來再看牠。"
        case .restComplete: return "慢慢來，回來再繼續。"
        case .paused: return "陪伴暫停中。"
        }
    }
    public var workTime: String { CountdownDisplay.text(seconds: cycle.remainingWork) }
    public var startTitle: String { "開始工作" }
    public var scheduleDescription: String { "工作 \(Int(cycle.workDuration / 60)) 分鐘，再離席 \(Int(cycle.breakDuration / 60)) 分鐘。" }
    public var showsWorkCountdown: Bool { cycle.phase == .working || (cycle.phase == .paused && !cycle.hasPendingNeed) }
    public var needTime: String { CountdownDisplay.text(seconds: cycle.nextPenaltyRemaining) }
    public var restTime: String {
        CountdownDisplay.text(seconds: cycle.restRemaining(now: clock))
    }
    public var canConfigureSchedule: Bool {
        ownsSession && !needsReset && (cycle.phase == .idle || cycle.phase == .restComplete)
    }
    /// Completed growth must be saved before leaving the previous round.
    public func configureSchedule(workMinutes: String, breakMinutes: String,
                                  afterSaving receipt: CompletedRest? = nil) -> String? {
        guard let work = Int(workMinutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              let rest = Int(breakMinutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...1440).contains(work), (1...1440).contains(rest) else {
            return "請輸入 1 到 1440 的整數分鐘。"
        }
        guard canConfigureSchedule, cycle.canLeaveCompletedRest(afterSaving: receipt) else {
            return "請先收工，或等這次休息的成長保存完成，再設定下一輪。"
        }
        change {
            if $0.phase == .restComplete { $0.stop() }
            try! $0.configure(workMinutes: work, breakMinutes: rest)
        }
        return storageError
    }
    public func bind(to petID: UUID) { change { $0.bind(to: petID) } }
    public func start(for petID: UUID? = nil, afterSaving receipt: CompletedRest? = nil) {
        guard !needsReset, let owner = petID ?? cycle.petID else { return }
        let changed = change {
            guard $0.canLeaveCompletedRest(afterSaving: receipt) else { return }
            $0.bind(to: owner); $0.start(demand: chooseDemand())
        }
        if changed, cycle.phase == .working { reminder.schedule(after: cycle.remainingWork, mayAuthorize: true) }
    }
    public func rest(_ activity: CareActivity) { change { $0.rest(activity, now: now()) } }
    public func snooze() {
        if change({ $0.snooze() }), cycle.phase == .working {
            reminder.schedule(after: cycle.remainingWork, mayAuthorize: false)
        }
    }
    public func pause() { change { $0.pause() } }
    public func resume() {
        if change({ $0.resume() }), cycle.phase == .working {
            reminder.schedule(after: cycle.remainingWork, mayAuthorize: false)
        }
    }
    public func stop(afterSaving receipt: CompletedRest? = nil) {
        change {
            guard $0.canLeaveCompletedRest(afterSaving: receipt) else { return }
            $0.stop()
        }
    }
    public func prepareToQuit() {
        guard ownsSession else { return }
        refresh(); cycle.pause(); cancelNotification(); persist()
    }
    public func reset() {
        guard ownsSession else { return }
        do {
            var fresh = try store.reset()
            try fresh.setWorkDuration(Self.defaultWorkDuration)
            cycle = fresh; needsReset = false; storageError = nil
            lastTick = uptimeNow()
            persist()
        }
        catch { storageError = "暫時無法重設計時，請保留檔案後再試。" }
    }
    /// System inactivity must not refresh a potentially delayed tick before
    /// pausing: that would charge locked/sleeping time when an event arrives late.
    @objc private func systemPaused() { pauseForSafety() }
    public func pauseForSafety() {
        guard ownsSession, !needsReset else { return }
        cycle.pause(); lastTick = uptimeNow(); clock = now(); cancelNotification(); persist()
    }
    @discardableResult
    private func change(_ action: (inout CareCycle) -> Void) -> Bool {
        guard ownsSession, !needsReset else { return false }
        refresh()
        let previous = cycle
        action(&cycle)
        lastTick = uptimeNow()
        guard previous != cycle else { return false }
        cancelNotification()
        persist()
        return true
    }
    public func refresh(deliverNeed: Bool = true) {
        clock = now()
        let uptime = uptimeNow()
        let elapsed = max(0, uptime - lastTick)
        lastTick = uptime
        guard ownsSession, !needsReset else { return }
        let phase = cycle.phase
        let previousSteps = cycle.needProgress?.steps
        cycle.advance(workElapsed: elapsed, now: clock)
        if phase != cycle.phase || previousSteps != cycle.needProgress?.steps {
            if cycle.phase != .needsCare { cancelNotification() }
            persist()
        } else if (cycle.phase == .working || cycle.phase == .needsCare) && uptime - lastCheckpoint >= 10 {
            persist()
        }
        if deliverNeed, storageError == nil, let progress = cycle.needProgress { onNeedUpdate?(progress) }
    }
    private func persist() {
        guard !needsReset else { return }
        do { try store.save(cycle); storageError = nil; lastCheckpoint = uptimeNow() }
        catch {
            cycle.pause(); cancelNotification(); lastTick = uptimeNow(); needsReset = true
            storageError = "計時還沒存好，已停止。原檔會保留，請重設這次計時。"
        }
    }
    private func cancelNotification() { reminder.cancel() }
}

@MainActor
private final class SystemCareReminderCenter: CareReminderCenter {
    private let center = UNUserNotificationCenter.current()
    func permission() async -> ReminderPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: return .allowed
        case .notDetermined: return .unknown
        default: return .denied
        }
    }
    func authorize() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }
    func add(id: String, delay: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = "小傢伙需要你了。"
        content.body = "看看牠想吃飯還是晃晃；每 3 分鐘未回應會扣一格。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    func existingIDs() async -> [String] {
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        return pending.map(\.identifier) + delivered.map { $0.request.identifier }
    }
    func remove(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
