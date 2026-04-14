# Tai Assistant App Scaffold (A1)

## Structure

- `App/`: app bootstrapping, app config, navigation shell, dependency wiring
- `Core/`: shared architecture primitives (design system, persistence, service contracts)
- `Features/`: feature-owned presentation surfaces

## Decisions

- Feature-based folders with neutral names to avoid coupling flows to implementation details.
- Protocol-driven contracts in `Core/Services/Protocols` so feature code depends on interfaces.
- Mock-first defaults in `AppDependencies` so the app can render and navigate before live integrations.
- Shared SwiftData container bootstrapped at app launch for V1 simplicity.
- No photo storage path is included in V1 scaffold (text-first persistence only).
- iPhone-only is represented in config and expected to be locked in target settings when project files are generated.

## Deferred

- Real AI/HealthKit/persistence implementations.
- Business rules and domain behavior.
- Production navigation destinations for Ask Tai.
