import CareFlow
import AppKit
import SwiftUI
import DesktopCore
import AdoptionFlow
import PetCore

@MainActor
final class DesktopController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var titlebarInset: CGFloat = 0
    @Published private(set) var compact: Bool
    @Published private(set) var shellColor: ShellColor
    @Published private(set) var alwaysOnTop: Bool
    @Published private(set) var preferenceError: String?
    @Published private(set) var animationVisible = false
    private var motionSuspended = false
    private weak var window: NSWindow?
    private var savedFrame: CGRect?
    private let preferencesURL: URL
    private var adjusting = false
    private var lastPersistedPreferences: DesktopPreferences?
    private let ownsSession: Bool
    private let automaticallyRoams: Bool
    private var roamingTimer: Timer?
    private var roamingDeadline: Date?
    private var roamingAnchor: CGRect?
    private var roamingScreen: CGRect?
    private var roamingPath: DesktopWalk?
    private var roamingTick = ProcessInfo.processInfo.systemUptime
    private var dragging = false
    private var roamingReduced = false
    private var roamingSpriteSize: CGFloat = 96
    var isRoaming: Bool { roamingAnchor != nil }


    init(directory: URL, ownsSession: Bool = true, automaticallyRoams: Bool = true) {
        self.automaticallyRoams = automaticallyRoams
        self.ownsSession = ownsSession
        preferencesURL = directory.appendingPathComponent("desktop.json")
        let preferences = (try? Data(contentsOf: preferencesURL))
            .flatMap { try? JSONDecoder().decode(DesktopPreferences.self, from: $0) } ?? DesktopPreferences()
        compact = preferences.compact
        alwaysOnTop = preferences.alwaysOnTop
        let color = preferences.shellColor ?? .default
        shellColor = ShellColor(red: color.red, green: color.green, blue: color.blue)
        savedFrame = preferences.frame
        if FileManager.default.fileExists(atPath: preferencesURL.path) { lastPersistedPreferences = preferences }
        super.init()
        guard ownsSession else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for event in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspendMotion), name: event, object: nil)
        }
        for event in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resumeMotion), name: event, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(suspendMotion), name: CareModel.screenLocked, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(resumeMotion), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func suspendMotion() { motionSuspended = true; updateAnimationVisibility() }
    @objc private func resumeMotion() { motionSuspended = false; updateAnimationVisibility() }

    func attach(_ window: NSWindow) {
        guard ownsSession, self.window !== window else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: self.window)
        self.window = window
        NotificationCenter.default.addObserver(self, selector: #selector(updateAnimationVisibility),
            name: NSWindow.didChangeOcclusionStateNotification, object: window)
        window.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(willDragPet), name: Self.petWillDrag, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(didDragPet), name: Self.petDidDrag, object: window)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.level = alwaysOnTop ? .floating : .normal
        // SwiftUI's hidden-titlebar scene still adds the native titlebar inset
        // to its ideal content height. Compensate in the view layout, not by
        // repeatedly forcing NSWindow.setContentSize from resize callbacks.
        titlebarInset = max(0, window.frame.height - window.contentLayoutRect.maxY)
        fit(saved: savedFrame)
        updateAnimationVisibility()
    }

    @objc private func updateAnimationVisibility() {
        guard let window else { animationVisible = false; return }
        if motionSuspended { window.ignoresMouseEvents = false }
        animationVisible = !motionSuspended && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }
    func windowDidMiniaturize(_ notification: Notification) { updateAnimationVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { updateAnimationVisibility() }

    func show() {
        guard let window else { return }
        fit(saved: window.frame)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateAnimationVisibility()
    }
    func hide() { animationVisible = false; window?.orderOut(nil) }
    func toggleCompact() { compact.toggle(); persist() }
    func setShellColor(_ value: ShellColor) {
        shellColor = ShellColor(red: value.red, green: value.green, blue: value.blue)
        persist()
    }
    func setOnTop(_ value: Bool) {
        alwaysOnTop = value
        window?.level = value ? .floating : .normal
        persist()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func windowDidMove(_ notification: Notification) {
        guard !adjusting, !isRoaming else { return }
        savedFrame = window?.frame; persist()
    }
    func windowDidResize(_ notification: Notification) {
        // SwiftUI Window(.contentSize) owns sizing. Never resize or reposition
        // from this callback: title-bar conversion can create a feedback loop.
        guard !adjusting, !isRoaming else { return }
        savedFrame = window?.frame; persist()
    }
    @objc private func screensChanged() {
        guard let window else { return }
        fit(saved: window.frame)
    }
    private func fit(saved: CGRect?) {
        guard !adjusting, let window else { return }
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard let rect = WindowPlacement.restore(saved: saved, size: window.frame.size, visibleFrames: frames) else { return }
        adjusting = true
        if window.frame != rect { window.setFrame(rect, display: window.isVisible) }
        savedFrame = rect
        adjusting = false
        persist()
    }
    static let petWillDrag = Notification.Name("Tomatogotchi.petWillDrag")
    static let petDidDrag = Notification.Name("Tomatogotchi.petDidDrag")
    @objc private func willDragPet() { dragging = true }
    @objc private func didDragPet() {
        dragging = false
        if let window, isRoaming { roamingPath = DesktopWalk(origin: window.frame.origin) }
        roamingTick = ProcessInfo.processInfo.systemUptime
    }
    func setRoaming(active: Bool, deadline: Date?, reduced: Bool, spriteSize: CGFloat = 96) {
        guard ownsSession, let window else { return }
        roamingReduced = reduced; roamingSpriteSize = spriteSize
        guard active, let deadline, deadline > Date() else { stopRoaming(); return }
        roamingDeadline = deadline
        if roamingAnchor == nil {
            roamingAnchor = window.frame
            roamingScreen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            roamingPath = DesktopWalk(origin: window.frame.origin)
            roamingTick = ProcessInfo.processInfo.systemUptime
        }
        guard automaticallyRoams, roamingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in
                let tick = ProcessInfo.processInfo.systemUptime
                let elapsed = min(0.1, max(0, tick - controller.roamingTick))
                controller.roamingTick = tick
                controller.advanceRoaming(now: Date(), elapsed: elapsed)
            }
        }
        roamingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    /// Exposed internally so native contract tests can drive the exact production adapter.
    func advanceRoaming(now: Date, elapsed: Double, visibleFrames: [CGRect]? = nil, visible: Bool? = nil) {
        guard ownsSession, let window, let deadline = roamingDeadline, isRoaming else { return }
        guard now < deadline else { stopRoaming(); return }
        guard !motionSuspended, !roamingReduced, !dragging,
              visible ?? animationVisible else {
            window.ignoresMouseEvents = false; return
        }
        let frames = visibleFrames ?? NSScreen.screens.map(\.visibleFrame)
        guard let screen = roamingScreen, frames.contains(screen) else { stopRoaming(); return }
        guard var path = roamingPath else { return }
        let point = path.move(elapsed: min(0.1, max(0, elapsed)), windowSize: window.frame.size, visibleFrame: screen)
        roamingPath = path
        adjusting = true; window.setFrameOrigin(point); adjusting = false
        // A small sprite-sized window moves; the rest of the desktop never has an overlay.
        let hit = CGRect(x: window.frame.midX - roamingSpriteSize / 2,
                         y: window.frame.midY - roamingSpriteSize / 2,
                         width: roamingSpriteSize, height: roamingSpriteSize)
        window.ignoresMouseEvents = !hit.contains(NSEvent.mouseLocation)
    }
    private func stopRoaming() {
        roamingTimer?.invalidate(); roamingTimer = nil
        guard let anchor = roamingAnchor else { return }
        roamingAnchor = nil; roamingDeadline = nil; roamingScreen = nil; roamingPath = nil
        guard let window else { return }
        window.ignoresMouseEvents = false
        fit(saved: anchor)
    }
    private func persist() {
        guard ownsSession else { return }
        let preferences = DesktopPreferences(compact: compact, alwaysOnTop: alwaysOnTop, frame: savedFrame, shellColor: shellColor)
        guard preferences != lastPersistedPreferences || preferenceError != nil else { return }
        do {
            try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences).write(to: preferencesURL, options: .atomic)
            lastPersistedPreferences = preferences
            if preferenceError != nil { preferenceError = nil }
        } catch {
            preferenceError = "視窗偏好暫時無法保存；寵物存檔不受影響。"
        }
    }
}

/// Obtains the existing SwiftUI window; never creates a second AppKit window.
struct DesktopWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe(); view.onWindow = onWindow; return view
    }
    func updateNSView(_ nsView: WindowProbe, context: Context) { nsView.onWindow = onWindow }
    final class WindowProbe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                if let window { self?.onWindow?(window) }
            }
        }
    }
}

struct DesktopRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: AdoptionModel
    @ObservedObject var desktop: DesktopController
    @ObservedObject var care: CareModel
    var body: some View {
        Group {
            if model.screen == .home {
                PetDeviceView(model: model, care: care, desktop: desktop)
            } else {
                ContentView(model: model, desktop: desktop, care: care)
            }
        }
        .fixedSize()
        .ignoresSafeArea()
        .padding(.top, -desktop.titlebarInset)
        .preferredColorScheme(.light)
        .environment(\.petMotionVisible, desktop.animationVisible)
        .background(DesktopWindowReader { desktop.attach($0); syncCare() }.frame(width: 0, height: 0))
        .onAppear { syncCare() }
        .onChange(of: model.pet?.id) { _ in syncCare() }
        .onChange(of: model.saving) { saving in if !saving { syncCare() } }
        .onChange(of: model.screen) { _ in syncCare() }
        .onChange(of: care.cycle.phase) { _ in syncCare() }
        .onChange(of: care.cycle.restDeadline) { _ in syncCare() }
        .onChange(of: desktop.compact) { _ in syncCare() }
        .onChange(of: model.pet?.growth.stage) { _ in syncCare() }
        .onChange(of: reduceMotion) { _ in syncCare() }
    }
    private func syncCare() {
        let stage = model.pet?.growth.stage
        desktop.setRoaming(active: model.screen == .home && desktop.compact &&
            (stage == .hatchling || stage == .adult) && care.cycle.phase == .resting &&
            care.cycle.activity == .walk && !care.needsReset,
            deadline: care.cycle.restDeadline, reduced: reduceMotion,
            spriteSize: stage == .hatchling ? 72 : 96)
        guard model.screen == .home, let pet = model.pet, !care.needsReset else { return }
        care.bind(to: pet.id)
        guard !model.saving, model.progressError == nil, pet.growth.stage != .departed,
              let receipt = care.cycle.completedReceipt else { return }
        model.recordRest(receipt)
    }
}

/// SwiftUI content can consume background mouse events even when the window's
/// background-drag flag is enabled. Route actual user drags through AppKit.
struct WindowDragRegion: NSViewRepresentable {
    enum Region { case device, pet }
    var region: Region
    func makeNSView(context: Context) -> DragView { DragView(region: region) }
    func updateNSView(_ nsView: DragView, context: Context) { nsView.region = region }

    final class DragView: NSView {
        var region: Region
        override var isFlipped: Bool { true }
        init(region: Region) { self.region = region; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func resetCursorRects() {
            let height: CGFloat
            switch region { case .device: height = bounds.height * (278.0 / 360.0); case .pet: height = bounds.height }
            addCursorRect(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height), cursor: .openHand)
        }
        func acceptsDrag(at point: NSPoint) -> Bool {
            guard bounds.contains(point) else { return false }
            switch region {
            case .pet: return true
            case .device:
                // All three keys remain SwiftUI buttons; the shell and LCD drag.
                return point.y < bounds.height * (278.0 / 360.0) && DeviceEggShape().path(in: bounds).contains(point)
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard acceptsDrag(at: local) else { return nil }
            // Let SwiftUI receive right-clicks for the pet's restore menu.
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return nil
            default: return super.hitTest(point)
            }
        }
        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            if let window {
                NotificationCenter.default.post(name: DesktopController.petWillDrag, object: window)
                window.performDrag(with: event)
                NotificationCenter.default.post(name: DesktopController.petDidDrag, object: window)
            }
        }
    }
}
