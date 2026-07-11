# TAI_PRODUCT_V2_P0_BLUEPRINT

**Status:** Product definition — not an implementation ticket  
**Audience:** Product, design, engineering agents  
**Date:** 2026-07-11 (IA aligned 2026-07-11 to constitutional Home / Tai navigation)  
**Scope:** P0 product outcome for Tai’s pivot to a personalised AI health and performance coach  
**Constitution:** Obeys `Docs/` constitutional layer (`Docs/README.md`). If this blueprint conflicts with manifesto, principles, decisions or AI architecture, those documents win until a superseding decision is recorded.  

---

## 1. Executive summary

### What Tai is becoming

Tai is a personalised AI health and performance coach for iPhone.

Tai continuously learns from a user’s nutrition, training, recovery and (when available) health signals, then gives timely, practical guidance that helps the user make better decisions **before they matter**.

Tai is not a collection of trackers. Nutrition, training, sleep, weight, recovery and future signals contribute to one unified model of the user, their goal, their current state and their plan.

**Core product feeling:** “Tai knows me, remembers what matters and tells me what to do next.”

### Who it serves

Primary user: an adult who already trains (or is starting a simple program), cares about nutrition, and wants coaching that reduces decision friction — not another dashboard to interpret.

Secondary user: someone returning to training or body recomposition who needs a clear daily focus, reliable meal logging and a workout plan they already have (imported), without medical claims.

### What P0 proves

P0 proves the **complete core loop**, not “all health functionality”:

1. Tai understands the user’s goal.
2. Tai provides a useful daily briefing.
3. The user can check in with food quickly.
4. Tai remembers meals and corrections.
5. The user can import a workout via paste or photo.
6. Tai guides the user through that workout.
7. The user can log sets with minimal friction.
8. Tai uses previous performance to suggest the next appropriate action.
9. Tai explains its recommendations.
10. The user can ask Tai contextual questions.
11. The Home briefing reflects nutrition and workout activity together.
12. The architecture is ready for future Apple Health and proactive context **without pretending those integrations already exist**.

### Explicitly outside P0

| Out of P0 | Why |
|-----------|-----|
| Apple Health / HealthKit read integration | Designed now; implemented later |
| Manual sleep or weight logging | Locked decision — never build these workflows |
| Continuous location / office restaurant recommendations | Future privacy-sensitive capability |
| Tai-generated full workout programs | P0 is import-first; generation comes later |
| Supplements tracking | No validated P0 need |
| Household / shared visibility features | Models exist (`VisibilityScope`) but are unused and distract from coaching |
| Live medical diagnosis or treatment advice | Safety boundary |
| Mandatory per-set photo logging | Photos assist recognition; they must not become ceremony |
| Push notification spam / background surveillance | Controllable, high-value notifications only |
| Full conversational Home transcript | Home is a briefing; Tai is the Conversation |

---

## 2. Product principles

Enforceable decision rules for every future feature:

1. **Coaching is the product; tracking is infrastructure.** If a screen forces the user to interpret numbers before receiving guidance, redesign it.
2. **One primary action at a time.** Home, Tai and contextual Workout each highlight a single next move.
3. **Tai speaks first.** Tai tells the user what matters; the user does not hunt for insight.
4. **Never request what another trusted source can provide.** Prefer Apple Health over manual sleep/weight; prefer imported plans over blank program builders.
5. **Every AI interpretation is reviewable** before it becomes a confirmed fact.
6. **Every recommendation is explainable** (reason + evidence + confidence).
7. **Learned memory is visible, correctable and deletable.**
8. **Proactive behaviour is permissioned and controllable.** Opt-in by category; frequency caps; quiet hours.
9. **Blank states stay intelligent.** Empty does not mean dumb — offer the next useful setup step.
10. **Do not invent data.** Insufficient history → ask, wait or give conservative guidance with explicit uncertainty.
11. **Avoid fake precision.** Prefer ranges, confidence bands and “approximate” language for nutrition and loads.
12. **Safety over engagement.** Pain, injury, aggressive deficits and unsafe overload beat retention tactics.
13. **Calm, premium, native iOS.** Reduce dashboard density; keep motion intentional.
14. **Coral is for Tai, recommendations and primary actions** — not decorative chrome everywhere.
15. **Do not turn every screen into chat bubbles.** Conversational tone ≠ transcript UI.
16. **AI suggests; humans decide.** No silent mutation of meals, sets, goals or programs.

---

## 3. Current-state assessment

Inspection date: 2026-07-11. Paths refer to the repository at the time of this blueprint.

### 3.1 Current screens and journeys

| Area | Implementation | Maturity |
|------|----------------|----------|
| Shell navigation | `TaiAssistant/App/Navigation/AppShellView.swift` — tabs: Dashboard, Check In, Goals; custom bottom bar; Ask Tai FAB on Dashboard | Production UI |
| Dashboard / “Today with Tai” | `Features/Dashboard/Presentation/DashboardView.swift` (~1.1k lines) — calorie ring hero, macros, Next Best Meal, today’s meals (delete/undo), Smart Patterns, Alcohol Budget | Strong nutrition dashboard; **tracker-first**, not coach-first |
| Check In (meals) | `Features/CheckIn/` — text + camera photo, AI interpret, confirmation, refinement, ambiguity UI | Most complete feature |
| Goals | `Features/Goals/Presentation/GoalsView.swift` — AI interpret goal → macro targets → save | Usable; top-level tab |
| Ask Tai | `AskTaiEntrySheet` + `AskTaiResponseView` + `MockAskTaiGuidanceService` | **Preview only** — local mock responses; not live AI |
| MealCapture (legacy) | `Features/MealCapture/` | Parallel prototype flow; **not wired** into `AppShellView` |
| Workout | — | **Does not exist** |
| Settings / privacy / memory UI | Consent sheet + privacy link only | Incomplete |
| Notifications | — | **Does not exist** |
| Apple Health UI | Protocol stub only | Not user-facing |

**Actual user journey today:** open Dashboard → see calorie ring → optionally Check In meal → confirm → return to Dashboard. Goals are a separate silo. Ask Tai is a preview strategist sheet seeded from Dashboard prompts.

### 3.2 Current architecture

```
App/          bootstrapping, AppConfig, AppShellView, AppDependencies
Core/         design system, SwiftData models/repos, AI/Health protocols, legal
Features/     Dashboard, CheckIn, Goals, AskTai, MealCapture (orphan)
tai-ai-proxy/ Cloudflare Worker: POST /ai/interpret-meal, /ai/interpret-goal
```

- **Persistence:** SwiftData via `AppModelContainerFactory` + `LocalSwiftDataRepositories`.
- **DI:** `AppDependencies.live` / `mocksOnly`; protocol-driven repos and services.
- **AI:** App never holds OpenAI keys; `OpenAIProxyAIService` posts to proxy (`Docs/ai-proxy-meal-interpretation-contract.md`).
- **Health:** `HealthService` + `MockHealthService` returning empty steps/calories; **not called from UI**.
- **Config:** `RuntimeAppConfig` switches mock vs openAIProxy; bearer token via env/Info.plist.
- **Tests:** No iOS unit/UI test target in `TaiAssistant.xcodeproj`. Proxy has Vitest (`tai-ai-proxy/test/`).
- **Feature flags:** None.
- **Analytics:** None observed in app code.

### 3.3 Reusable assets (retain / adapt)

| Asset | Path | Recommendation |
|-------|------|----------------|
| Check In meal interpret + confirm loop | `Features/CheckIn/` | **Retain and extend** — gold-standard “AI suggests, human confirms” pattern |
| Photo capture + resize preprocessor | `CheckInCamera*`, `CheckInPhotoUploadPreprocessor` | Reuse for workout plan photos and optional exercise recognition |
| AI proxy + meal/goal contracts | `AIService.swift`, `tai-ai-proxy` | Extend with workout-interpret and coaching-chat endpoints |
| Consent + legal footnotes | `Core/Legal/` | Extend categories (workout import, Ask Tai live, notifications) |
| Design tokens | `DSColor`, `DSSpacing`, cards, coral gradient buttons | Retain identity; change hierarchy of use |
| SwiftData meal + goal models | `PersistentModels.swift` | Adapt; add workout/coaching entities |
| Meal refinement payload | `AIProxyMealRefinementPayload` | Pattern for workout-interpretation refinement |
| Delete + undo on meals | Dashboard meal rows | Reuse interaction pattern for set/meal corrections |
| Protocol + mock wiring | `AppDependencies`, `MockServices` | Continue for new domains |

### 3.4 Structural problems

1. **Product identity mismatch:** Home is a calorie dashboard (`TodayStatusHero` giant ring), not a briefing.
2. **Goals as permanent tab** blocks Tai as the Conversation relationship surface.
3. **No unified coaching layer** — “Next Best Meal” is local heuristic copy in `DashboardState`, not a recommendation object with evidence.
4. **Orphan / scaffold debt:** `MealCapture` unused; `FineTuneCorrection` repo unused by Check In saves; `WeightLog` / `AlcoholPlan` / `RecurringMeal` partially modelled but weakly productised; `VisibilityScope` / sharing unused.
5. **Ask Tai is mock-only** while meal/goal AI is live — incoherent trust model.
6. **ARCHITECTURE.md is outdated** (still “scaffold / deferred”).
7. **No workout domain** — largest P0 gap.
8. **DashboardView monolith** (~1128 lines) mixes presentation, state building and heuristics — migration risk hotspot.
9. **No iOS automated tests** — regression risk as navigation and models change.
10. **Single hardcoded owner** `preview.user` — acceptable for P0 local-first, but memory and notifications must assume future auth.

### 3.5 UX problems

- Numbers dominate; coaching is secondary caption under the ring.
- Alcohol Budget and Smart Patterns compete for attention without clear actionability.
- Check In is meal-only; multi-domain capture must move into the Tai Conversation rather than a third tab.
- Goals “Goal Studio” feels like a macro calculator, not goal/phase coaching.
- Ask Tai preview can over-promise (“Strategist summary”) while disclosing mock status inconsistently across entry points.
- No surface for “what Tai remembers” or correcting memory.
- Empty health signals are invisible (because Health is unused), so users cannot yet learn Tai’s honest missing-data behaviour.

### 3.6 Technical risks

- Extending SwiftData schema without migration plan for existing meal/goal data.
- Adding large features into `DashboardView` / `AppShellView` without modularisation → merge conflicts (already flagged in `Docs/dev-workflow.md`).
- Proxy schema growth without versioned contracts.
- Photo payloads for workout sheets may hit Worker size/CPU limits (meal path already logs content length).
- Live Tai Conversation without Context Prompt assembly will feel dumb relative to meal Check In refinement quality.

### 3.7 Privacy and safety gaps

- Consent covers meal/goal AI; does not yet cover workout images, chat history, or notifications.
- No injury/pain/aggressive-goal behavioural guards in product logic (disclaimers exist: `NutritionEstimateDisclaimer`, consent copy).
- `FineTuneCorrection` unused → corrections do not systematically train memory.
- Weight model exists (`WeightLog`) — **must not** grow a manual logging UI; treat as deprecated write path pending HealthKit.
- No notification permission architecture.
- No memory export/delete UI.

### 3.8 Assumptions requiring validation

| Assumption | Validation needed |
|------------|-------------------|
| Import-first workout onboarding is enough for first users | User interviews / TestFlight |
| Users accept Home as briefing without a calorie ring hero | A/B or qualitative test |
| Set logging can beat Notes/Strong for imported plans | Timed task study |
| Meal memory reuse is the highest friction reducer after confirm | Analytics after P0.3 |
| Coral + card language still feels premium when less “dashboard” | Design critique |
| Optional RPE is unnecessary in P0 | Coach/athlete feedback |

### 3.9 Retain / adapt / deprecate / remove / migrate

| Item | Action |
|------|--------|
| Check In meal flow | **Retain** as Meal path inside Tai Conversation |
| AI proxy meal + goal | **Adapt** (add workout interpret + contextual ask) |
| GoalProfile + DailyTargets | **Adapt** into Goal + Phase inside Tai |
| MealLog / MealItem | **Retain**; add provenance + memory links |
| Design system + coral | **Retain**; re-map semantics |
| Ask Tai UI shell | **Adapt** from preview → live Tai Conversation |
| Dashboard calorie ring as hero | **Deprecate** as identity; keep compact nutrition strip |
| Alcohol Budget on Home | **Deprecate from Home**; move to Tai preferences if retained |
| Smart Patterns card as-is | **Adapt** into meal memory / wins |
| MealCapture feature folder | **Remove** from product surface; delete or archive after Check In parity confirmed |
| WeightLog write APIs in UI | **Do not ship UI**; migrate later to HealthKit-sourced `HealthSignal` |
| VisibilityScope / sharing | **Defer**; keep fields inert |
| FineTuneCorrection | **Migrate** into explicit MemoryCorrection pipeline |
| RecurringMeal | **Adapt** into MealMemory (user-confirmed reusable meals) |
| HealthService stub | **Adapt** into future HealthKit adapter; Home uses Unavailable signal now |

**Rewrite verdict:** Incremental migration is better than rewrite. The Check In confirm pattern, proxy, SwiftData meals/goals and design system are real assets. Rewrite would discard the only production-proven AI loop.

---

## 4. Target information architecture

### 4.1 Primary navigation

```
┌──────────────────────────────────────────────┐
│  Home                              Tai       │
└──────────────────────────────────────────────┘
```

```text
Home
 ↓
Tai
```

- **Home** — personalised daily briefing (not a Conversation transcript).
- **Tai** — the single conversational workspace: one active Conversation for nutrition, workouts, goals, coaching, Memory, preferences and future health guidance.

Goals are **not** a top-level tab. Workout is **not** a permanent tab; it launches contextually from Home or Tai. Check In and Coach are **not** navigation destinations.

Capabilities live **inside** the Tai Conversation (cards, attachments, confirmation flows) rather than as separate application screens.

### 4.2 Screen hierarchy (text map)

```
AppShell
├── Home (Briefing)
│   ├── → Start / Resume Workout (contextual)
│   ├── → Open Tai with meal / workout / goal intent
│   ├── → Why this Recommendation? (sheet)
│   ├── → Recent meal Artifact detail
│   └── → Signal unavailable explainer (sheet)
│
└── Tai (Conversation workspace)
    ├── Active Conversation (one thread)
    │   ├── Meal check-in (composer, photo, confirmation)
    │   ├── Workout import / today’s workout entry
    │   ├── Goal & phase management
    │   ├── Recommendations + Evidence + Confidence
    │   ├── Attachments (meal photo, workout screenshot)
    │   └── Archive → Archive package
    ├── Workout Plan Overview (opened from Conversation)
    │   ├── Import (paste / photo)
    │   ├── Interpretation Review
    │   └── Plan detail / edit (confirmed changes only)
    ├── Progress Narrative
    ├── Memory & learned data controls
    ├── Notification Preferences
    └── Settings & Privacy
        ├── AI consent & disclosures
        ├── Health permissions (future)
        ├── Location permissions (future)
        └── Data deletion

Contextual full-screen flows
├── Workout Session
│   ├── Exercise Detail
│   ├── Set Logging
│   ├── Optional Photo Assist (exercise / weight)
│   └── Completion Summary
└── Onboarding (first-run)
    ├── Purpose + consent
    ├── Goal capture (via Tai)
    └── Optional workout import
```

### 4.3 Where key capabilities live

| Capability | Home | Tai | Contextual |
|------------|------|-----|------------|
| Daily briefing | ● | | |
| Next action / Recommendation | ● | ● | |
| Meal log | deep link | ● | |
| Start workout | deep link | ● | ● |
| Conversation | | ● | |
| Goals / phase | summary | ● | |
| Plan management | | ● | |
| Memory controls | | ● | |
| Notifications prefs | | ● | |
| Settings / privacy | | ● | |

### 4.4 Modal vs full-screen

| Flow | Presentation |
|------|----------------|
| Meal check-in | Within Tai Conversation stack or full-screen cover from Home CTA |
| Meal confirmation | Same stack (inline, as today) |
| Tai Conversation | Primary tab surface |
| Workout import + review | Full-screen (from Tai) |
| Active workout | Full-screen (hides tab bar) |
| Why Recommendation | Sheet |
| Consent / permissions | Sheet |
| Settings | Push from Tai |

---

## 5. Target screen specifications

Conventions for all screens:

- **Uncertainty:** show confidence language; never fake exactness.
- **Accessibility:** Dynamic Type, VoiceOver labels on primary actions, Reduce Motion alternatives, sufficient contrast on coral CTAs.
- **Analytics (P0 minimum):** `screen_view`, `primary_action`, `ai_interpret_started|confirmed|edited|discarded`, `recommendation_shown|accepted|dismissed|explained`, `permission_prompted|accepted|denied`.

### 5.1 Home briefing

| Field | Spec |
|-------|------|
| Purpose | Tell the user what matters now, what Tai noticed, what to do next, and why |
| Entry | App launch; tab Home |
| Key content | Greeting; primary focus; **one** next action; compact nutrition state; scheduled/active workout; recent check-ins; one win/progress note; unavailable-signal honesty |
| Primary action | Execute next action (e.g. Start workout / Log lunch / Review protein) |
| Secondary | Why?; open Tai; open recent meal |
| Empty | “Let’s set your goal” or “Import your workout plan” with single CTA |
| Loading | Skeleton briefing cards |
| Error | Inline retry; last-known briefing if safe |
| Permission | If notifications not decided and value is clear, soft prompt after first successful workout — not on first launch |
| AI uncertainty | Prefer rule-based briefing when model confidence low; label “Based on today’s logs” |
| Data | Goal/phase, meals today, plan/session, recommendations, signal availability |
| Analytics | `home_briefing_view`, `home_next_action_tap`, `home_why_open` |

**Change from today:** Remove giant calorie ring as hero. Macros become supporting strip.

### 5.2 Tai Conversation — intent entry

| Field | Spec |
|-------|------|
| Purpose | Single conversational workspace; user starts or continues Meal, Workout, Goal or open coaching |
| Entry | Tab Tai; Home next-action deep link into Tai with intent |
| Key content | Active Conversation; suggested intents; optional contextual hint (“Workout scheduled for 6pm”) |
| Primary | Continue Conversation or choose an intent |
| Empty | Seed prompts grounded in actual state |
| Exclude | Weight, Sleep, Supplements as standalone logging |

### 5.3 Meal check-in

Retain current meal Check In strengths (composer, photo, context rows, interpret) as flows **inside Tai**, not as a separate tab.

| Enhancements | Spec |
|--------------|------|
| Quick reuse | Top suggestions from MealMemory |
| Day context | Compact remaining protein/calories (not a second dashboard) |
| Consent | Existing AI consent gate |

### 5.4 Meal interpretation confirmation

| Field | Spec |
|-------|------|
| Purpose | Human confirms AI estimate before save |
| Primary | Confirm meal(s) |
| Secondary | Edit label/items; choose alternative; re-estimate; discard |
| Uncertainty | Ambiguity chips + low-confidence hints (existing thresholds) |
| Data | Draft meals; day progress |

### 5.5 Meal history and quick reuse

| Field | Spec |
|-------|------|
| Purpose | Log remembered meals in seconds |
| Entry | Meal check-in; Home recent |
| Primary | Reuse as-is or tweak then confirm |
| Empty | “Meals you confirm become quick options here” |

### 5.6 Tai Conversation

| Field | Spec |
|-------|------|
| Purpose | Genuine Conversation with context, attachments, history — the relationship surface |
| Entry | Tab Tai; Home “Ask about this” / next-action deep link |
| Key content | Thread; context chips (today’s briefing, active goal, last workout); attachments (meal photo, workout screenshot); citations to Evidence; Confidence when uncertain |
| Primary | Send / confirm User Decision |
| Secondary | Attach; archive Conversation; stop |
| Empty | Seed prompts grounded in **actual** state, not generic marketing |
| Loading | Streaming or staged “Tai is thinking” with cancel |
| Error | Retry; offline message; never silently fall back to mock without Preview badge |
| P0 | Live proxy chat with structured coaching responses preferred over free-form only |
| Out | Medical diagnosis |

### 5.7 Tai workspace overview

| Field | Spec |
|-------|------|
| Purpose | Within Tai: goal, phase, plan, narrative and entries to management without extra tabs |
| Primary | Continue plan action (e.g. today’s workout or refine goal) via Conversation or card |
| Secondary | Memory, notifications, settings |

### 5.8 Goal and phase management

| Field | Spec |
|-------|------|
| Purpose | Capture/update goal + phase; AI interprets; user confirms targets |
| Entry | Tai Conversation; onboarding |
| Primary | Save confirmed goal/phase (User Decision → Artifact) |
| Safety | Block or soften aggressive deficit suggestions; require confirmation; show caution state |
| Migrate | Current `GoalsView` into Tai |

### 5.9 Workout plan import

| Field | Spec |
|-------|------|
| Purpose | Paste text or photo/screenshot of existing plan |
| Primary | Interpret |
| Secondary | Paste examples / tips |
| Consent | AI processing for workout content |

### 5.10 Workout interpretation review

| Field | Spec |
|-------|------|
| Purpose | Review structured exercises, sets, rep ranges, order, notes before save |
| Primary | Confirm & save plan |
| Secondary | Edit exercise; merge/split; discard |
| Uncertainty | Flag low-confidence lines; never auto-save |

### 5.11 Workout plan overview

| Field | Spec |
|-------|------|
| Purpose | See program structure, schedule mapping, last performed |
| Primary | Start today’s workout |
| Secondary | Re-import; edit with confirmation; archive |

### 5.12 Today’s workout

| Field | Spec |
|-------|------|
| Purpose | Session start surface: exercises, prior performance, suggested loads |
| Primary | Start / Resume |
| Secondary | Substitute exercise; skip; ask Tai |

### 5.13 Exercise detail

| Field | Spec |
|-------|------|
| Purpose | Targets, history, suggestion, notes |
| Primary | Log set |
| Secondary | Photo assist; substitute; mark warm-up |

### 5.14 Set logging

| Field | Spec |
|-------|------|
| Purpose | Fast capture of weight × reps (and optional RPE — **deferred by default in P0**) |
| Primary | Save set |
| Secondary | Adjust suggestion; skip set |
| Principle | Fewer taps than Notes; defaults from last working set |

**P0 decision:** Do **not** require RPE. Progression uses completed reps vs target range + prior load. Revisit RPE only if progression quality fails usability tests.

### 5.15 Exercise or machine photo recognition

| Field | Spec |
|-------|------|
| Purpose | Optional assist to identify exercise/machine or visible load |
| Primary | Confirm interpretation |
| Secondary | Edit; dismiss |
| Rules | Always uncertain; never required per set; one photo may cover multiple sets of same exercise |

### 5.16 Workout completion summary

| Field | Spec |
|-------|------|
| Purpose | What was done; wins; progression suggestion requiring confirmation |
| Primary | Done → Home |
| Secondary | Confirm progression change; ask why; discard suggestion |

### 5.17 Progress narrative

| Field | Spec |
|-------|------|
| Purpose | Short story of recent training + nutrition adherence — not a chart gallery |
| Charts | Optional supporting visuals; coaching copy leads |

### 5.18 Notification preferences

| Field | Spec |
|-------|------|
| Purpose | Per-category opt-in, quiet hours, frequency |
| Primary | Save preferences |
| Permission | System prompt only after user enables a category |

### 5.19 Memory and learned-data controls

| Field | Spec |
|-------|------|
| Purpose | See, edit, delete what Tai remembers |
| Primary | Correct or delete item |
| Empty | “As you confirm meals and workouts, memory appears here” |

### 5.20 Settings and privacy

| Field | Spec |
|-------|------|
| Purpose | Consent withdrawal, privacy policy, Health/Location future toggles, delete data |
| Primary | Manage privacy |

---

## 6. Core user journeys

### 6.1 New user onboarding (P0)

1. Launch → short value: “Tai coaches your nutrition and training together.”
2. AI processing consent (required before any AI call).
3. Goal capture (text) → interpretation review → confirm targets/phase.
4. Optional: import workout now or “Later in Tai.”
5. Land on Home briefing with explicit next action (“Log breakfast” or “Import workout”).

### 6.2 Returning user — morning Home (P0)

1. Open Home.
2. See greeting + focus (“Lower body day; protein behind after yesterday”).
3. One CTA (“Review today’s workout” or “Log breakfast”).
4. Compact nutrition + workout cards.
5. If sleep/weight unavailable: calm note, no manual log CTA.

### 6.3 Meal photo check-in (P0)

1. Tai (or Home CTA) → Meal check-in → capture photo (± text).
2. Consent if needed → interpret.
3. Review estimate; edit if needed → Confirm.
4. Home updates briefing + recent check-ins.

### 6.4 Repeating a remembered meal (P0)

1. Tai → Meal check-in → pick Memory suggestion.
2. Confirm or tweak → save.
3. Faster than re-describing.

### 6.5 Correcting an AI meal estimate (P0)

1. On confirmation, edit label/macros/items or choose alternative.
2. Confirm saves **user-approved** values.
3. Correction writes MemoryCorrection; future suggestions bias toward correction.
4. User can later delete that Memory in Tai → Memory.

### 6.6 Import workout from pasted text (P0)

1. Tai → Plan → Import → Paste.
2. Interpret → Review structure → Confirm save.
3. Plan appears in Tai and as Home workout card.

### 6.7 Import workout from photo (P0)

1. Same as paste, with screenshot/photo.
2. Low-confidence lines highlighted for edit before save.

### 6.8 Starting a scheduled workout (P0)

1. Home or Tai → Workout → Today’s workout → Start.
2. Enter session UI; tab bar hidden.

### 6.9 Logging a set manually (P0)

1. Select exercise → weight/reps prefilled from suggestion or last set.
2. Save set → advance.
3. No forced photo.

### 6.10 Photo assist for exercise/weight (P0 optional)

1. User taps Photo assist.
2. Tai proposes exercise identity and/or load with confidence.
3. User confirms or edits once; continues logging sets without re-photoing.

### 6.11 Receiving a progression suggestion (P0)

1. After session (or before next session), Tai suggests e.g. +2.5 kg on squat working sets.
2. Shows reason + evidence (hit top of rep range twice).
3. User Accept / Not now / Never for this exercise.
4. Only on Accept does plan target weight update (audited).

### 6.12 Asking why a recommendation was made (P0)

1. Tap Why on Home or completion summary.
2. Sheet lists Recommendation, reason, Evidence, Confidence, goal link.
3. Optional “Ask Tai more” opens the Tai Conversation with that Recommendation as context.

### 6.13 Completing a workout (P0)

1. Mark session complete (or complete last exercise).
2. Summary + optional progression confirmation.
3. Home briefing updates (“Session done — protein still open”).

### 6.14 Evening sleep-preparation notification (Future)

1. User opted into Recovery reminders; Health sleep/wind-down signals available **or** clock-based preference.
2. Tai sends one evening prep note with deep link to Home/Tai.
3. Suppressed if already asleep signal, DND, or frequency cap hit.

### 6.15 Office restaurant recommendation (Future)

1. Explicit location coaching opt-in; geofence around saved “office” place (not continuous tracking by default).
2. At lunch window, if nutrition behind and near office, suggest nearby options filtered by goal.
3. Honest uncertainty if menus unknown; prefer “likely high-protein options” over fake menu certainty.
4. Deep link to Tai with location context ephemeral.

### 6.16 Apple Health unavailable (P0 behaviour / Future integration)

Home shows: “Sleep and weight aren’t connected yet — Tai is coaching from nutrition and training.” No manual entry CTA.

### 6.17 Apple Health permission denied (Future)

Same honesty; Settings entry to revisit; coaching continues without those signals.

### 6.18 Apple Health data stale or incomplete (Future)

Mark signal stale; avoid strong claims; prefer “last weight from 12 days ago” over pretending currency.

---

## 7. Unified user model

### 7.1 Conceptual entities

| Concept | Meaning |
|---------|---------|
| UserGoal | What the user is trying to achieve (strength, recomposition, etc.) |
| ActivePhase | Time-bounded emphasis (e.g. “accumulate volume”, “cut calmly”) |
| Preferences | Units, quiet hours, coaching tone, dietary constraints |
| Constraints | Injuries, equipment limits, schedule limits (user-confirmed) |
| MealMemory | Reusable confirmed meal patterns |
| CorrectionHistory | Field-level before/after for AI outputs |
| WorkoutPlan | Imported (later: generated) program |
| WorkoutSession | A performed instance of a day/plan slice |
| ExerciseDefinition | Canonical exercise with aliases |
| ExerciseVariant | Machine vs free-weight, unilateral, grip, etc. |
| Equipment | Bar, dumbbell, named machine |
| PerformedSet | Confirmed set with load, reps, timestamps |
| ProgressionRule | How suggestions are produced (rep-range then load) |
| Recommendation | Coaching output object (see §9) |
| Evidence | Pointers to facts used |
| Confidence | 0–1 or enum band |
| UserDecision | Accept / reject / edit / defer on suggestions |
| NotificationPreference | Per-category controls |
| ContextualSignal | Ephemeral context (time of day, “at gym”) |
| HealthSignal | Read-only metrics from HealthKit (future) |
| SourceProvenance | Where data came from |
| AIMemory | Learned preferences/facts Tai may use |
| MemoryCorrection / MemoryDeletion | User controls |

### 7.2 Epistemic categories (critical)

| Category | Examples | May silently change records? |
|----------|----------|------------------------------|
| Confirmed facts | Saved MealLog, confirmed PerformedSet, saved Goal after confirm | No — only user actions |
| User preferences | Units, notification opts, dietary excludes | No without user edit |
| AI interpretations | Meal draft, imported plan draft | Must be confirmed |
| AI inferences | “Likely under-recovered”, “probably office lunch” | Display as inference; never write as fact |
| Recommendations | Next action, progression | Require accept when mutating plan |
| Temporary context | Session UI state, geofence trigger | Expires |
| Imported source data | Original paste text / photo reference metadata | Retained for audit; not editable as “truth” without re-import |

### 7.3 Provenance

Every persisted health-adjacent record should carry:

- `sourceType`: userEntered | aiInterpretedThenConfirmed | healthKit | importedDocument | systemDerived
- `sourceConfidence` (if AI involved)
- `confirmedAt` / `confirmedByUser`

---

## 8. Workout domain model

### 8.1 P0 entities (robust, not overbuilt)

```
WorkoutPlan
  id, ownerID, title, source (paste|photo), sourceRawRef,
  createdAt, updatedAt, status (draft|active|archived)

WorkoutDay / PlanDay
  id, planID, name (e.g. "Lower A"), sortOrder, notes

PlanExercise
  id, dayID, exerciseDefinitionID, sortOrder,
  targetSets, repRangeMin, repRangeMax,
  targetWeight? (user-confirmed), restSeconds?,
  groupId? (superset), isWarmupTemplate,
  notes, substitutionOf? 

ExerciseDefinition
  id, canonicalName, aliases[], laterality (bilateral|unilateral),
  equipmentClass (barbell|dumbbell|machine|cable|bodyweight|other)

ExerciseVariant
  id, definitionID, displayName, machineName?, loadSemantics (plate|stack|dumbbell)

WorkoutSession
  id, planID, dayID?, startedAt, endedAt?, status,
  userNotes

SessionExercise
  id, sessionID, planExerciseID?, definitionID, variantID?,
  status (pending|active|completed|skipped), substitutedFrom?

PerformedSet
  id, sessionExerciseID, setIndex,
  setRole (warmup|working),
  targetRepsMin?, targetRepsMax?,
  reps, weight, weightUnit,
  loadAmbiguityNote?,  // e.g. machine stack uncertain
  source (manual|photoAssistConfirmed),
  completedAt

ProgressionSuggestion
  id, planExerciseID, sessionID?,
  proposedTargetWeight, reason, evidenceRefs[],
  confidence, status (pending|accepted|rejected|expired)

PlanRevision
  id, planID, at, summary, userDecision, beforeJSON/afterJSON (or structured diff)
```

### 8.2 P0 rules

- Supersets: supported via `groupId` for display; logging remains per exercise (no forced complex editor).
- Unilateral: store per-side sets or a `side` field on PerformedSet when laterality ≠ bilateral.
- Machine weight ambiguity: allow `loadAmbiguityNote` + lower confidence; never invent stack-to-kg precision.
- Warm-ups vs working: explicit `setRole`; progression uses working sets only.
- Units: respect `MeasurementSystem`; store canonical kg internally with display conversion.
- Program revisions: **only** after UserDecision accept; write PlanRevision audit.
- Adaptive programming later: ProgressionRule interface should not hard-code a single algorithm in UI.

### 8.3 Explicitly deferred

- Full periodisation engine
- Auto-generated mesocycles
- Video form critique
- Social sharing of plans

---

## 9. Coaching model

### 9.1 Recommendation object

Every recommendation Tai shows must include:

| Field | Description |
|-------|-------------|
| `id` | Stable id for analytics and Why sheet |
| `recommendation` | Short directive (“Eat 40g protein in the next meal”) |
| `reason` | Human-readable why |
| `evidence[]` | Facts used (meal totals, last squat sets, goal phase) |
| `confidence` | band: high / medium / low |
| `relevantGoalID` | Link to goal/phase |
| `action` | Deep link / action type |
| `relevanceWindow` | e.g. expires end of local day |
| `requiresConfirmation` | true if accepting mutates plan/goals/records |
| `safetyFlags[]` | optional |

### 9.2 How data becomes advice (P0)

P0 coaching is primarily **deterministic with AI-assisted copy**, not opaque model autonomy:

1. Gather confirmed facts (meals, sessions, goal).
2. Evaluate rule library (protein gap, workout due, progression criteria, empty plan).
3. Rank by urgency × goal alignment × confidence × freshness.
4. Select **one** primary Home recommendation.
5. Optionally ask LLM to phrase explanation **constrained** to provided evidence (no new facts).

### 9.3 Precedence when signals conflict

Example conflict:

- Goal: increase strength  
- Nutrition: aggressive deficit  
- Performance: falling  
- Sleep: unavailable  

**Precedence (highest first):**

1. **Safety** (pain, injury flags, extreme deficit, unsafe overload) → protect, don’t push intensity.
2. **User-confirmed constraints** (injured shoulder, equipment limits).
3. **Confirmed recent performance trend** (over optimistic plan defaults).
4. **Confirmed nutrition adherence** (over assumed recovery).
5. **Goal aspiration** (direction, not a blunt instrument).
6. **Inferences from missing data** (lowest — speak tentatively or omit).

In the example, Tai should **not** recommend aggressive progression. Prefer: maintain loads, raise protein, note sleep unknown, ask user about recovery — and flag calorie deficit vs strength tension explicitly.

### 9.4 Know vs suspect

| Know | Suspect |
|------|---------|
| Saved meals, confirmed sets, confirmed goals | “You might be under-recovered” without Health |
| User rejected progression | Office lunch needs without location opt-in |
| Explicit pain note in session | Photo-estimated machine weight |

UI language: “Here’s what I know…” vs “I’m less sure about…”

---

## 10. AI memory model

### 10.1 What Tai should remember

- Confirmed meal patterns user reuses
- Label/macro corrections the user made
- Goal and phase statements
- Equipment available / substitutions chosen
- Preferred working weights after acceptance
- Notification and coaching preferences
- Explicit user notes (“travel Thursdays”)

### 10.2 What Tai should not remember

- Raw photos longer than needed for the active interpret session (align with current meal photo policy)
- Rejected interpretations as facts
- Inferences presented as confirmed preferences
- Sensitive health details beyond what user confirmed for coaching (e.g. diagnoses) — if volunteered, store only as user note with visibility in Memory
- Precise location history (future: minimise)

### 10.3 Lifecycle

1. **Create:** only after user confirmation, or explicit “Remember this.”
2. **Correct:** user edits memory item → CorrectionHistory + update.
3. **Surface:** Tai → Memory; occasional Home chip (“Using your usual breakfast”).
4. **Delete:** user deletes → tombstone; excluded from prompts.
5. **Stale:** unused meal memories fade from suggestions after N days without use (still listed in Memory until deleted).
6. **Confidence:** increases with repeated confirmations; decreases after user corrections against it.

### 10.4 Meal memory vs workout history

| | Meal memory | Workout history |
|--|-------------|-----------------|
| Nature | Reusable template | Chronological facts |
| Edit | Yes | Correct sets via explicit edit |
| Suggest reuse | Yes | Suggest loads from history |
| Delete | Removes future suggestions | Deleting sessions is destructive; confirm strongly |

### 10.5 Sensitive information

- Memory UI must show raw remembered text.
- Consent copy must mention workout photos and chat.
- Export/delete in Settings (P0.9).

---

## 11. Proactive notification strategy

### 11.1 Principles

- High value, explainable, controllable.
- Progressive permission: ask when enabling a category, not at install.
- No continuous location for P0.
- Default **off** for all proactive categories until user opts in (except transactional if any).

### 11.2 Categories

#### A. Workout reminders (P0)

| | |
|--|--|
| Trigger | Local scheduled time for plan day; or “usual training window” after user sets it |
| Evidence | Active plan + user preference time |
| Timing | 30–90 min before window (user setting) |
| Cap | 1/day; 4/week default |
| Suppress | Session already started/completed; quiet hours; manual snooze |
| Controls | On/off, time, days |
| Deep link | Today’s workout |
| Privacy | No location required |

#### B. Workout preparation (P0 light / Future richer)

| | |
|--|--|
| Trigger | Same as reminder with “what to expect” payload |
| Cap | Combined with A — not a second ping |

#### C. Nutrition guidance (P0)

| | |
|--|--|
| Trigger | Afternoon protein gap beyond threshold **and** no meal logged for N hours |
| Evidence | Confirmed meals + targets |
| Timing | User-defined afternoon window |
| Cap | 1/day |
| Suppress | Already logged catch-up meal; user dismissed similar today |
| Deep link | Meal check-in |
| Safety | No disordered-eating pressure copy; soft language |

#### D. Progress summaries (P0 weekly)

| | |
|--|--|
| Trigger | Weekly local time |
| Cap | 1/week |
| Deep link | Progress narrative |
| Content | Wins + one focus; no shame framing |

#### E. Sleep preparation (Future + Health)

| | |
|--|--|
| Trigger | Clock preference and/or Health wind-down; never claim sleep stage certainty |
| Cap | 1/night |
| Privacy | Health permission required for signal-based; clock-only possible with clear labeling |

#### F. Office restaurant (Future + Location)

| | |
|--|--|
| Trigger | Geofence enter saved Office + lunch window + nutrition gap |
| Evidence | Coarse location event; **not** continuous track |
| Cap | 2/week |
| Suppress | User logged lunch; travel mode; low confidence POI |
| Privacy | Explicit opt-in; no location history beyond ephemeral event |
| Reliability | Without live menus, recommendations must disclose uncertainty |

### 11.3 P0 notification implementation slice

Ship: preference UI + local notifications for A/C/D only.  
Defer: Health-triggered and location-triggered categories (architecture stubs only).

---

## 12. Apple Health integration boundary

### 12.1 Future read set

| Type | Use | Notes |
|------|-----|-------|
| Sleep analysis | Recovery coaching context | No stage-level medical claims |
| Body mass | Trend coaching | Prefer rolling trend over daily noise |
| Steps | Ambulation context | Weak signal alone |
| Active energy | Training day context | |
| Resting HR | Optional trend | Careful language |
| HRV | Only if clearly useful | Easy to overclaim — default exclude until justified |
| Workouts | Correlate with Tai sessions | Deduplicate carefully |

### 12.2 Rules

- **Read-only** into `HealthSignal` with provenance + `asOf`.
- **No manual sleep/weight logging** in Tai.
- Permission: request per meaningful benefit (“Use weight trends in your weekly coaching”).
- Missing: Home unavailable state (§6.16).
- Stale: mark and downgrade confidence.
- Conflicts: HealthKit vs user-confirmed Tai workout — show both; don’t auto-overwrite Tai session.
- Privacy: data stays on device where possible; if sent to AI, include in consent and minimise.

### 12.3 Home before integration exists (P0)

Always support `SignalAvailability.unavailable(reason: .notConnected)` for sleep/weight. Copy is calm and specific. No dead ends that demand Health.

---

## 13. Location-aware coaching boundary

### Designed, not in first implementation slice

- User saves an “Office” place explicitly.
- Prefer **geofencing** significant locations over continuous background location.
- Restaurant discovery is best-effort; **menu availability is usually missing** → recommendations must be probabilistic and filtered by dietary/goal constraints.
- If Confidence low: ask a question in Tai instead of pushing a notification.
- Inaccurate location: suppress rather than guess.
- Minimise history: store place labels + geofence ids, not breadcrumb trails.
- Controls: hard off switch; delete saved places.

**Critical product call:** Do not ship location restaurant notifications until menu confidence or honest uncertainty UX is proven. Architecture readiness ≠ feature commitment.

---

## 14. Target visual and interaction system

### 14.1 Retain

- Coral gradient for primary Tai actions (`DSColor.coralStart/End`)
- Warm surface accents (`warmSurface`)
- Card primitives (`PrimaryCard`, `DashboardCard`) — used more sparingly
- Custom bottom bar adapted for two tabs (Home | Tai)
- Native grouped backgrounds
- Confirmation-before-save patterns from the meal Check In loop (retained inside Tai)

### 14.2 Change

| Current | Target |
|---------|--------|
| Giant calorie ring hero | Briefing headline + one CTA; nutrition as compact strip |
| Dashboard / Goals labels | Home / Tai |
| Alcohol + patterns competing on Home | Remove from Home; memory/wins condensed |
| Ask Tai FAB only on Dashboard | Tai tab is the Conversation; FAB optional deep link into Tai |
| Card-heavy metric walls | One coaching composition first |
| Goals as macro studio | Goal/phase narrative + editable targets |

### 14.3 System guidance

- **Typography:** Large title for greeting; headline for recommendation; footnotes for evidence.
- **Spacing:** Keep `DSSpacing`; increase breathing room on Home vs dense Dashboard.
- **Cards:** Allowed for interactive clusters; avoid card-for-everything. Hero briefing should feel like one composition.
- **Colour:** Coral = Tai/recommendation/CTA; semantic green sparingly for “on track”; destructive coral for delete.
- **Conversational presentation:** Short paragraphs and “Tai says” voice without bubble threads on Home.
- **Buttons:** One coral primary; secondary plain/text.
- **Progress:** Thin bars or compact rings — never the identity.
- **Tab bar:** Home | Tai.
- **Image capture:** Reuse meal Check In camera patterns inside Tai; always show confirm.
- **Uncertainty:** Inline captions + chips, not modal panic.
- **Empty states:** Helpful next step, not illustrations-only.
- **Charts:** Secondary in Progress; not Home hero.
- **Accessibility:** Dynamic Type up to accessibility sizes; hit targets ≥44pt; VoiceOver reads recommendation + reason.
- **Dark mode:** Existing dynamic colors; verify coral contrast.
- **Reduce Motion:** Disable ring spin / large springs; keep fades.

---

## 15. P0 backlog

Format: `ID — User value — Depends on`

### P0.1 Foundation

- `P0.1.1` — Establish coaching domain types (Recommendation, Evidence, SignalAvailability) so features share one language — none
- `P0.1.2` — Extend AI service contracts for workout interpret and contextual ask without breaking meal/goal — P0.1.1
- `P0.1.3` — Add feature flags for Home/Tai/Workout rollout — none
- `P0.1.4` — Define SwiftData migration strategy for new entities while keeping meals/goals — none
- `P0.1.5` — Expand AI consent copy for workouts and chat — none

### P0.2 Home and navigation

- `P0.2.1` — Switch tabs to Home / Tai so the app matches the coaching product — P0.1.3
- `P0.2.2` — Replace calorie-ring hero with a daily briefing and one next action — P0.2.1, P0.1.1
- `P0.2.3` — Show compact nutrition and workout status that support the briefing — P0.2.2
- `P0.2.4` — Show honest “sleep/weight not connected” state without manual logging — P0.2.2
- `P0.2.5` — Move Goals UI into Tai without losing saved targets — P0.2.1

### P0.3 Meal speed and memory

- `P0.3.1` — Suggest remembered meals during check-in so repeats take seconds — P0.2.1
- `P0.3.2` — Persist user corrections into visible meal memory — P0.3.1
- `P0.3.3` — Let users edit or delete meal memories in Tai — P0.3.2
- `P0.3.4` — Reflect new meals in the Home briefing the same day — P0.2.2

### P0.4 Tai and Conversation

- `P0.4.1` — Ship Tai workspace with goal, phase and plan entry points inside Conversation — P0.2.5
- `P0.4.2` — Replace Ask Tai preview mocks with live contextual Conversation — P0.1.2, P0.1.5
- `P0.4.3` — Let users ask why a Recommendation was made and see Evidence — P0.2.2, P0.4.2
- `P0.4.4` — Keep Conversation history available in Tai (including Archive) — P0.4.2

### P0.5 Workout import

- `P0.5.1` — Import a workout plan from pasted text with confirmation before save — P0.1.2, P0.1.4
- `P0.5.2` — Import a workout plan from photo/screenshot with the same review step — P0.5.1
- `P0.5.3` — Show saved plan overview in Tai — P0.5.1
- `P0.5.4` — Surface today’s planned workout on Home — P0.5.3, P0.2.3

### P0.6 Guided workout and set logging

- `P0.6.1` — Start today’s workout in a focused session experience — P0.5.4
- `P0.6.2` — Log sets with weight and reps faster than using Notes — P0.6.1
- `P0.6.3` — Show previous performance while logging — P0.6.2
- `P0.6.4` — Allow exercise skip and simple substitution with confirmation — P0.6.1
- `P0.6.5` — Optional photo assist for exercise/load identity with mandatory confirm — P0.6.2, P0.1.5
- `P0.6.6` — End-of-session summary returns user to an updated Home — P0.6.2, P0.2.2

### P0.7 Coaching recommendations

- `P0.7.1` — Suggest next working weight/reps from prior confirmed sets — P0.6.3
- `P0.7.2` — Require explicit accept before changing programmed targets — P0.7.1
- `P0.7.3` — Rank a single Home recommendation across nutrition + training — P0.2.2, P0.6.6
- `P0.7.4` — Apply safety precedence when deficit and strength goals conflict — P0.7.3

### P0.8 Notifications and permissions

- `P0.8.1` — Let users opt into workout reminder notifications — P0.5.4
- `P0.8.2` — Let users opt into protein/nutrition nudges with frequency caps — P0.3.4
- `P0.8.3` — Weekly progress notification opt-in — P0.4.1
- `P0.8.4` — Quiet hours and per-category controls in Tai — P0.8.1

### P0.9 Privacy, safety and memory controls

- `P0.9.1` — Central Settings & Privacy with policy links and consent withdrawal — P0.1.5
- `P0.9.2` — Pain/injury session flag that suppresses aggressive progression — P0.6.6, P0.7.2
- `P0.9.3` — Caution flow for aggressive weight-loss target suggestions — P0.2.5
- `P0.9.4` — Memory browser with edit/delete — P0.3.3
- `P0.9.5` — Local data delete / reset path — P0.9.1

### P0.10 Release readiness

- `P0.10.1` — Instrument core analytics events for the P0 loop — parallel
- `P0.10.2` — Add iOS tests for recommendation ranking and workout import parsing fixtures — P0.5.1, P0.7.3
- `P0.10.3` — TestFlight checklist for consent, offline AI failure, and migration — P0.1.4
- `P0.10.4` — Remove or archive MealCapture orphan from shipping surface — P0.3.1
- `P0.10.5` — Update ARCHITECTURE.md to match V2 — end

### Future-designed (not P0 delivery)

- `F.1` HealthKit sleep/weight/steps read path  
- `F.2` Sleep preparation notifications  
- `F.3` Office geofence restaurant coaching  
- `F.4` Tai-generated workout programs  
- `F.5` HRV-informed recovery claims (only if validated)  

### Recommended implementation sequence

1. P0.1 → P0.2 (product feels like a coach)  
2. P0.3 (meal loop excellence)  
3. P0.4 (conversation becomes real)  
4. P0.5 → P0.6 (workout loop)  
5. P0.7 (unified recommendations)  
6. P0.8 → P0.9 (trust & control)  
7. P0.10 (ship)  

---

## 16. Acceptance criteria for the P0 product

Observable proofs:

1. **Feels like a coach:** On cold open, a new tester can state Tai’s next-action advice without interpreting a calorie ring first.
2. **Fast common meals:** Reusing a remembered weekday lunch takes ≤30 seconds from Tai meal entry to saved.
3. **Remembers corrections:** After correcting “oat latte” calories once, the next suggestion reflects the correction or surfaces the memory explicitly.
4. **Workout import usable:** At least one real pasted plan and one screenshot plan can be confirmed into a structured session a user can run the same day.
5. **Logging beats Notes:** Timed task — logging a 4-exercise session with prior loads is faster than the user’s current Notes flow (qualitative + timed).
6. **Explainable recommendations:** Every primary Home recommendation has a Why sheet with evidence the user recognises.
7. **Human control:** No plan weight, goal or meal changes without an explicit confirm path; testers cannot find a silent mutation.
8. **Missing Health doesn’t break:** With Health disconnected, Home remains useful and never asks for manual sleep/weight entry.
9. **Proactive control:** Notifications are off until opted in; enabling one category cannot exceed its frequency cap in test harnesses.
10. **Unified briefing:** After a workout + meal day, Home references both domains in one briefing.

---

## 17. Migration strategy

### 17.1 Principles

- Incremental; feature-flagged.
- Preserve meal logs and goal targets.
- Do not rewrite the meal Check In AI loop (retain inside Tai).
- Avoid big-bang navigation + workout + chat in one release if possible; **Home + Tai shell** can ship before workout.

### 17.2 Navigation migration

1. Flag `nav_v2`: rename Dashboard→Home; replace Goals / Check In tabs with **Tai** as the Conversation workspace (Goals and meal flows embedded in Tai).
2. Home next actions deep-link into Tai with intent (meal, workout, goal); preserve meal muscle memory.
3. Remove Ask Tai FAB dependency once the Tai tab is the Conversation (FAB may remain temporarily as a deep link).

### 17.3 Model migrations

- Keep `MealLog`, `MealItem`, `GoalProfile`, `DailyTargets`.
- Add workout + recommendation + memory entities via SwiftData migration plan / versioned schema.
- Stop writing `WeightLog` from any UI; optional later migration of any seed rows to `HealthSignal` or delete.
- Wire `FineTuneCorrection` into meal confirmation path or replace with `MemoryCorrection`.
- Grow `RecurringMeal` into MealMemory or map into new table with dual-read period.

### 17.4 Screen replacement order

1. Shell + Home briefing (keep meal cards)  
2. Tai shell + relocate Goals into Conversation  
3. Meal memory  
4. Live Tai Conversation  
5. Workout import → session → progression  
6. Notifications + memory UI polish  

### 17.5 Feature flags

Suggested: `nav_v2`, `home_briefing`, `tai_tab`, `meal_memory`, `ask_tai_live`, `workout_import`, `workout_session`, `local_notifications`.

### 17.6 Data compatibility

- Read old goals as ActivePhase “general” if phase missing.
- Briefing falls back to current `DashboardState` heuristics if recommendation engine unavailable.

### 17.7 Rollback

- Flags off restores prior tab labels and Dashboard hero.
- Do not ship irreversible destructive schema without backup/export path.

### 17.8 Preview and test strategy

- SwiftUI previews for Home briefing states: empty, meal-only, workout-due, signals unavailable, conflict safety.
- Proxy contract tests for new endpoints (extend Vitest).
- Introduce iOS unit tests for ranking and import fixtures (P0.10.2).

### 17.9 What can ship incrementally vs together

| Can ship alone | Must ship together |
|----------------|--------------------|
| Home briefing + nav rename | Workout import + review confirm |
| Goals under Tai | Progression suggestion + accept/audit |
| Meal memory v1 | Live Tai Conversation + consent update |
| Notification prefs UI (no sends) | First notification category + deep link target |

---

## 18. Risks and unresolved decisions

| Risk | Type | Mitigation |
|------|------|------------|
| Briefing feels vague vs calorie ring’s clarity | UX | Keep compact numbers; test comprehension |
| Workout OCR/import accuracy too low | AI | Mandatory review; confidence flags; allow manual fix; success metric on “confirmable” not “perfect” |
| Scope creep into Health/location | Scope | Hard gate in backlog; F.* labels |
| Safety incidents from overload advice | Safety | Pain flag; precedence rules; confirm progression; conservative defaults |
| Disordered eating reinforcement via protein nudges | Safety | Soft copy; caps; no streak punishment |
| Privacy backlash on photos/chat | Privacy | Consent expansion; retention limits; Memory UI |
| SwiftData migration bugs | Technical | Versioned migrations; flag rollback; TestFlight on real stores |
| DashboardView / AppShell merge conflicts | Technical | Split briefing into feature module early; ownership rules |
| Tai Conversation live without grounding | AI/UX | Evidence-constrained prompts; show sources |
| Users expect Tai to write programs in P0 | Product | Onboarding honesty: import-first |
| Alcohol features distract coaching IA | Product | Keep out of Home; validate later need |
| Fake precision in machine weights | AI/Safety | Ambiguity notes; avoid kg pretence |

### Assumptions requiring user testing

- Import-first is acceptable vs blank program builder.
- One next action beats multi-tile dashboards for retention.
- Optional photo assist is discovered without training.
- Weekly summary notification is welcome rather than annoying.

### Do not manufacture certainty

Workout photo interpret quality, restaurant recommendations without menus, and HRV coaching value remain **unproven**. Treat as experiments with kill criteria.

---

## 19. First implementation slice

### Recommendation: “Home + Tai” vertical slice

**Name:** Slice 0 — Briefing Home + navigation pivot + Tai Conversation shell  

This slice delivers visible coaching identity, reuses meal/goal capabilities, avoids workout complexity, and establishes Recommendation / Evidence patterns later slices reuse.

### Included

- Feature flags `nav_v2` + `home_briefing` (+ `tai_tab` as needed)
- Tabs: **Home | Tai**
- Tai is the Conversation workspace: meal check-in (live) available from Conversation intents; Workout intent **disabled with “Coming soon”** or hidden behind `workout_import` flag off; Ask Tai preview may remain inside Tai until live Conversation ships
- Home: greeting, primary Recommendation (rule-based from meals + goals), Why sheet, compact nutrition strip, today’s meals, unavailable sleep/weight note
- Tai: Conversation surface + embedded existing Goals flow + entries (placeholders) for Plan, Memory, Notifications, Settings
- Shared `Recommendation` + `Evidence` + `SignalAvailability` types
- Consent unchanged except copy prep if touching Conversation entry points

### Excluded

- Workout import/session
- Live Tai Conversation backend (keep preview badge if still mock)
- Push notifications
- HealthKit
- Location
- Meal Memory v1 (can follow immediately after)
- Deleting MealCapture (schedule in P0.10 unless it confuses agents)

### Screens affected

- `AppShellView` (shared hotspot)
- New `HomeBriefingView` (extract from/replace `DashboardView` hero)
- New Tai Conversation container (hosts meal entry, Goals, placeholders)
- Optional Why Recommendation sheet

### Models affected

- New lightweight coaching value types (may be non-SwiftData first)
- No breaking change to `MealLog` / `GoalProfile` required

### Services affected

- Optional `BriefingService` / recommendation ranker (local)
- Repos: meal + goal read paths only

### Acceptance criteria for this slice

1. User opens app and sees a coaching briefing, not a giant ring as the primary identity.
2. Goals reachable from Tai; not a third root tab labelled Goals.
3. Meal check-in path remains fully functional from Tai.
4. Sleep/weight show unavailable without manual logging affordances.
5. Why sheet shows Evidence from real meal/goal data.
6. Flag off restores previous navigation.

### Suggested implementation agent roles

| Agent | Owns |
|-------|------|
| Navigation / Shell | `AppShellView`, Tai tab, flags |
| Home Briefing | New Home feature module, recommendation ranker UI |
| Tai Shell | Tai Conversation container, relocate Goals |
| Design QA | Visual hierarchy, coral usage, empty/unavailable states |
| Do not touch in this slice | Meal Check In interpret internals, proxy contracts, workout |

---

## Document control

- **Authority:** Constitutional layer in `Docs/` (`Docs/README.md`). Locked decisions in `Docs/PRODUCT_DECISIONS.md` remain locked.
- **Next step after approval:** Execute First implementation slice (§19), then P0.3 meal Memory.
- **Non-goals of this document:** Production code, dependency adds, SwiftUI redesigns in isolation.
- **IA note:** Target navigation is **Home | Tai** only. Section 3 current-state assessment may still describe legacy Dashboard / Check In / Goals tabs as they exist in code today.

---

*End of TAI_PRODUCT_V2_P0_BLUEPRINT.md*
