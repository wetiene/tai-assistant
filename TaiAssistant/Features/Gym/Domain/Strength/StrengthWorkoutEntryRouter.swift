import Foundation
import OSLog

/// Canonical shell-level entry router for structured strength workouts.
/// Owns start/resume requests, conflict presentation state, and conflict resolution lifecycle.
@MainActor
@Observable
final class StrengthWorkoutEntryRouter {
  private static let logger = Logger(subsystem: "com.taiassistant", category: "StrengthWorkoutEntry")

  private(set) var pendingConflict: GymWorkoutStartConflict?
  var isConflictDialogPresented = false
  var isAbandonConfirmationPresented = false
  private(set) var isResolvingConflict = false
  var alertMessage: String?

  private var isStartInFlight = false
  private let coordinator: StrengthWorkoutCoordinator
  private let gymPlanRepository: GymPlanRepository
  private let ownerID: String
  private var onPresentWorkout: (StrengthWorkoutPresentation) -> Void
  private var onWorkoutSaved: (() -> Void)?

  init(
    coordinator: StrengthWorkoutCoordinator,
    gymPlanRepository: GymPlanRepository,
    ownerID: String,
    onPresentWorkout: @escaping (StrengthWorkoutPresentation) -> Void,
    onWorkoutSaved: (() -> Void)? = nil
  ) {
    self.coordinator = coordinator
    self.gymPlanRepository = gymPlanRepository
    self.ownerID = ownerID
    self.onPresentWorkout = onPresentWorkout
    self.onWorkoutSaved = onWorkoutSaved
  }

  func updateOnWorkoutSaved(_ handler: (() -> Void)?) {
    onWorkoutSaved = handler
  }

  // MARK: - Entry

  func requestStart(target: GymPlanWorkoutTarget, source: StrengthWorkoutEntrySource) async {
    guard !isStartInFlight else { return }
    isStartInFlight = true
    defer { isStartInFlight = false }

    do {
      if let active = try await coordinator.fetchActiveWorkout(),
         active.planReference == target.reference,
         let resume = try await coordinator.buildResumePresentation(source: source)
      {
        onPresentWorkout(resume)
        return
      }

      let plan = try await gymPlanRepository.resolvePlan(
        reference: target.reference,
        sectionIndex: target.sectionIndex,
        ownerID: ownerID
      )

      if let conflict = try await coordinator.detectStartConflict(
        requestedTarget: target,
        requestedTitle: plan.title,
        entrySource: source
      ) {
        presentConflict(conflict)
        return
      }

      let presentation = try await coordinator.buildStartPresentation(
        request: StrengthWorkoutStartRequest(target: target, source: source, skipPreFlight: false)
      )
      onPresentWorkout(presentation)
    } catch {
      Self.logger.error("Strength workout start failed: \(error.localizedDescription, privacy: .public)")
      alertMessage = "Could not start this workout. Please try again."
    }
  }

  func requestResume(source: StrengthWorkoutEntrySource) async {
    do {
      guard let presentation = try await coordinator.buildResumePresentation(source: source) else {
        alertMessage = "No workout in progress to resume."
        return
      }
      onPresentWorkout(presentation)
    } catch {
      Self.logger.error("Strength workout resume failed: \(error.localizedDescription, privacy: .public)")
      alertMessage = "Could not resume your workout. Please try again."
    }
  }

  // MARK: - Conflict UI

  func cancelConflict() {
    pendingConflict = nil
    isConflictDialogPresented = false
    isAbandonConfirmationPresented = false
  }

  func requestAbandonConfirmation() {
    isConflictDialogPresented = false
    isAbandonConfirmationPresented = true
  }

  func cancelAbandonConfirmation() {
    isAbandonConfirmationPresented = false
    if pendingConflict != nil {
      isConflictDialogPresented = true
    }
  }

  func resolveConflict(_ resolution: GymWorkoutStartConflictResolution) async {
    guard !isResolvingConflict else { return }
    guard let conflict = pendingConflict else { return }

    isResolvingConflict = true
    isConflictDialogPresented = false
    isAbandonConfirmationPresented = false
    defer { isResolvingConflict = false }

    let target = conflict.requestedWorkoutTarget
    let source = conflict.entrySource

    switch resolution {
    case .resumeCurrent:
      pendingConflict = nil
      await requestResume(source: source)

    case .finishCurrentAndStartSelected:
      do {
        try await coordinator.finishActiveWorkout()
        onWorkoutSaved?()
        pendingConflict = nil
        let presentation = try await coordinator.buildStartPresentation(
          request: StrengthWorkoutStartRequest(target: target, source: source, skipPreFlight: false)
        )
        onPresentWorkout(presentation)
      } catch {
        Self.logger.error("Finish-and-start failed: \(error.localizedDescription, privacy: .public)")
        alertMessage = "Could not finish your current workout. Please try again."
        isConflictDialogPresented = true
      }

    case .discardCurrentAndStartSelected:
      do {
        try await coordinator.abandonActiveWorkout()
        pendingConflict = nil
        let presentation = try await coordinator.buildStartPresentation(
          request: StrengthWorkoutStartRequest(target: target, source: source, skipPreFlight: false)
        )
        onPresentWorkout(presentation)
      } catch {
        Self.logger.error("Abandon-and-start failed: \(error.localizedDescription, privacy: .public)")
        alertMessage = "Could not start this workout. Please try again."
        isConflictDialogPresented = true
      }

    case .cancel:
      cancelConflict()
    }
  }

  // MARK: - Private

  private func presentConflict(_ conflict: GymWorkoutStartConflict) {
    pendingConflict = conflict
    isAbandonConfirmationPresented = false
    isConflictDialogPresented = true
  }
}
