# Tai Product Decisions

Living decision log for Tai. Entries are chronological. Newer decisions may supersede earlier ones; when that happens, note it in the Reason or Future review of the new entry.

Related: `Docs/README.md`, `Docs/TAI_MANIFESTO.md`, `Docs/PRODUCT_PRINCIPLES.md`, `Docs/AI_ARCHITECTURE.md`.

Canonical terms: Conversation, Artifact, Memory, Archive, Human Summary, AI Context Prompt, Context Prompt, Recommendation, Evidence, Confidence, User Decision, Trusted Integrations, Confirmed Artifacts.

For each decision:

- **Date** — when the decision was locked
- **Decision** — what we chose
- **Reason** — why
- **Future review** — optional trigger to revisit

---

## 2026-07-11

### Tai is becoming an AI health and performance coach

- **Date:** 2026-07-11
- **Decision:** Tai’s product identity is a personalised AI health and performance coach — not a collection of trackers or dashboards.
- **Reason:** Tracking alone does not reduce decision friction. Users need timely, practical guidance before decisions matter. Nutrition, training, recovery and health signals exist to support coaching, not as ends in themselves.
- **Future review:** After P0 ships, validate with TestFlight that users describe Tai as a coach rather than a tracker.

### Nutrition is the first capability

- **Date:** 2026-07-11
- **Decision:** Nutrition (meal check-in, interpretation, confirmation, Memory) is the first coaching capability.
- **Reason:** Meal logging is already the most complete production loop in the app and is the highest-frequency daily input. It proves the “AI suggests, humans decide” pattern before expanding domains.
- **Future review:** Revisit priority only if workout demand clearly outpaces nutrition usage in early cohorts.

### Workout coaching is the second capability

- **Date:** 2026-07-11
- **Decision:** Workout coaching (import, session guidance, set logging, progression suggestions) is the second capability after nutrition.
- **Reason:** Training is the other half of the health-and-performance loop. Completing nutrition + workout in P0 proves a unified coaching product rather than a meal tracker with a bolted-on gym feature.
- **Future review:** After import-first workouts ship, assess whether generated programs should move earlier than planned.

### Conversation-first UX replaces screen-first UX

- **Date:** 2026-07-11
- **Decision:** Users interact with Tai primarily through Conversation (plus cards, attachments and quick actions), not by hunting across many purpose-built screens.
- **Reason:** Screen-first navigation forces users to interpret numbers and find the right form. Conversation-first matches a coaching relationship and keeps navigation minimal as capabilities grow.
- **Future review:** If Conversation friction rises for common tasks, introduce dedicated flows only where they clearly beat chat.

### Two tabs only: Home and Tai

- **Date:** 2026-07-11
- **Decision:** Primary navigation has exactly two tabs — **Home** and **Tai**. Goals, workouts, check-in and settings are not permanent top-level tabs.
- **Reason:** Extra tabs recreate tracker IA and pull goals/workouts into silos. New capabilities must justify belonging on Home or inside Tai before earning another destination.
- **Future review:** If a third destination becomes unavoidable, record a superseding decision with explicit criteria.

### Home is a briefing

- **Date:** 2026-07-11
- **Decision:** Home is a personalised daily briefing: what matters now, what Tai has noticed, and one clear next action — not a Conversation transcript and not a calorie-ring dashboard hero.
- **Reason:** Home should speak first and reduce decision friction. A full transcript or dense tracker UI competes with coaching and makes the next step unclear.
- **Future review:** Qualitative check that users accept briefing-first Home without a dominant calorie ring.

### Tai is the conversation

- **Date:** 2026-07-11
- **Decision:** The Tai tab is the ongoing Conversation relationship surface — goals, plans, questions, Memory and coaching dialogue live here.
- **Reason:** Separating briefing (Home) from dialogue (Tai) keeps each surface focused: Home answers “what now?”; Tai answers “talk with me / manage my plan.”
- **Future review:** None required unless Home and Tai content start to duplicate.

### One active conversation

- **Date:** 2026-07-11
- **Decision:** There is one active Conversation at a time.
- **Reason:** Multiple parallel threads fragment context and undermine “Tai knows me.” A single active thread keeps coaching coherent and simplifies Memory and UI.
- **Future review:** Revisit only if users need concurrent threads for clearly distinct life contexts (e.g. travel vs home).

### Users may archive conversations

- **Date:** 2026-07-11
- **Decision:** Users can archive the active Conversation and start fresh.
- **Reason:** Long threads become noisy. Archiving gives control without deleting history that still informs future coaching.
- **Future review:** Measure how often users archive and whether they expect restore vs start-new behaviour.

### Archived conversations produce an Archive package

- **Date:** 2026-07-11
- **Decision:** Archiving produces a conceptual Archive package consisting of: (1) Raw Archive, (2) Human Summary, (3) AI Context Prompt, and (4) Structured Artifacts. Structured Artifacts are generally already persisted before archiving; they are not generated by archiving. They are part of the Archive package because they represent the durable facts created during that Conversation.
- **Reason:** Raw Archive preserves Conversation history; Human Summary serves the user; AI Context Prompt keeps future turns efficient; Structured Artifacts remain the source of truth. No single representation serves all needs. See `Docs/AI_ARCHITECTURE.md`.
- **Future review:** After first Archive pipeline ships, audit prompt quality vs token cost and Artifact completeness.

### Conversation summaries become future context

- **Date:** 2026-07-11
- **Decision:** The Human Summary and archive-derived AI Context Prompt feed future coaching via Context Prompt assembly.
- **Reason:** Tai must feel continuous across sessions without replaying entire transcripts every turn.
- **Future review:** Validate that summaries stay correctable and do not silently overwrite Confirmed Artifacts.

### Structured artifacts remain the source of truth

- **Date:** 2026-07-11
- **Decision:** Meals, workouts, goals, plans and other confirmed records are structured Artifacts outside the Conversation. They are the source of truth.
- **Reason:** Conversation text is ambiguous and hard to query. Durable coaching and Home briefings require typed, confirmed domain records.
- **Future review:** None — foundational. Only revisit if a new domain cannot be modelled as Artifacts.

### Conversation is not the database

- **Date:** 2026-07-11
- **Decision:** Conversation history is interaction history and context, not the system of record for domain data.
- **Reason:** Treating Conversation as storage breaks correction, undo, reporting and future Health integrations. Artifacts must outlive any single thread.
- **Future review:** None — foundational.

### Goals are managed inside Tai

- **Date:** 2026-07-11
- **Decision:** Goals are created, reviewed and adjusted inside the Tai Conversation (and related coaching UI), not as a permanent top-level Goals tab.
- **Reason:** Goals are part of the coaching relationship. A separate Goals tab siloed macro editing and competed with Home/Tai for attention.
- **Future review:** If goal setup remains too heavy in Conversation alone, add a focused goal sheet launched from Tai — still not a third tab.

### Workout plans begin via copy/paste or photo import

- **Date:** 2026-07-11
- **Decision:** P0 workout onboarding starts by importing an existing plan (paste or photo), not by blank program builders or full AI-generated programs.
- **Reason:** Most target users already have a plan. Import proves coaching on real programs faster and avoids fake-precision generated routines before trust exists.
- **Future review:** After import-first validation, decide when Tai-generated programs enter scope.

### Workout programs are user-owned

- **Date:** 2026-07-11
- **Decision:** Imported and confirmed workout programs belong to the user. Tai coaches against them; it does not own or silently replace them.
- **Reason:** Trust requires that the user’s training plan remains theirs. Silent ownership by the AI would feel like loss of control.
- **Future review:** None required unless shared/coach-authored programs become a product need.

### AI suggests progression but never silently changes programs

- **Date:** 2026-07-11
- **Decision:** Tai may suggest load, volume or plan progression; it must never mutate programs, sets or preferences without explicit user confirmation.
- **Reason:** Aligns with “AI suggests. Humans decide.” Silent changes destroy trust and can create unsafe overload.
- **Future review:** None — safety and trust boundary.

### Sleep and weight come from Apple Health

- **Date:** 2026-07-11
- **Decision:** Sleep and weight (and other supported health metrics) are sourced from Apple Health when available and authorised — not from first-party manual trackers as the preferred path.
- **Reason:** Do not ask for information another Trusted Integration already knows. Apple Health is the preferred source for health metrics on iPhone.
- **Future review:** When HealthKit ships, confirm coverage gaps and whether any fallback UX is needed for users without Health data.

### No manual sleep logging

- **Date:** 2026-07-11
- **Decision:** Do not build a manual sleep logging workflow.
- **Reason:** Manual sleep entry duplicates Apple Health, adds friction and invites low-quality data. Prefer integration over duplicate entry.
- **Future review:** Only if a material user segment cannot use Apple Health and sleep is required for coaching quality.

### No manual weight logging

- **Date:** 2026-07-11
- **Decision:** Do not build a manual weight logging UI. Existing weight write paths must not grow product surface pending HealthKit-sourced signals.
- **Reason:** Same as sleep — prefer Apple Health; avoid tracker ceremony that conflicts with coach identity.
- **Future review:** Same as sleep — only for Health-unavailable segments if weight becomes coaching-critical.

### Meal Memory is a core product differentiator

- **Date:** 2026-07-11
- **Decision:** Meal Memory (confirmed, reusable meal knowledge and corrections that improve future interpretation) is a core differentiator, not a nice-to-have.
- **Reason:** Fast, accurate reuse of known meals is the highest-friction reducer after confirm. Memory makes Tai feel like it knows the user.
- **Future review:** After P0.3-class Meal Memory ships, measure reuse rate and correction rate vs one-off logging.

### Notifications are proactive but contextual

- **Date:** 2026-07-11
- **Decision:** Notifications may be proactive, but only when contextual, permissioned and high-value — not spam, streaks or background surveillance.
- **Reason:** Prefer proactive coaching over passive reporting, within quiet hours, category opt-in and frequency caps. Engagement tactics must not outrank safety or trust.
- **Future review:** After first notification categories ship, audit opt-out rates and perceived usefulness.

### Location recommendations are future work

- **Date:** 2026-07-11
- **Decision:** Continuous location and office/restaurant-style Recommendations are out of P0 and deferred.
- **Reason:** High privacy sensitivity and not required to prove the core coaching loop (nutrition + workout + briefing + Conversation).
- **Future review:** Reopen only with explicit privacy design, consent model and a clear coaching use case.

### HealthKit is future work

- **Date:** 2026-07-11
- **Decision:** Apple Health / HealthKit read integration is designed for now but implemented later. Architecture should stay ready without pretending the integration already exists.
- **Reason:** P0 must prove the coaching loop without blocking on Health permissions. Home should stay honest about unavailable signals until HealthKit lands.
- **Future review:** Schedule HealthKit after nutrition + workout loop is stable and consent categories are extended.

### Conversation-first architecture

- **Date:** 2026-07-11
- **Decision:** Conversation-first architecture. Tai is organised around one active Conversation. Capabilities such as nutrition, workouts, goals, coaching and future health guidance exist inside that Conversation rather than as separate application screens.
- **Reason:** This creates one continuous relationship with the user, reduces navigation complexity and allows new capabilities to be added without expanding navigation.
- **Future review:** Only revisit if long-term user research demonstrates a genuine need for multiple concurrent conversations.


---

## 2026-07-22

### Meal artifact date semantics and nutrition-day bucketing

- **Date:** 2026-07-22
- **Decision:** Confirmed meals use `MealLog.eatenAt` as the authoritative occurrence timestamp. Nutrition-day membership, ordering, Home aggregation, and repository day queries are derived from `eatenAt` using device-local `Calendar.current` day bounds (`startOfDay` through next midnight, half-open). `MealLog.createdAt` is the immutable audit timestamp for when the meal was first confirmed and persisted. `MealLog.updatedAt` is the last user-driven modification timestamp. Do not add stored `effectiveDate`, `recordedAt`, or `consumedAt` fields, and do not rename existing SwiftData fields for this feature.
- **Reason:** Historical day navigation and backdated logging require one occurrence timestamp and clear audit fields without schema migration or duplicate day columns that can drift.
- **Future review:** Revisit only if timezone-aware bucketing or explicit user time-zone preferences ship beyond device-local `Calendar.current`.

### Selected nutrition day is ephemeral UI context

- **Date:** 2026-07-22
- **Decision:** The app-scoped selected nutrition day defaults to Today on launch, is not persisted in this slice, and cannot be set to a future calendar day. Tai launch intents may carry optional `NutritionDayContext` without creating per-day Conversations.
- **Reason:** Home historical browsing and Tai historical logging need shared, lightweight context while preserving one active Conversation.
- **Future review:** After historical logging ships, assess whether restoring the last selected day across launches improves usability.

---

## Future decisions
