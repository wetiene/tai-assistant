import Foundation

protocol GymPlanRepository {
    func fetchLibrary(ownerID: String) async throws -> GymPlanLibrarySnapshot

    func fetchTemplateSummaries() -> [GymPlanSummary]

    func fetchSummaries(ownerID: String) async throws -> [GymPlanSummary]

    func resolvePlan(
        reference: GymPlanReference,
        sectionIndex: Int,
        ownerID: String
    ) async throws -> GymResolvablePlan

    func loadDraft(reference: GymPlanReference, ownerID: String) async throws -> GymPlanDraft

    func saveDraft(
        _ draft: GymPlanDraft,
        ownerID: String,
        activation: GymPlanSaveActivation
    ) async throws -> GymPlanReference

    func duplicatePlan(reference: GymPlanReference, ownerID: String) async throws -> GymPlanReference

    func deletePlan(reference: GymPlanReference, ownerID: String) async throws

    func archivePlan(reference: GymPlanReference, ownerID: String) async throws

    func resetStarterPlan(templateID: GymProgramTemplateID, ownerID: String) async throws
}

extension GymPlanRepository {
    func resolvePlan(reference: GymPlanReference, ownerID: String) async throws -> GymResolvablePlan {
        try await resolvePlan(reference: reference, sectionIndex: 0, ownerID: ownerID)
    }

    func saveDraft(_ draft: GymPlanDraft, ownerID: String) async throws -> GymPlanReference {
        try await saveDraft(draft, ownerID: ownerID, activation: .saveOnly)
    }
}
