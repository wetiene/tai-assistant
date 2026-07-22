# SwiftData schema migration

## Version history

| Version | Identifier | Models added / changed |
|---------|------------|-------------------------|
| 1 | `1.0.0` | Goals, meals, corrections, recurring meals, alcohol, weight, app config, persisted conversation |
| 2 | `2.0.0` | `WorkoutSessionLog`, `WorkoutSetLog` (gym vertical slice) |
| 3 | `3.0.0` | `GymWorkoutPlan` (user-editable workout plans) |

## Architecture

- `TaiAssistantSchemaV1` — pre-workout schema snapshot (existing production stores).
- `TaiAssistantSchemaV2` — adds workout session/set logging.
- `TaiAssistantSchemaV3` — current schema; adds persisted gym plans.
- `TaiAssistantMigrationPlan` — lightweight migrations V1→V2 and V2→V3.

`AppModelContainerFactory` opens the store with `Schema(versionedSchema: TaiAssistantSchemaV3.self)` and `migrationPlan: TaiAssistantMigrationPlan.self`.

## Guarantees

- No store reset on upgrade.
- Existing `MealLog`, `PersistedConversation`, and other V1 entities are preserved.
- New workout tables are created empty on first launch after upgrade.

## Verification

Run `WorkoutSchemaMigrationTests` in `TaiAssistantTests`. The test:

1. Creates a V1 store on disk with meal + conversation rows.
2. Reopens with the migration plan at V2.
3. Asserts meal and conversation counts unchanged.
4. Asserts workout repository operations succeed on the migrated store.

## Adding schema version 3+

1. Add `TaiAssistantSchemaV3` with the full model list.
2. Append a new `MigrationStage` to `TaiAssistantMigrationPlan.stages`.
3. Update `TaiAssistantSchema.current` to V3.
4. Extend migration tests with a V2 → V3 fixture.
