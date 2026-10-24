import Foundation
import Combine
import PetCore
import CareCore

@MainActor
public final class AdoptionModel: ObservableObject {
    public enum Screen { case loading, welcome, naming, home, editing, loadFailed }
    @Published public private(set) var screen: Screen = .loading
    @Published public private(set) var pet: Pet?
    @Published public var draft = ""
    @Published public private(set) var saving = false
    @Published public private(set) var saveError: String?
    @Published public private(set) var loadError = ""
    @Published public private(set) var canRestore = false
    @Published public var resting = false
    @Published public private(set) var progressError: String?
    @Published public var farewellConfirming = false
    private var replacementCandidate: Pet?
    private let repository: PetRepository
    private let candidateID = UUID()
    private var pendingName = ""
    private var pendingEdit = false
    private var task: Task<Void, Never>?

    public init(repository: PetRepository) { self.repository = repository }
    public var nameError: String? {
        do { _ = try Pet.normalizedName(draft); return nil }
        catch { return error.localizedDescription }
    }
    public func load() {
        guard !saving else { return }
        screen = .loading
        task = Task {
            do {
                pet = try await repository.load()
                screen = pet == nil ? .welcome : .home
            } catch {
                loadError = error.localizedDescription
                if case PetError.unsupportedVersion = error { canRestore = false }
                else { canRestore = await repository.hasValidBackup() }
                screen = .loadFailed
            }
        }
    }
    public func receive() { draft = ""; saveError = nil; screen = .naming }
    public func edit() {
        guard screen == .home, pet != nil, !saving else { return }
        draft = pet?.name ?? ""; saveError = nil; screen = .editing
    }
    public func cancelEdit() { guard !saving else { return }; draft = pet?.name ?? ""; saveError = nil; screen = .home }
    public func backToInput() { guard !saving else { return }; saveError = nil }
    public func save(skip: Bool = false) {
        guard !saving else { return }
        pendingName = skip ? "" : draft
        pendingEdit = screen == .editing
        performSave()
    }
    public func retrySave() { guard !saving else { return }; performSave() }
    private func performSave() {
        guard !saving else { return }
        do { _ = try Pet.normalizedName(pendingName) }
        catch { saveError = error.localizedDescription; return }
        saving = true
        saveError = nil
        let name = pendingName, editing = pendingEdit, id = pet?.id
        task = Task {
            do {
                let stored: Pet
                if editing, let id { stored = try await repository.rename(id: id, to: name) }
                else { stored = try await repository.adopt(Pet(id: candidateID, name: name)) }
                pet = stored
                draft = stored.name ?? ""
                screen = .home
            } catch PetError.alreadyAdopted(let existing) {
                pet = existing; screen = .home
            } catch {
                saveError = "暫時無法儲存，請再試一次。"
            }
            saving = false
        }
    }
    public func hasSavedRest(_ receipt: CompletedRest?) -> Bool {
        guard let receipt, let pet, receipt.petID == pet.id else { return false }
        return pet.growth.completedRests.contains(receipt.id)
    }
    public func recordRest(_ receipt: CompletedRest) {
        guard !saving, screen == .home, let pet, pet.id == receipt.petID,
              pet.growth.stage != .departed, !pet.growth.completedRests.contains(receipt.id) else { return }
        saving = true; progressError = nil
        task = Task {
            do {
                self.pet = try await repository.completeRest(id: receipt.petID, receipt: receipt.id,
                    food: receipt.activity == .food, now: receipt.completedAt)
            } catch { progressError = "這次成長還沒存好，休息紀錄會保留，請重試。" }
            saving = false
        }
    }
    public func hasSavedNeed(_ progress: CareNeedProgress) -> Bool {
        guard let pet, pet.id == progress.petID else { return false }
        return pet.growth.hasProcessedNeed(id: progress.id, steps: progress.steps)
    }
    public func recordNeed(_ progress: CareNeedProgress, responding: Bool = false,
                           completion: ((Bool) -> Void)? = nil) {
        guard !saving, screen == .home, pet?.id == progress.petID,
              pet?.growth.stage != .departed else { return }
        if !responding && hasSavedNeed(progress) { return }
        saving = true; progressError = nil
        task = Task {
            do {
                self.pet = try await repository.applyNeed(petID: progress.petID, needID: progress.id,
                    food: progress.activity == .food, steps: progress.steps, responding: responding, now: Date())
                saving = false
                completion?(self.pet?.growth.stage != .departed)
            } catch {
                progressError = "照顧狀態還沒存好，已暫停。請保留原檔並重試。"
                saving = false
                completion?(false)
            }
        }
    }

    public func farewell() {
        guard !saving, farewellConfirming, let pet, pet.growth.stage == .departed else { return }
        do { if replacementCandidate == nil { replacementCandidate = try Pet() } }
        catch { progressError = "新蛋暫時無法建立，原本的牠會保留。"; return }
        guard let candidate = replacementCandidate else { return }
        saving = true; progressError = nil
        task = Task {
            do {
                self.pet = try await repository.farewell(id: pet.id, replacement: candidate)
                draft = ""; farewellConfirming = false; replacementCandidate = nil; screen = .home
            } catch { progressError = "還沒完成告別，原本的牠會保留，可以再試一次。" }
            saving = false
        }
    }

    public func restore() {
        guard !saving, canRestore else { return }
        saving = true
        task = Task {
            do { pet = try await repository.restoreBackup(); screen = .home }
            catch { loadError = error.localizedDescription; screen = .loadFailed }
            saving = false
        }
    }
}
