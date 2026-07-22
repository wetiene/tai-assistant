# SwiftData schema migration

## Version history

| Version | Identifier | Models added / changed |
|---------|------------|-------------------------|
| 1 | `1.0.0` | Goals, meals, corrections, recurring meals, alcohol, weight, app config, persisted conversation |
| 2 | `2.0.0` | `WorkoutSessionLog`, `WorkoutSetLog` (gym vertical slice) |
| 3 | `3.0.0` | `GymWorkoutPlan` (user-editable workout plans, historical entity name on disk) |
| 4 | `4.0.0` | Trainer-plan lifecycle and structured import metadata on `GymWorkoutPlan` |
| 5 | `5.0.0` | `WorkoutSessionLog.debriefJSON` (persisted strength coach debrief) |

**Current schema: V5**

## Architecture

- `TaiAssistantSchemaV1` — pre-workout schema snapshot.
- `TaiAssistantSchemaV2` — adds workout session/set logging (frozen historical `WorkoutSessionLog` without debrief).
- `TaiAssistantSchemaV3` — adds persisted gym plans (`GymWorkoutPlanV3` nested type).
- `TaiAssistantSchemaV4` — production `GymWorkoutPlan` with import metadata; still uses frozen V2 workout models.
- `TaiAssistantSchemaV5` — production `WorkoutSessionLog` with optional `debriefJSON`.
- `TaiAssistantMigrationPlan` — lightweight migrations V1→V2, V2→V3, V3→V4, V4→V5.

`AppModelContainerFactory` opens the store with `Schema(versionedSchema: TaiAssistantSchemaV5.self)` and `migrationPlan: TaiAssistantMigrationPlan.self`.

## Frozen historical schema rule

Each versioned schema must reference **frozen model types** for entities that change across versions. Production `@Model` classes in `WorkoutPersistentModels.swift` and `GymPlanPersistentModels.swift` must not be referenced directly from older schema versions.

Example: V2–V4 use `TaiAssistantSchemaV2.WorkoutSessionLog` (no `debriefJSON`). V5 uses the production `WorkoutSessionLog` with `debriefJSON`.

Changing a production model without adding a new schema version and migration stage will break existing stores.

## Session snapshot JSON (not schema versioned)

`WorkoutSessionLog.activeSessionJSON` stores a `WorkoutSessionSnapshotEnvelope`:

- `kind`: `strength_coach` or `legacy_gym_active`
- `version`: envelope format version (currently `2`)
- Strength sessions include accepted proposals, pre-flight proposals, origin, and snapshot metadata

Malformed envelopes decode safely to `nil` without deleting the store row.

## Guarantees

- No store reset on upgrade.
- Existing meals, conversations, workouts, and gym plans are preserved across migrations.
- V4→V5 adds optional `debriefJSON` (nil for existing rows).
- Legacy `GymActiveSession` JSON in `activeSessionJSON` migrates to strength sessions at decode time.

## Verification

Run `WorkoutSchemaMigrationTests` in `TaiAssistantTests`. Coverage includes:

1. V1→V5 meal and conversation preservation
2. V2→V3 gym plan enablement
3. V3→V4 trainer-plan metadata migration
4. V4→V5 debrief column migration
5. V4 active legacy session restore after V5 migration

## Development stores

If a simulator store was created during an intermediate broken V4/V5 build (identical schema versions), migration may fail at launch. **Do not auto-reset production stores.** For local simulators, delete the app or remove `default.store` from the simulator container.

## Adding schema version 6+

1. Add `TaiAssistantSchemaV6` with frozen copies of any changed entities.
2. Append a lightweight `MigrationStage` to `TaiAssistantMigrationPlan.stages`.
3. Update `TaiAssistantSchema.current` to V6.
4. Extend `WorkoutSchemaMigrationTests` with a V5→V6 fixture test.
5. Update this document.
