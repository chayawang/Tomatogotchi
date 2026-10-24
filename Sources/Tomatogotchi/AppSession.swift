import Foundation
import DesktopCore

@MainActor
final class AppSession {
    static let shared = AppSession()
    let directory: URL
    let lease: SessionLease?
    let startupError: String?
    var ownsSession: Bool { lease != nil }

    private init() {
        if let path = ProcessInfo.processInfo.environment["TOMATOGOTCHI_DATA_DIR"], !path.isEmpty {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("work.shiroi.tomatogotchi", isDirectory: true)
        }
        do { lease = try SessionLease.acquire(directory: directory); startupError = nil }
        catch {
            lease = nil
            startupError = "暫時無法開啟資料夾，請確認可讀寫後再試。寵物存檔不會被重設。"
        }
    }
}
