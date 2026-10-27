import SwiftUI
import AdoptionFlow
import CareFlow
import CareCore
import PetCore
import DesktopCore

/// Shared with the editable Figma device: 48 × 60, orthogonal pixel steps.
struct DeviceEggShape: Shape {
    static let outline: [[CGFloat]] = [
        [16,0],[32,0],[32,1],[36,1],[36,3],[40,3],[40,6],[43,6],
        [43,10],[45,10],[45,15],[47,15],[47,21],[48,21],[48,41],
        [47,41],[47,50],[45,50],[45,53],[42,53],[42,56],[39,56],
        [39,58],[34,58],[34,60],[14,60],[14,58],[9,58],[9,56],
        [6,56],[6,53],[3,53],[3,50],[1,50],[1,41],[0,41],[0,21],[1,21],[1,15],[3,15],
        [3,10],[5,10],[5,6],[8,6],[8,3],[12,3],[12,1],[16,1]
    ]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (i, v) in Self.outline.enumerated() {
            let point = CGPoint(x: r.minX + v[0] / 48 * r.width, y: r.minY + v[1] / 60 * r.height)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

enum DevicePalette {
    static let outline = Color(red: 48/255, green: 56/255, blue: 87/255)
    static let shell = Color(red: 131/255, green: 157/255, blue: 242/255)
    static let highlight = Color(red: 189/255, green: 207/255, blue: 255/255)
    static let lcd = Color(red: 223/255, green: 233/255, blue: 215/255)
}

enum DeviceSpacing {
    static let fullScreen: CGFloat = 9
    static let compactScreen: CGFloat = 6
    static let keyLabel: CGFloat = 5
    static let fullKeys: CGFloat = 26
    static let compactKeys: CGFloat = 17
}

struct PixelBezel: Shape {
    var step: CGFloat = 8
    func path(in r: CGRect) -> Path {
        let s = min(step, min(r.width, r.height) / 4)
        return Path { p in
            p.move(to: CGPoint(x: r.minX+s, y: r.minY))
            for point in [CGPoint(x:r.maxX-s,y:r.minY),CGPoint(x:r.maxX-s,y:r.minY+s),
                          CGPoint(x:r.maxX,y:r.minY+s),CGPoint(x:r.maxX,y:r.maxY-s),
                          CGPoint(x:r.maxX-s,y:r.maxY-s),CGPoint(x:r.maxX-s,y:r.maxY),
                          CGPoint(x:r.minX+s,y:r.maxY),CGPoint(x:r.minX+s,y:r.maxY-s),
                          CGPoint(x:r.minX,y:r.maxY-s),CGPoint(x:r.minX,y:r.minY+s),
                          CGPoint(x:r.minX+s,y:r.minY+s)] { p.addLine(to: point) }
            p.closeSubpath()
        }
    }
}

struct DeviceShell<Screen: View, Controls: View>: View {
    var shellColor: ShellColor = .default
    @ViewBuilder let screen: Screen
    @ViewBuilder let controls: Controls
    private let width: CGFloat = 288
    private let height: CGFloat = 360
    var body: some View {
        ZStack(alignment: .top) {
            DeviceEggShape().fill(DevicePalette.outline)
            ZStack {
                DeviceEggShape().fill(Color(red: shellColor.red * 0.55 + 0.45, green: shellColor.green * 0.55 + 0.45, blue: shellColor.blue * 0.55 + 0.45))
                DeviceEggShape().fill(Color(red: shellColor.red, green: shellColor.green, blue: shellColor.blue))
                    .offset(x: 6, y: 6)
            }.clipShape(DeviceEggShape()).padding(6)
            VStack(spacing: 0) {
                Text("TOMATOGOTCHI").font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2).foregroundStyle(shellColor.needsLightLabels ? Color.white : DevicePalette.outline)
                    .padding(.top, 34)
                screen
                    .frame(width: 200, height: 200)
                    .background(DevicePalette.lcd)
                    .clipShape(PixelBezel())
                    .padding(6)
                    .background(DevicePalette.outline, in: PixelBezel())
                    .padding(.top, 8)
                controls.padding(.top, 12)

            }
        }
        .frame(width: width, height: height)
        .overlay(WindowDragRegion(region: .device))
        .contentShape(DeviceEggShape())
        .clipShape(DeviceEggShape())
        .padding(10)
        .foregroundStyle(Theme.ink)
    }
}

/// Original 9 × 9 icon bitmaps, also used as editable vectors in Figma.
struct DevicePixelIcon: View {
    let symbol: String
    static func rows(for symbol: String) -> [String] {
        switch symbol {
        case "pause.fill": return ["000000000","011000110","011000110","011000110","011000110","011000110","011000110","011000110","000000000"]
        case "stop.fill": return ["000000000","011111110","011111110","011111110","011111110","011111110","011111110","011111110","000000000"]
        case "ellipsis": return ["000000000","000000000","000000000","000000000","110110110","110110110","000000000","000000000","000000000"]
        case "fork.knife": return ["101010010","101010010","111110010","001000010","001000110","001000010","001000010","001000010","000000000"]
        case "figure.walk": return ["000011000","000011000","000100000","001110000","010101000","000100100","001010000","010001000","100000100"]
        case "cup.and.saucer": return ["001001000","010010000","000000000","111111100","100001010","100001010","011110100","000000000","111111110"]
        case "sparkles": return ["000010000","000010010","000111000","011111110","000111000","000010000","010000000","111000000","010000000"]
        default: return ["001000000","001100000","001110000","001111000","001111100","001111000","001110000","001100000","001000000"]
        }
    }
    var body: some View {
        Canvas { context, size in
            let cell = size.width / 9
            for (y, row) in Self.rows(for: symbol).enumerated() {
                for (x, bit) in row.enumerated() where bit == "1" {
                    context.fill(Path(CGRect(x: CGFloat(x)*cell, y: CGFloat(y)*cell, width: cell, height: cell)), with: .foreground, style: FillStyle(antialiased: false))
                }
            }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }
}

private extension ShellColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
}

struct DeviceKey: View {
    let title: String
    let symbol: String
    var primary = false
    var shellColor: ShellColor = .default
    private var palette: ShellButtonPalette { shellColor.buttonPalette }
    var lightLabel = false
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            VStack(spacing: DeviceSpacing.keyLabel) {
                DevicePixelIcon(symbol: symbol)
                    .foregroundStyle((primary ? palette.primaryInk : palette.secondaryInk).swiftUIColor)
                    .frame(width: 40, height: 32)
                    .background((primary ? palette.primary : palette.secondary).swiftUIColor, in: PixelBezel(step: 4))
                    .padding(4)
                    .background(palette.border.swiftUIColor, in: PixelBezel(step: 8))
                Text(title).font(Theme.font(10)).lineLimit(1)
                    .foregroundStyle(lightLabel ? Color.white : DevicePalette.outline)
            }.opacity(enabled ? 1 : 0.35)
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

struct VitalMeter: View {
    let label: String
    let value: Int
    var body: some View {
        HStack(spacing: 3) {
            Text(label).font(Theme.font(9))
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(i < value ? Theme.ink : Theme.ink.opacity(0.12))
                    .frame(width: 8, height: 7)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label)，\(value)／5 格")
    }
}

enum DevicePresentation {
    static let scale: CGFloat = 0.8
    // 308 * 0.8 = 246.4pt; fit the artwork in integral window points.
    static let size = CGSize(width: 247, height: 304)
}

struct PetDeviceView: View {
    @ObservedObject var model: AdoptionModel
    @ObservedObject var care: CareModel
    @ObservedObject var desktop: DesktopController
    @State private var menuOpen = false
    private var pet: Pet? { model.pet }
    private var dead: Bool { pet?.growth.stage == .departed }
    private var lightLabel: Bool { desktop.shellColor.needsLightLabels }
    private var receiptSaved: Bool { model.hasSavedRest(care.cycle.completedReceipt) }
    private var pending: Bool { care.cycle.hasPendingNeed }
    private var title: String {
        if dead { return model.farewellConfirming ? "準備好重新領蛋嗎？" : "好好跟牠說再見。" }
        if care.needsReset { return "計時需要重新開始。" }
        if let _ = model.progressError { return "還沒存好，先停一下。" }
        if care.cycle.phase == .paused { return "先停一下，也很好。" }
        if pending { return care.cycle.demand?.needTitle ?? "牠需要你。" }
        if care.cycle.phase == .working { return "牠在旁邊陪你。" }
        if care.cycle.phase == .resting { return care.cycle.activity == .food ? "牠在吃飯，你去休息。" : "一起離開電腦晃晃。" }
        if care.cycle.phase == .restComplete { return "休息好了，慢慢來。" }
        return "今天也一起待著吧。"
    }
    private var visualContext: PetVisualContext {
        if care.cycle.phase == .resting { return care.cycle.activity == .food ? .eating : .walking }
        if care.cycle.phase == .paused || care.cycle.phase == .idle { return .sleeping }
        if care.cycle.phase == .restComplete { return .completed }
        return .wandering
    }
    private var time: String {
        if dead { return "" }
        if pending { return care.needTime }
        if care.cycle.phase == .resting { return care.restTime }
        if care.showsWorkCountdown { return care.workTime }
        return ""
    }
    private var note: String {
        if dead {
            if pet?.growth.deathReason == .sadness { return "心情歸零 · 憂鬱離世" }
            return pet?.growth.deathReason == .hunger ? "健康歸零 · 餓死" : "這段陪伴會留在這台 Mac"
        }
        if care.needsReset { return care.storageError ?? "原本的寵物會保留。" }
        if let error = model.progressError ?? care.storageError { return error }
        if pending { return care.cycle.phase == .paused ? "已暫停 · 倒數停止，不扣格" : "距離下次扣格 · 每 3 分鐘一格" }
        if care.cycle.phase == .idle { return care.scheduleDescription }
        if care.cycle.phase == .resting { return "不用盯著螢幕；晚回也沒關係" }
        if care.cycle.phase == .restComplete { return model.saving ? "正在記住這次成長…" : pet?.growth.label ?? "休息完成" }
        return care.cycle.phase == .paused ? "準備好時，再繼續" : "工作剩餘時間"
    }
    var body: some View {
        Group {
            if desktop.compact {
                PetOnlyView(pet: pet, hatchingRequestID: care.hatchingPresentationID, onHatchingReady: care.confirmHatchingPresentation, attention: care.completionNoticeID != nil && !dead, acknowledge: care.acknowledgeCompletion, visualContext: visualContext, roamsDesktop: care.cycle.phase == .resting && care.cycle.activity == .walk && (pet?.growth.stage == .hatchling || pet?.growth.stage == .adult)) { desktop.toggleCompact() }
            } else {
                device.scaleEffect(DevicePresentation.scale)
                    .frame(width: DevicePresentation.size.width, height: DevicePresentation.size.height)
            }
        }
    }
    private var device: some View {
        DeviceShell(shellColor: desktop.shellColor) {
            VStack(spacing: DeviceSpacing.compactScreen) {
                Text(pet?.displayName ?? "小傢伙").font(Theme.font(11, bold: true))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    VitalMeter(label: "健康", value: pet?.growth.health ?? 5)
                    VitalMeter(label: "心情", value: pet?.growth.mood ?? 5)
                }
                PetStage(pet: pet, height: 78, framed: false, visualContext: visualContext, hatchingRequestID: care.hatchingPresentationID, onHatchingReady: care.confirmHatchingPresentation)
                    .modifier(CompletionAttention(active: care.completionNoticeID != nil && !dead))
                    .background(Color.clear)
                Text(title).font(Theme.font(11, bold: true))
                    .multilineTextAlignment(.center).lineLimit(2)
                if !time.isEmpty { Text(time).font(.system(size: 22, weight: .medium, design: .monospaced)).accessibilityLabel(time) }
                Text(care.completionNoticeID != nil && !dead ? "時間到了，準備休息吧" : note).font(Theme.font(9)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 8).padding(.vertical, 10)
        } controls: {
            HStack(alignment: .top, spacing: DeviceSpacing.compactKeys) {
                DeviceKey(title: leftTitle, symbol: leftSymbol, shellColor: desktop.shellColor, lightLabel: lightLabel, action: leftAction)
                    .disabled(model.saving || (dead && !model.farewellConfirming))
                DeviceKey(title: mainTitle, symbol: mainSymbol, primary: true, shellColor: desktop.shellColor, lightLabel: lightLabel, action: mainAction)
                    .disabled(model.saving || care.hatchingPresentationID != nil || (care.cycle.phase == .restComplete && !receiptSaved && model.progressError == nil && !dead))
                    .keyboardShortcut(.defaultAction)
                DeviceKey(title: "選單", symbol: "ellipsis", shellColor: desktop.shellColor, lightLabel: lightLabel) { menuOpen.toggle() }
                    .popover(isPresented: $menuOpen, arrowEdge: .top) {
                        DeviceMenuView(desktop: desktop, care: care, savedReceipt: receiptSaved ? care.cycle.completedReceipt : nil,
                            canRename: !model.saving && !dead,
                            canStop: care.cycle.phase != .idle && !dead && !model.saving,
                            rename: { model.edit(); menuOpen = false },
                            stop: { care.stop(afterSaving: receiptSaved ? care.cycle.completedReceipt : nil); menuOpen = false },
                            dismiss: { menuOpen = false })
                    }
            }
        }
    }
    private var mainTitle: String {
        if dead { return model.farewellConfirming ? "確認領蛋" : "告別" }
        if care.needsReset { return "重設計時" }
        if model.progressError != nil { return "重試保存" }
        if pending { return care.cycle.demand?.title ?? "照顧牠" }
        switch care.cycle.phase {
        case .idle: return "開始工作"
        case .working: return "提早休息"
        case .resting: return "休息中"
        case .restComplete: return "繼續工作"
        case .paused: return "繼續工作"
        case .needsCare: return "照顧牠"
        }
    }
    private var mainSymbol: String {
        if dead { return "sparkles" }
        if pending { return care.cycle.demand == .walk ? "figure.walk" : "fork.knife" }
        return care.cycle.phase == .working || care.cycle.phase == .resting ? "cup.and.saucer" : "play.fill"
    }
    private var leftTitle: String {
        if dead { return "先不要" }
        return care.cycle.phase == .working || care.cycle.phase == .needsCare ? "暫停" : care.cycle.phase == .resting ? "結束休息" : "收工"
    }
    private var leftSymbol: String { care.cycle.phase == .working || care.cycle.phase == .needsCare ? "pause.fill" : "stop.fill" }
    private func mainAction() {
        if dead {
            if model.farewellConfirming { care.stop(); model.farewell() } else { model.farewellConfirming = true }
        } else if care.needsReset { care.reset() }
        else if model.progressError != nil {
            if care.cycle.needProgress != nil { CareActions.respond(model: model, care: care) }
            else if let receipt = care.cycle.completedReceipt { model.recordRest(receipt) }
        } else if pending { CareActions.respond(model: model, care: care) }
        else {
            switch care.cycle.phase {
            case .idle: care.start(for: pet?.id)
            case .working: care.rest(.food)
            case .paused: care.resume()
            case .restComplete: care.start(for: pet?.id, afterSaving: receiptSaved ? care.cycle.completedReceipt : nil)
            case .resting: desktop.hide()
            case .needsCare: break
            }
        }
    }
    private func leftAction() {
        if dead { model.farewellConfirming = false }
        else if care.cycle.phase == .working || care.cycle.phase == .needsCare { care.pause() }
        else { care.stop(afterSaving: receiptSaved ? care.cycle.completedReceipt : nil) }
    }
}

/// A separate transparent presentation of the same pet and care session.
struct PetOnlyView: View {
    @Environment(\.openWindow) private var openWindow
    let pet: Pet?
    var hatchingRequestID: UUID?
    var onHatchingReady: ((UUID) -> Void)?
    var attention = false
    var acknowledge: () -> Void = {}
    var visualContext: PetVisualContext = .wandering
    var roamsDesktop = false
    var restore: () -> Void
    var body: some View {
        PetStage(pet: pet, height: 112, framed: false, visualContext: visualContext, movesWithinContainer: !roamsDesktop, hatchingRequestID: hatchingRequestID, onHatchingReady: onHatchingReady)
            .modifier(CompletionAttention(active: attention))
            .frame(width: roamsDesktop ? 112 : 144, height: 112).padding(8)
            .overlay(WindowDragRegion(region: .pet))
            .contentShape(Rectangle())
            .contextMenu {
                if attention { Button("知道了，停止提醒動態", action: acknowledge) }
                Button("回到一般視窗", action: restore)
                Button("死亡寵物紀錄") { openWindow(id: "memorial") }
            }
            .accessibilityLabel("\(pet?.displayName ?? "小傢伙")，寵物模式；按右鍵回到一般視窗")
            .help("按右鍵回到一般視窗")
    }
}

enum DeviceMenuMetrics {
    static let padding: CGFloat = 16
    static let sectionGap: CGFloat = 12
    static let rowGap: CGFloat = 10
    static let buttonRadius: CGFloat = 8
    static let sectionRadius: CGFloat = 10
}

struct DeviceMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var desktop: DesktopController
    @ObservedObject var care: CareModel
    var savedReceipt: CompletedRest?
    var canRename: Bool
    var canStop: Bool
    var rename: () -> Void
    var stop: () -> Void
    var dismiss: () -> Void
    private var color: Binding<Color> {
        Binding(get: { Color(red: desktop.shellColor.red, green: desktop.shellColor.green, blue: desktop.shellColor.blue) },
                set: { value in
                    guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
                    desktop.setShellColor(ShellColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
                })
    }
    var body: some View {
        ScrollView { menuContent }.frame(width: 256, height: 620)
    }
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: DeviceMenuMetrics.sectionGap) {
            Text("電子雞設定").font(Theme.font(15, bold: true))
            VStack(spacing: DeviceMenuMetrics.sectionGap) {
                HStack {
                    Text("視窗置頂")
                    Spacer()
                    Toggle("視窗置頂", isOn: Binding(get: { desktop.alwaysOnTop }, set: { desktop.setOnTop($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                HStack {
                    Text("機身顏色")
                    Spacer()
                    ColorPicker("機身顏色", selection: color, supportsOpacity: false).labelsHidden()
                        .accessibilityLabel("機身顏色，開啟系統色盤")
                }
                Button("恢復預設顏色") { desktop.setShellColor(.default) }
                    .font(Theme.font(10)).foregroundStyle(Theme.muted).buttonStyle(.plain)
            }.padding(DeviceMenuMetrics.sectionGap).background(Theme.canvas, in: RoundedRectangle(cornerRadius: DeviceMenuMetrics.sectionRadius))
            Text("到時提醒").font(Theme.font(12, bold: true))
            HStack(spacing: 8) {
                ForEach(CompletionReminderMode.allCases, id: \.self) { mode in
                    Button(mode.title) { care.setReminderMode(mode) }
                        .buttonStyle(.plain).font(Theme.font(11, bold: true))
                        .padding(8).frame(maxWidth: .infinity)
                        .foregroundStyle(care.reminderMode == mode ? Theme.surface : Theme.ink)
                        .background(care.reminderMode == mode ? Theme.ink : Theme.canvas, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityAddTraits(care.reminderMode == mode ? .isSelected : [])
                }
            }
            Text(care.reminderMode == .gentle ? "電子雞動態提醒，不打斷目前工作。" : "電子雞動態＋螢幕中央彈窗。")
                .font(Theme.font(10)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if care.completionNoticeID != nil {
                Button("知道了，停止提醒動態", action: care.acknowledgeCompletion)
            }
            if let error = care.reminderPreferenceError { Text(error).font(Theme.font(10)).foregroundStyle(.red) }
            DurationSettingsView(care: care, savedReceipt: savedReceipt)
            menuButton("只顯示寵物", symbol: "arrow.down.right.and.arrow.up.left") { dismiss(); desktop.toggleCompact() }
            menuButton("死亡寵物紀錄", symbol: "book.closed") { dismiss(); openWindow(id: "memorial") }
            menuButton("修改名字", symbol: "pencil", action: rename).disabled(!canRename)
            menuButton("藏到選單列", symbol: "eye.slash") { dismiss(); desktop.hide() }
            if canStop { menuButton("今天先收工", symbol: "stop.circle", action: stop) }
            Divider()
            menuButton("結束 App", symbol: "power") { NSApp.terminate(nil) }
            if let error = desktop.preferenceError { Text(error).font(Theme.font(10)).foregroundStyle(.red) }
        }.font(Theme.font(12)).foregroundStyle(Theme.ink).padding(DeviceMenuMetrics.padding).frame(width: 256)
    }
    private func menuButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DeviceMenuMetrics.rowGap) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 12).frame(height: 34).frame(maxWidth: .infinity)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: DeviceMenuMetrics.buttonRadius))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}


/// The same settings form is used by the device menu and the larger care views.
struct DurationSettingsView: View {
    @ObservedObject var care: CareModel
    var savedReceipt: CompletedRest? = nil
    @State private var work = ""
    @State private var rest = ""
    @State private var feedback: String?
    private var editable: Bool {
        care.canConfigureSchedule && care.cycle.canLeaveCompletedRest(afterSaving: savedReceipt)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(care.cycle.phase == .resting ? "下一輪時間" : "每輪時間").font(Theme.font(12, bold: true))
            Text("專注期間無法調整；休息時可設定下一次的專注時間。")
                .font(Theme.font(10)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            minuteField("工作", value: $work, options: [10, 20, 30, 60])
            minuteField("休息", value: $rest, options: [5, 10, 15])
            Button("套用時間") {
                feedback = care.configureSchedule(workMinutes: work, breakMinutes: rest, afterSaving: savedReceipt)
                    ?? "已儲存，下次開始工作時使用。"
            }.buttonStyle(.plain).font(Theme.font(11, bold: true))
                .padding(8).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 6))
                .disabled(!editable)
            Text(feedback ?? (editable
                ? (care.cycle.phase == .resting ? "僅套用下一輪，不影響這次休息倒數。可輸入 1–1440 分鐘。" : "可自行輸入 1–1440 分鐘；每輪都能重新設定。")
                : "專注中與暫停時不能調整，收工或進入休息後即可設定；休息完成需先保存成長。"))
                .font(Theme.font(10)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            work = String(Int(care.cycle.configuredWorkDuration / 60))
            rest = String(Int(care.cycle.configuredBreakDuration / 60))
        }
        .onChange(of: care.cycle.phase) { _ in feedback = nil }
    }
    private func minuteField(_ title: String, value: Binding<String>, options: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                TextField("分鐘", text: value).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(title)時間，分鐘").disabled(!editable)
                Text("分")
            }
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { minutes in
                    Button("\(minutes)分") { value.wrappedValue = String(minutes); feedback = nil }
                        .buttonStyle(.plain).font(Theme.font(10))
                        .padding(.horizontal, 6).padding(.vertical, 5)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 6))
                        .disabled(!editable)
                }
            }
        }
    }
}

/// Discrete, low-frequency movement; static outline remains with Reduce Motion.
struct CompletionAttention: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.petMotionVisible) private var visible
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 0.35, paused: !active || reduceMotion || !visible)) { timeline in
            let step = Int(timeline.date.timeIntervalSinceReferenceDate / 0.35) % 4
            content
                .offset(x: active && !reduceMotion && visible ? (step == 1 ? -5 : step == 3 ? 5 : 0) : 0)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Theme.ink : Color.clear, lineWidth: 3))
        }
    }
}
