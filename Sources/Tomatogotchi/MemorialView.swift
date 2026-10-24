import SwiftUI
import PetCore
import AdoptionFlow

struct MemorialWindowView: View {
    @ObservedObject var adoption: AdoptionModel
    @ObservedObject var memorial: MemorialModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        MemorialContent(snapshot: memorial.snapshot, loading: memorial.loading, error: memorial.error,
                        retry: { Task { await memorial.load() } }, close: { dismiss() })
            .task(id: adoption.pet) { await memorial.load() }
    }
}

struct MemorialContent: View {
    var snapshot: PetMemorialSnapshot?
    var loading = false
    var error: String?
    var retry: () -> Void = {}
    var close: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("死亡寵物紀錄").font(Theme.font(22, bold: true))
            Text(loading ? "正在讀取紀錄…" : snapshot?.countLabel ?? "紀錄尚未載入")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("memorial-count")
            if let error {
                Text(error).font(Theme.font(13)).fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot, !loading {
                if snapshot.unreadableCount > 0 {
                    Text("有 \(snapshot.unreadableCount) 筆資料無法讀取，未計入上方數量；原檔已保留。")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if snapshot.records.isEmpty {
                            VStack(spacing: 12) {
                                TombstoneStage(height: 88, framed: false)
                                Text(snapshot.unreadableCount == 0 ? "目前還沒有死亡寵物紀錄" : "目前沒有可讀取的死亡寵物紀錄")
                                    .font(Theme.font(14)).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.vertical, 24)
                        }
                        ForEach(snapshot.records) { record in
                            HStack(alignment: .center, spacing: 12) {
                                TombstoneStage(height: 88, framed: false).frame(width: 80)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(record.name).font(Theme.font(16, bold: true))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("見面時間：\(PetMemorial.timestamp(record.metAt))")
                                    Text("死亡時間：\(PetMemorial.timestamp(record.departedAt))")
                                }.font(Theme.font(12)).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(.trailing, 4)
                }
            } else {
                Spacer(minLength: 20)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                Spacer(minLength: 20)
            }
            HStack {
                Button("重新讀取", action: retry).buttonStyle(PetButtonStyle(secondary: true)).disabled(loading)
                Spacer()
                Button("關閉", action: close).buttonStyle(PetButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(minWidth: 420, minHeight: 360)
            .background(Theme.surface).foregroundStyle(Theme.ink).preferredColorScheme(.light)
    }
}
