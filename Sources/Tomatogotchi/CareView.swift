import CareFlow
import SwiftUI
import CareCore
import AdoptionFlow

struct CareView: View {
    @ObservedObject var model: AdoptionModel
    @ObservedObject var care: CareModel
    @ObservedObject var desktop: DesktopController

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(Theme.font(24, bold: true)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            PetStage(pet: model.pet, hatchingRequestID: care.hatchingPresentationID, onHatchingReady: care.confirmHatchingPresentation)
            if care.showsWorkCountdown && !care.needsReset {
                Text(care.workTime).font(Theme.font(36, bold: true)).monospacedDigit()
                    .accessibilityLabel("工作剩餘 \(care.workTime)")
            }
            if care.needsReset {
                caption(care.storageError ?? "寵物與原本的計時檔都會保留。")
                primary("重設這次計時") { care.reset() }
            } else {
                actions
                if let error = care.storageError { caption(error) }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 24).frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface).foregroundStyle(Theme.ink)
    }
    private var title: String {
        if care.needsReset { return "這次計時需要重新開始。" }
        switch care.cycle.phase {
        case .working: return "牠在旁邊陪你。"
        case .needsCare: return care.cycle.demand?.needTitle ?? "牠需要你。"
        case .resting: return care.cycle.activity == .walk ? "牠想散步，你也走走吧。" : "牠在吃飯，你去休息吧。"
        case .restComplete: return "慢慢來，回來再繼續。"
        case .paused: return "先停一下，也很好。"
        case .idle: return "先一起待著吧。"
        }
    }
    private var subtitle: String {
        if care.needsReset { return "寵物沒有不見，只重設這次計時。" }
        switch care.cycle.phase {
        case .working: return "照顧牠的時候，再提醒你。"
        case .needsCare: return "你也離開電腦一下吧。"
        case .resting: return "去裝水、上廁所，或走一走。"
        case .restComplete: return "牠休息好了，也等你休息好。"
        case .paused: return "睡眠、切換使用者與暫停都不累積工作時間。"
        case .idle: return care.scheduleDescription
        }
    }
    @ViewBuilder private var actions: some View {
        switch care.cycle.phase {
        case .working:
            caption(care.notificationHint)
            primary("先休息一下") { care.rest(.food) }
            secondary("暫停陪伴") { care.pause() }
        case .needsCare:
            caption("照顧一下，接著離席 \(Int(care.cycle.breakDuration / 60)) 分鐘。")
            primary(care.cycle.demand?.title ?? "照顧牠") { CareActions.respond(model: model, care: care) }
            secondary("暫停陪伴") { care.pause() }
        case .resting:
            Text(care.restTime).font(Theme.font(36, bold: true)).monospacedDigit().foregroundStyle(Theme.muted)
                .accessibilityLabel("休息剩餘 \(care.restTime)")
            DurationSettingsView(care: care)
            primary("結束這次休息") { care.stop() }
            secondary("藏到選單列") { desktop.hide() }
            caption("不用留在螢幕前；晚回來也沒關係。")
        case .restComplete:
            caption("休息完成")
            primary("我回來了，繼續陪伴") { care.start(for: model.pet?.id) }
            secondary("今天先收工") { care.stop() }
            caption("不自動開始下一輪，不催你回到電腦。")
        case .paused:
            caption("準備好時再繼續，不用補回暫停的時間。")
            primary("繼續陪伴") { care.resume() }
            secondary("今天先收工") { care.stop() }
        case .idle:
            DurationSettingsView(care: care)
            primary(care.startTitle) { care.start(for: model.pet?.id) }
        }
    }
    private func primary(_ text: String, action: @escaping () -> Void) -> some View {
        Button(text, action: action).buttonStyle(PetButtonStyle())
    }
    private func secondary(_ text: String, action: @escaping () -> Void) -> some View {
        Button(text, action: action).buttonStyle(PetButtonStyle(secondary: true))
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(Theme.font(12)).foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
    }
}
