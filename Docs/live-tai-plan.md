# Live Tai implementation plan

Operational plan for Live Tai inside the one active Conversation.  
Not constitutional — obey `Docs/README.md` reading order and constitutional docs.

**Status:** Implemented (post attachment-externalisation baseline `0a01a8c`).  
**Endpoint:** `POST /ai/coach`  
**Contract:** [`Docs/ai-proxy-live-tai-contract.md`](ai-proxy-live-tai-contract.md)

---

## Locked product behaviour

- Navigation remains `Home | Tai`.
- One active Conversation.
- Confirmed Artifacts remain source of truth.
- AI suggests; user decides.
- Live Tai must not claim sleep, weight, location, workouts, or HealthKit when unavailable.
- Out of scope: Archive, Long-Term Memory, Meal Memory, workout, HealthKit, notifications, voice, multi-conversation, provider credentials in app, direct Artifact mutation from AI.

---

## Implemented behaviour (2026-07-11)

### 1. Targeted meal refinement only

- Meal refinement runs only when Conversation activity carries an **explicit** `targetedDraftID` in the meal capability payload (persisted in `activityJSON`).
- Entered only after **Change something** on a specific meal card.
- Cleared on: successful refinement, Cancel change, Log Meal for that draft, Looks right for that draft, or new meal capture (Take Photo / Describe Meal / start meal intent).
- Photos / Take Photo / Describe Meal (collecting phase) still start meal capture.
- **Natural-language meal log statements** (e.g. “Had half a pizza…”) route to Meal via `ConversationMealIntentClassifier` — users do not need to tap Describe Meal first.
- Food **questions** (“Can I have pizza tonight?”) route to Live Tai.
- Short ambiguous food fragments (“Pizza”) ask whether to log or ask about it.
- Pending meal cards alone never hijack general questions.

### 2. Consent versioning

| Version | Scope |
|---------|--------|
| 1 | Meal check-in text/photo + goal strategy |
| 2 | Live Tai coaching (question + bounded confirmed meals/goals + recent text; **no** meal photos on `/ai/coach`) |

- Legacy boolean consent migrates to version **1**.
- Version **2** is required once before the first Live Tai request.
- Declining v2 does **not** disable v1 meal/goal interpretation.

### 3. Context assembly

- Capture immutable `LiveTaiContextSnapshot` (`Sendable`) at the repository boundary (value types only).
- Assemble via `LiveTaiContextAssembler` **actor** (Swift concurrency, off MainActor).
- Do not hop SwiftData models, repositories, or `@Observable` state across actors.
- Known limitations always included in the **request**; shown in UI only when `response.limitations` is non-empty (material to the answer).

### 4. Identifiers

Omit `ownerID` from `/ai/coach` requests.

### 5. Response presentation

- Default: conversational assistant text + optional Why/Evidence disclosure.
- No visible structured coaching card for ordinary text responses.
- `requiresUserDecision` is advisory only — never mutates Artifacts.
- Proxy quick actions map through a typed allowlist; unknown ids never trigger navigation/persistence/capabilities.

### 6. Allowlisted quick actions

`meal.takePhoto` · `meal.describeMeal` · `meal.askTai` · `meal.cancelRefine` · `meal.logIt` · `liveTai.askAboutIt` · `liveTai.retry` · `liveTai.why`

### 7. Live Tai prose hygiene

- `assistantText` is clean conversational prose only (Worker prompt + sanitize + app renderer).
- Bracketed evidence tags and capability jargon are forbidden in user-visible text.
- Evidence / material limitations appear in the Why sheet only.

---

## Live request flow

```text
Composer send
  ↓
Conversation router
  ├─ targeted meal refinement draftID → Meal capability
  ├─ photo / meal collecting intent → Meal capability
  ├─ high-confidence NL meal statement → Meal capability
  ├─ ambiguous food fragment → clarify (Log meal / Ask about it)
  └─ otherwise → Live Tai
```

No streaming. Duplicate send while `processing(live_tai)` is ignored.

---

## Failure recovery

Retain user message; append failure; Retry without duplicating user turn; heal interrupted `processing(live_tai)` on restore.

---

## Performance

Preserves attachment externalisation + off-main coalesced persist from `0a01a8c`:

- composer draft isolation + composer-only saves
- externalised attachments (no JPEG in `messagesJSON`)
- coalesced persist coordinator
- bounded context; no images on `/ai/coach`
- no sensitive production logs
