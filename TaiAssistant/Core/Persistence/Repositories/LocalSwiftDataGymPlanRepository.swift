import Foundation
import SwiftData

final class LocalSwiftDataGymPlanRepository: GymPlanRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchLibrary(ownerID: String) async throws -> GymPlanLibrarySnapshot {
        let userPlans = try await fetchUserPlanSummaries(ownerID: ownerID)
        let active = userPlans.first { $0.lifecycleStatus == .active }
        let previous = userPlans.filter { $0.lifecycleStatus != .active }
        return GymPlanLibrarySnapshot(
            activePlan: active,
            previousPlans: previous,
            hasUserPlans: !userPlans.isEmpty
        )
    }

    func fetchTemplateSummaries() -> [GymPlanSummary] {
        GymProgramTemplateID.allCases.map { GymProgramTemplateLibrary.starterSummary(for: $0) }
    }

    func fetchSummaries(ownerID: String) async throws -> [GymPlanSummary] {
        try await fetchUserPlanSummaries(ownerID: ownerID)
    }

    func resolvePlan(reference: GymPlanReference, sectionIndex: Int, ownerID: String) async throws -> GymResolvablePlan {
        let draft = try await loadDraft(reference: reference, ownerID: ownerID)
        guard draft.sections.indices.contains(sectionIndex) else {
            throw GymPlanRepositoryError.sectionNotFound
        }
        let section = draft.sections.sorted { $0.orderIndex < $1.orderIndex }[sectionIndex]
        let prescription = section.prescription ?? draft.prescription
        return GymResolvablePlan(
            reference: reference,
            title: draft.sections.count > 1 ? "\(draft.title) — \(section.name)" : draft.title,
            sectionName: section.name,
            sectionIndex: sectionIndex,
            exercises: section.exercises.sorted { $0.orderIndex < $1.orderIndex },
            prescription: prescription,
            generalInstructions: draft.generalInstructions
        )
    }

    func loadDraft(reference: GymPlanReference, ownerID: String) async throws -> GymPlanDraft {
        switch reference {
        case .starter(let templateID):
            if let override = try fetchStarterOverride(templateID: templateID, ownerID: ownerID) {
                return try draft(from: override, reference: reference)
            }
            let template = GymProgramTemplateLibrary.template(for: templateID)
            return GymPlanDraft(
                reference: reference,
                title: template.title,
                sections: [
                    GymPlanSectionDraft(
                        name: template.title,
                        orderIndex: 0,
                        exercises: template.exercises,
                        prescription: template.prescription
                    )
                ],
                prescription: template.prescription,
                generalInstructions: [],
                suggestedDurationWeeks: nil,
                lifecycleStatus: .inactive,
                importedAt: nil
            )
        case .custom(let planID):
            guard let plan = try fetchCustomPlan(id: planID, ownerID: ownerID) else {
                throw GymPlanRepositoryError.planNotFound
            }
            return try draft(from: plan, reference: reference)
        }
    }

    func saveDraft(
        _ draft: GymPlanDraft,
        ownerID: String,
        activation: GymPlanSaveActivation
    ) async throws -> GymPlanReference {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.exercises.isEmpty
        else {
            throw GymPlanRepositoryError.invalidDraft
        }

        let content = GymPlanPersistedContent(
            sections: draft.sections,
            prescription: draft.prescription,
            generalInstructions: draft.generalInstructions,
            suggestedDurationWeeks: draft.suggestedDurationWeeks
        )
        let exercisesJSON = try GymPlanPersistenceCodec.encodeExercises(draft.exercises)
        let prescriptionJSON = try GymPlanPersistenceCodec.encodePrescription(draft.prescription)
        let contentJSON = try GymPlanPersistenceCodec.encodeContent(content)
        let generalInstructionsJSON = try GymPlanPersistenceCodec.encodeStringArray(draft.generalInstructions)

        let lifecycle: GymPlanLifecycleStatus = switch activation {
        case .makeActive: .active
        case .saveOnly: draft.lifecycleStatus == .active ? .active : .inactive
        }

        let context = ModelContext(container)

        if activation == .makeActive {
            try deactivateActivePlans(ownerID: ownerID, context: context, excluding: draft.reference)
        }

        if let reference = draft.reference {
            switch reference {
            case .starter(let templateID):
                if let existing = try fetchStarterOverride(templateID: templateID, ownerID: ownerID) {
                    existing.title = draft.title
                    existing.exercisesJSON = exercisesJSON
                    existing.prescriptionJSON = prescriptionJSON
                    existing.contentJSON = contentJSON
                    existing.generalInstructionsJSON = generalInstructionsJSON
                    existing.suggestedDurationWeeks = draft.suggestedDurationWeeks
                    existing.lifecycleStatus = lifecycle
                    existing.importedAt = draft.importedAt ?? existing.importedAt
                    existing.updatedAt = .now
                } else {
                    context.insert(
                        GymWorkoutPlan(
                            ownerID: ownerID,
                            title: draft.title,
                            starterTemplateID: templateID.rawValue,
                            exercisesJSON: exercisesJSON,
                            prescriptionJSON: prescriptionJSON,
                            lifecycleStatusRaw: lifecycle.rawValue,
                            importedAt: draft.importedAt,
                            suggestedDurationWeeks: draft.suggestedDurationWeeks,
                            contentJSON: contentJSON,
                            generalInstructionsJSON: generalInstructionsJSON
                        )
                    )
                }
                try context.save()
                return reference
            case .custom(let planID):
                guard let existing = try fetchCustomPlan(id: planID, ownerID: ownerID) else {
                    throw GymPlanRepositoryError.planNotFound
                }
                existing.title = draft.title
                existing.exercisesJSON = exercisesJSON
                existing.prescriptionJSON = prescriptionJSON
                existing.contentJSON = contentJSON
                existing.generalInstructionsJSON = generalInstructionsJSON
                existing.suggestedDurationWeeks = draft.suggestedDurationWeeks
                existing.lifecycleStatus = lifecycle
                existing.importedAt = draft.importedAt ?? existing.importedAt
                existing.updatedAt = .now
                try context.save()
                return reference
            }
        }

        let plan = GymWorkoutPlan(
            ownerID: ownerID,
            title: draft.title,
            starterTemplateID: nil,
            exercisesJSON: exercisesJSON,
            prescriptionJSON: prescriptionJSON,
            lifecycleStatusRaw: lifecycle.rawValue,
            importedAt: draft.importedAt ?? .now,
            suggestedDurationWeeks: draft.suggestedDurationWeeks,
            contentJSON: contentJSON,
            generalInstructionsJSON: generalInstructionsJSON
        )
        context.insert(plan)
        try context.save()
        return .custom(plan.id)
    }

    func duplicatePlan(reference: GymPlanReference, ownerID: String) async throws -> GymPlanReference {
        let source = try await loadDraft(reference: reference, ownerID: ownerID)
        var copy = source
        copy.reference = nil
        copy.title = "Copy of \(source.title)"
        copy.lifecycleStatus = .inactive
        return try await saveDraft(copy, ownerID: ownerID, activation: .saveOnly)
    }

    func deletePlan(reference: GymPlanReference, ownerID: String) async throws {
        switch reference {
        case .starter:
            throw GymPlanRepositoryError.cannotDeleteStarter
        case .custom(let planID):
            let context = ModelContext(container)
            guard let existing = try fetchCustomPlan(id: planID, ownerID: ownerID) else {
                throw GymPlanRepositoryError.planNotFound
            }
            context.delete(existing)
            try context.save()
        }
    }

    func archivePlan(reference: GymPlanReference, ownerID: String) async throws {
        switch reference {
        case .starter:
            return
        case .custom(let planID):
            let context = ModelContext(container)
            guard let existing = try fetchCustomPlan(id: planID, ownerID: ownerID) else {
                throw GymPlanRepositoryError.planNotFound
            }
            existing.lifecycleStatus = .archived
            existing.updatedAt = .now
            try context.save()
        }
    }

    func resetStarterPlan(templateID: GymProgramTemplateID, ownerID: String) async throws {
        let context = ModelContext(container)
        if let existing = try fetchStarterOverride(templateID: templateID, ownerID: ownerID) {
            context.delete(existing)
            try context.save()
        }
    }

    // MARK: - Helpers

    private func fetchUserPlanSummaries(ownerID: String) async throws -> [GymPlanSummary] {
        let persisted = try fetchPersistedPlans(ownerID: ownerID)
        let customPlans = persisted.filter { $0.starterTemplateID == nil }
        let sorted = customPlans.sorted { ($0.importedAt ?? $0.createdAt) > ($1.importedAt ?? $1.createdAt) }
        return try sorted.map { plan in
            try summary(from: plan, reference: .custom(plan.id))
        }
    }

    private func deactivateActivePlans(
        ownerID: String,
        context: ModelContext,
        excluding reference: GymPlanReference?
    ) throws {
        let activeRaw = GymPlanLifecycleStatus.active.rawValue
        let predicate = #Predicate<GymWorkoutPlan> {
            $0.ownerID == ownerID && $0.lifecycleStatusRaw == activeRaw && $0.starterTemplateID == nil
        }
        let activePlans = try context.fetch(FetchDescriptor(predicate: predicate))
        for plan in activePlans {
            if case .custom(let id)? = reference, plan.id == id {
                continue
            }
            plan.lifecycleStatus = .archived
            plan.updatedAt = .now
        }
    }

    private func fetchPersistedPlans(ownerID: String) throws -> [GymWorkoutPlan] {
        let context = ModelContext(container)
        let predicate = #Predicate<GymWorkoutPlan> { $0.ownerID == ownerID }
        let descriptor = FetchDescriptor<GymWorkoutPlan>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.title)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchStarterOverride(templateID: GymProgramTemplateID, ownerID: String) throws -> GymWorkoutPlan? {
        let context = ModelContext(container)
        let raw = templateID.rawValue
        let predicate = #Predicate<GymWorkoutPlan> {
            $0.ownerID == ownerID && $0.starterTemplateID == raw
        }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    private func fetchCustomPlan(id: UUID, ownerID: String) throws -> GymWorkoutPlan? {
        let context = ModelContext(container)
        let predicate = #Predicate<GymWorkoutPlan> {
            $0.ownerID == ownerID && $0.id == id && $0.starterTemplateID == nil
        }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    private func draft(from plan: GymWorkoutPlan, reference: GymPlanReference) throws -> GymPlanDraft {
        let content = try GymPlanPersistenceCodec.content(from: plan)
        return GymPlanDraft(
            reference: reference,
            title: plan.title,
            sections: content.sections,
            prescription: content.prescription,
            generalInstructions: content.generalInstructions,
            suggestedDurationWeeks: content.suggestedDurationWeeks ?? plan.suggestedDurationWeeks,
            lifecycleStatus: plan.lifecycleStatus,
            importedAt: plan.importedAt
        )
    }

    private func summary(from plan: GymWorkoutPlan, reference: GymPlanReference) throws -> GymPlanSummary {
        let content = try GymPlanPersistenceCodec.content(from: plan)
        let exerciseCount = content.sections.reduce(0) { $0 + $1.exercises.count }
        return GymPlanSummary(
            reference: reference,
            title: plan.title,
            exerciseCount: exerciseCount,
            sectionCount: content.sections.count,
            workingSetsPerExercise: content.prescription.workingSetsPerExercise,
            repRangeLabel: content.prescription.repRangeLabel,
            isStarter: reference.isStarter,
            isCustom: !reference.isStarter,
            isEditedStarter: plan.starterTemplateID != nil,
            lifecycleStatus: plan.lifecycleStatus,
            importedAt: plan.importedAt,
            suggestedDurationWeeks: plan.suggestedDurationWeeks,
            sectionNames: content.sections.sorted { $0.orderIndex < $1.orderIndex }.map(\.name)
        )
    }
}
