import CareFlow
import SwiftUI
import AdoptionFlow
import CareCore
import PetCore

struct GrowthView: View {
    @ObservedObject var model: AdoptionModel
    @ObservedObject var care: CareModel
    private var count: Int { model.pet?.growth.completedRests.count ?? 0 }
    private var committed: Bool { model.hasSavedRest(care.cycle.completedReceipt) }
    private var title: String {
        if count == 3 { return "蛋裡住著一隻\(model.pet?.growth.species.label ?? "小傢伙")。" }
        return count == 12 ? "牠長大了一點。" : "牠休息好了。"
    }
    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(Theme.font(24, bold: true)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(count == 3 ? "謝謝你這幾次有停下來休息。" : "你休息的時候，牠也慢慢長大。")
                .font(Theme.font(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            PetStage(pet: model.pet)
            Text(model.pet?.growth.label ?? "未知蛋").font(Theme.font(12)).foregroundStyle(Theme.muted)
            if model.saving { ProgressView("正在記住這次成長…").font(Theme.font(12)) }
            if let error = model.progressError {
                Text(error).font(Theme.font(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                Button("重新保存這次成長") {
                    if let receipt = care.cycle.completedReceipt { model.recordRest(receipt) }
                }.buttonStyle(PetButtonStyle()).disabled(model.saving)
            }
            Button("我回來了，繼續陪伴") { care.start(for: model.pet?.id, afterSaving: care.cycle.completedReceipt) }
                .buttonStyle(PetButtonStyle()).disabled(model.saving || !committed)
            Button("今天先收工") { care.stop(afterSaving: care.cycle.completedReceipt) }.buttonStyle(PetButtonStyle(secondary: true))
                .disabled(model.saving || !committed)
        }
        .padding(.horizontal, 32).padding(.vertical, 24).frame(width: 400)
        .fixedSize(horizontal: false, vertical: true).background(Theme.surface).foregroundStyle(Theme.ink)
    }
}

struct FarewellView: View {
    @ObservedObject var model: AdoptionModel
    @ObservedObject var care: CareModel
    @ObservedObject var desktop: DesktopController
    var body: some View {
        VStack(spacing: 16) {
            Text(model.farewellConfirming ? "準備好開始新的陪伴嗎？" : "好好跟牠說再見。")
                .font(Theme.font(24, bold: true)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(model.farewellConfirming ? "會先保留牠的紀錄，再交給你新的未知蛋。" : "這段陪伴會保留在這台 Mac。")
                .font(Theme.font(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if model.farewellConfirming { EggStage() } else { PetStage(pet: model.pet) }
            Text(model.farewellConfirming ? "確認後不復活原寵物；寫入失敗可重試。" : "新蛋會是新的旅程。")
                .font(Theme.font(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if let error = model.progressError { Text(error).font(Theme.font(12)).foregroundStyle(Theme.muted) }
            Button(model.saving ? "正在保留這段陪伴…" : model.farewellConfirming ? "確認告別並領蛋" : "準備告別，領一顆新蛋") {
                if model.farewellConfirming { care.stop(); model.farewell() }
                else { model.farewellConfirming = true }
            }.buttonStyle(PetButtonStyle()).disabled(model.saving)
            Button(model.farewellConfirming ? "先不要" : "先留在這裡") {
                if model.farewellConfirming { model.farewellConfirming = false }
                else { desktop.hide() }
            }.buttonStyle(PetButtonStyle(secondary: true)).disabled(model.saving)
        }
        .padding(.horizontal, 32).padding(.vertical, 24).frame(width: 400)
        .fixedSize(horizontal: false, vertical: true).background(Theme.surface).foregroundStyle(Theme.ink)
    }
}
