import Foundation
import OSLog
import SwiftData

enum SwiftDataContainerFailureCategory: String, Sendable {
  case freshStoreCreationFailure
  case unsupportedModelVersion
  case migrationFailure
  case corruptedStore
  case schemaConstructionFailure
  case unknown
}

struct SwiftDataContainerDiagnostics: Sendable {
  let failureCategory: SwiftDataContainerFailureCategory
  let errorReflection: String
  let errorChain: [String]
  let storeURL: String?
  let isInMemory: Bool
  let currentSchemaVersion: String
  let migrationPlanSchemaVersions: [String]
  let migrationPlanStageCount: Int

  #if DEBUG
  var debugSummary: String {
    """
    failureCategory=\(failureCategory.rawValue)
    storeURL=\(storeURL ?? "default")
    inMemory=\(isInMemory)
    currentSchemaVersion=\(currentSchemaVersion)
    migrationPlanSchemaVersions=\(migrationPlanSchemaVersions.joined(separator: ", "))
    migrationPlanStageCount=\(migrationPlanStageCount)
    errorReflection=\(errorReflection)
    errorChain:
    \(errorChain.map { "  - \($0)" }.joined(separator: "\n"))
    """
  }
  #endif

  func log(using logger: Logger) {
    logger.error(
      "SwiftData container startup failed category=\(self.failureCategory.rawValue, privacy: .public) storeURL=\(self.storeURL ?? "default", privacy: .public) inMemory=\(self.isInMemory, privacy: .public) currentSchemaVersion=\(self.currentSchemaVersion, privacy: .public) migrationPlanSchemaVersions=\(self.migrationPlanSchemaVersions.joined(separator: ", "), privacy: .public) migrationPlanStageCount=\(self.migrationPlanStageCount, privacy: .public)"
    )
    logger.error("SwiftData error reflection: \(self.errorReflection, privacy: .public)")
    for entry in errorChain {
      logger.error("SwiftData error chain: \(entry, privacy: .public)")
    }
  }

  static func make(
    error: Error,
    schema: Schema,
    configuration: ModelConfiguration,
    migrationPlan: any SchemaMigrationPlan.Type
  ) -> SwiftDataContainerDiagnostics {
    let storeURL = configuration.url.absoluteString
    let isInMemory = configuration.isStoredInMemoryOnly
    let currentSchemaVersion = String(describing: TaiAssistantSchema.currentVersionIdentifier)
    let migrationPlanSchemaVersions = migrationPlan.schemas.map {
      String(describing: $0.versionIdentifier)
    }
    let errorChain = Self.flattenErrorChain(error)
    let failureCategory = Self.categorize(
      error: error,
      errorChain: errorChain,
      isInMemory: isInMemory,
      storeExists: Self.storeExists(at: configuration.url)
    )

    return SwiftDataContainerDiagnostics(
      failureCategory: failureCategory,
      errorReflection: String(reflecting: error),
      errorChain: errorChain,
      storeURL: storeURL,
      isInMemory: isInMemory,
      currentSchemaVersion: currentSchemaVersion,
      migrationPlanSchemaVersions: migrationPlanSchemaVersions,
      migrationPlanStageCount: migrationPlan.stages.count
    )
  }

  private static func storeExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  private static func flattenErrorChain(_ error: Error) -> [String] {
    var entries: [String] = []
    var current: NSError? = error as NSError
    var seen = Set<String>()

    while let nsError = current {
      let key = "\(nsError.domain)#\(nsError.code)"
      guard seen.insert(key).inserted else { break }

      let userInfoSummary = nsError.userInfo
        .map { key, value in
          let renderedValue: String
          if key == NSUnderlyingErrorKey {
            renderedValue = "(underlying error)"
          } else {
            renderedValue = String(reflecting: value)
          }
          return "\(key)=\(renderedValue)"
        }
        .sorted()
        .joined(separator: "; ")

      entries.append(
        "domain=\(nsError.domain) code=\(nsError.code) userInfo={\(userInfoSummary)}"
      )
      current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
    }

    return entries
  }

  private static func categorize(
    error: Error,
    errorChain: [String],
    isInMemory: Bool,
    storeExists: Bool
  ) -> SwiftDataContainerFailureCategory {
    let haystack = ([String(reflecting: error)] + errorChain).joined(separator: " ").lowercased()

    if haystack.contains("migration") || haystack.contains("migrate") {
      return .migrationFailure
    }
    if haystack.contains("incompatible") || haystack.contains("unsupported") || haystack.contains("version") {
      return .unsupportedModelVersion
    }
    if haystack.contains("corrupt") || haystack.contains("integrity") {
      return .corruptedStore
    }
    if haystack.contains("checksum") || haystack.contains("schema") {
      return .schemaConstructionFailure
    }
    if !storeExists && !isInMemory {
      return .freshStoreCreationFailure
    }
    return .unknown
  }
}
