import Foundation
import Combine
import PetCore

@MainActor
public final class MemorialModel: ObservableObject {
    @Published public private(set) var snapshot: PetMemorialSnapshot?
    @Published public private(set) var loading = false
    @Published public private(set) var error: String?
    private let repository: PetRepository
    private var generation = 0
    public init(repository: PetRepository) { self.repository = repository }
    public func load() async {
        generation += 1
        let request = generation
        loading = true; error = nil
        do {
            let result = try await repository.memorials()
            guard request == generation else { return }
            snapshot = result
        } catch {
            guard request == generation else { return }
            snapshot = nil
            self.error = "死亡寵物紀錄暫時無法讀取。原本的紀錄仍保留，請再試一次。"
        }
        loading = false
    }
}
