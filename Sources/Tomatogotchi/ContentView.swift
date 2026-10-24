import CareFlow
import AdoptionFlow
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AdoptionModel
    @ObservedObject var desktop: DesktopController
    @ObservedObject var care: CareModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            if model.screen == .loading {
                ProgressView().controlSize(.small).padding(.top, 32)
                Text("正在看看牠在哪裡…").font(Theme.font(14)).padding(.bottom, 32)
            } else if model.screen == .loadFailed {
                heading("暫時找不到牠。", "先保留原本的家，我們再試一次。")
                EggStage()
                caption(model.loadError)
                Button("重新讀取", action: model.load).buttonStyle(PetButtonStyle()).disabled(model.saving)
                if model.canRestore {
                    Button("從備份恢復", action: model.restore).buttonStyle(PetButtonStyle(secondary: true)).disabled(model.saving)
                    caption("恢復時會保留問題原檔，備份可能是改名前的版本。")
                }
            } else if model.screen == .welcome {
                heading("有一顆蛋，想跟你回家。", "裡面住著誰，還是個秘密。")
                EggStage()
                caption("不必登入。這顆蛋會保存在這台 Mac。")
                Button("收下這顆蛋", action: model.receive).buttonStyle(PetButtonStyle()).keyboardShortcut(.defaultAction)
            } else if model.screen == .home {
                heading(model.pet?.growth.stage == .egg ? "牠現在有家了。" : "牠在這裡陪你。", "\(model.pet?.displayName ?? "小傢伙")，先一起待著吧。")
                PetStage(pet: model.pet)
                caption(model.pet?.growth.label ?? "未知蛋")
                caption("已保存在這台 Mac · \(model.pet?.name == nil ? "未命名" : "已命名")")
                DurationSettingsView(care: care)
                Button(care.startTitle) { care.start(for: model.pet?.id) }.buttonStyle(PetButtonStyle())
                caption(care.scheduleDescription + "開始後可選擇開啟系統通知。")
                Button(model.pet?.name == nil ? "幫牠取名字" : "修改名字", action: model.edit).buttonStyle(PetButtonStyle())
                Button("收合成小窗") { desktop.toggleCompact() }.buttonStyle(PetButtonStyle(secondary: true))
                caption("關閉視窗後，可從選單列叫回。")
                Button("藏到選單列") { desktop.hide() }.buttonStyle(PetButtonStyle(secondary: true))
                if let error = desktop.preferenceError { caption(error) }
            } else {
                naming
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
        .frame(width: 400).fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface).foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
        .task { if model.screen == .loading { model.load() } }
    }

    @ViewBuilder private var naming: some View {
        let editing = model.screen == .editing
        heading(model.saving ? "正在幫牠安頓下來…" : model.saveError != nil ? "還沒存好，再試一次。" : editing ? "幫小傢伙取個名字。" : "要幫牠取個名字嗎？",
                model.saving ? "快好了，等一下就能見到牠。" : model.saveError != nil ? "剛剛的名字還在，別擔心。" : editing ? "現在取名，或改成更喜歡的。" : "不急，熟一點再取也可以。")
        PetStage(pet: model.pet)
        VStack(alignment: .leading, spacing: 12) {
            Text("名字（選填）").font(Theme.font(12))
            TextField("想好名字再填也可以", text: $model.draft)
                .textFieldStyle(.plain).font(Theme.font(16)).padding(.horizontal, 12).frame(height: 40)
                .background(model.saving ? Theme.canvas : Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.nameError == nil ? Theme.line : Color(red: 1, green: 0.7, blue: 0.6)))
                .focused($nameFocused).disabled(model.saving)
                .accessibilityLabel("名字，選填")
                .onSubmit { if model.nameError == nil && model.saveError == nil { model.save() } }
            Text(model.saving ? "正在保存，請稍候。" : model.saveError ?? model.nameError ?? (editing ? "取消會保留原本的名字；留白可改回未命名。" : "之後可以補上或修改名字。"))
                .font(Theme.font(12)).foregroundStyle(model.nameError == nil ? Theme.muted : Color(red: 0.8, green: 0.2, blue: 0.1))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(model.saveError ?? model.nameError ?? "之後可以補上或修改名字")
        }
        if model.saveError != nil {
            Button("再試一次", action: model.retrySave).buttonStyle(PetButtonStyle()).disabled(model.saving)
            Button("返回修改", action: model.backToInput).buttonStyle(PetButtonStyle(secondary: true)).disabled(model.saving)
        } else {
            Button(model.saving ? "保存中…" : editing ? "儲存名字" : "儲存名字並領養") { model.save() }
                .buttonStyle(PetButtonStyle()).disabled(model.saving || model.nameError != nil)
            Button(editing ? "取消" : "之後再取") {
                if editing { model.cancelEdit() } else { model.save(skip: true) }
            }.buttonStyle(PetButtonStyle(secondary: true)).disabled(model.saving)
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 16) {
            Text(title).font(Theme.font(24, bold: true)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(Theme.font(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
    }
}
