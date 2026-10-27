import Foundation
import AdoptionFlow
import PetCore
import CareCore

@MainActor
public enum CareActions {
    public static func connect(model: AdoptionModel, care: CareModel) {
        care.onNeedUpdate = { [weak model, weak care] progress in
            guard let model, let care, !model.saving, care.hatchingPresentationID == nil, model.progressError == nil else { return }
            model.recordNeed(progress) { [weak care] alive in
                if !alive { care?.pauseForSafety() }
            }
        }
    }
    public static func respond(model: AdoptionModel, care: CareModel) {
        guard !model.saving, care.hatchingPresentationID == nil, model.pet?.growth.stage != .departed else { return }
        care.refresh(deliverNeed: false)
        guard !model.saving, let progress = care.cycle.needProgress else { return }
        // Freeze time at the click while persisting; disk latency is not neglect.
        care.pauseForSafety()
        guard care.storageError == nil else { return }
        let commit: () -> Void = { [weak model, weak care] in
            guard let model, let care, !model.saving,
                  care.cycle.needProgress?.id == progress.id else { return }
            model.recordNeed(progress, responding: true) { [weak care] alive in
                guard alive, let care, care.cycle.demandID == progress.id else { return }
                care.rest(progress.activity)
            }
        }
        if model.pet?.growth.stage == .egg { care.prepareHatchingPresentation(commit) }
        else { commit() }
    }
}
