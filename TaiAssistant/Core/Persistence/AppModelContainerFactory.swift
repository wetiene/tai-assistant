import Foundation
import OSLog
import SwiftData

enum AppModelContainerFactory {
  private static let logger = Logger(subsystem: "com.taiassistant", category: "Persistence")

  static func makeContainer(
    inMemory: Bool,
    includePreviewSeedData: Bool = false,
    ownerID: String = "preview.user",
    storeURL: URL? = nil
  ) -> ModelContainer {
    let schema = Schema(versionedSchema: TaiAssistantSchema.current)
    let configuration: ModelConfiguration
    if let storeURL {
      configuration = ModelConfiguration(url: storeURL)
    } else {
      configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
    }

    do {
      let container = try ModelContainer(
        for: schema,
        migrationPlan: TaiAssistantMigrationPlan.self,
        configurations: [configuration]
      )
      if includePreviewSeedData {
        try PreviewSeedData.seedIfNeeded(in: container, ownerID: ownerID)
      }
      return container
    } catch {
      let diagnostics = SwiftDataContainerDiagnostics.make(
        error: error,
        schema: schema,
        configuration: configuration,
        migrationPlan: TaiAssistantMigrationPlan.self
      )
      diagnostics.log(using: logger)
      #if DEBUG
      fatalError("Failed to build SwiftData container.\n\(diagnostics.debugSummary)")
      #else
      fatalError("Failed to build SwiftData container: persistence startup failed (\(diagnostics.failureCategory.rawValue)).")
      #endif
    }
  }

  /// Opens a V1-only store for migration tests (no workout entities).
  static func makeLegacyV1Container(storeURL: URL) throws -> ModelContainer {
    let schema = Schema(versionedSchema: TaiAssistantSchemaV1.self)
    let configuration = ModelConfiguration(url: storeURL)
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  /// Opens a V2 store for migration tests (workouts, no gym plans).
  static func makeLegacyV2Container(storeURL: URL) throws -> ModelContainer {
    let schema = Schema(versionedSchema: TaiAssistantSchemaV2.self)
    let configuration = ModelConfiguration(url: storeURL)
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  /// Opens a V3 store for migration tests (historical `GymWorkoutPlanV3` only).
  static func makeLegacyV3Container(storeURL: URL) throws -> ModelContainer {
    let schema = Schema(versionedSchema: TaiAssistantSchemaV3.self)
    let configuration = ModelConfiguration(url: storeURL)
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}
