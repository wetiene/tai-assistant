import SwiftData

/// Versioned SwiftData migration plan. Lightweight stage adds workout tables without touching meal/goal/conversation rows.
enum TaiAssistantMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            TaiAssistantSchemaV1.self,
            TaiAssistantSchemaV2.self,
            TaiAssistantSchemaV3.self,
            TaiAssistantSchemaV4.self,
            TaiAssistantSchemaV5.self,
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TaiAssistantSchemaV1.self,
        toVersion: TaiAssistantSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: TaiAssistantSchemaV2.self,
        toVersion: TaiAssistantSchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: TaiAssistantSchemaV3.self,
        toVersion: TaiAssistantSchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: TaiAssistantSchemaV4.self,
        toVersion: TaiAssistantSchemaV5.self
    )
}
