# Live Tai implementation plan (deferred)

Operational plan for the next product slice after attachment externalisation.
Not constitutional — obey `Docs/README.md` reading order and constitutional docs when implementing.

**Status:** Deferred until attachment-externalisation + off-main snapshot-codec slice is committed and re-inspected.  
**Endpoint:** `POST /ai/coach`  
**Do not implement until this document is refreshed against post-attachment APIs.**

---

## Locked product behaviour (unchanged)

- Navigation remains `Home | Tai`.
- One active Conversation.
- Confirmed Artifacts remain source of truth.
- AI suggests; user decides.
- Live Tai must not claim sleep, weight, location, workouts, or HealthKit when unavailable.
- Out of scope: Archive, Long-Term Memory, Meal Memory, workout, HealthKit, notifications, voice, multi-conversation, provider credentials in app, direct Artifact mutation from AI.

---

## Mandatory plan amendments (2026-07-11)

### 1. Targeted meal refinement only

A pending meal card must **not** automatically capture all composer text.

- Meal refinement runs only when Conversation is in an **explicit targeted refinement state** for one `draftID`.
- That state is entered only after the user taps **Change something** on a specific meal card.
- Outside that targeted state, ordinary text routes to **Live Tai** — even if interactive unlogged meal cards are still on screen.
- Photos / Take Photo / Describe Meal still start or continue meal capture as capability intents (not free-text hijacking).

Router sketch:

| State | Route |
|-------|--------|
| Targeted meal refinement (`draftID` set after Change something) | Meal refine for that draft |
| Photo present / meal collect intents | Meal |
| Otherwise (including idle with leftover cards awaiting Log) | Live Tai |

### 2. Consent versioning

Inspect existing AI consent wording before shipping Live Tai.

Current consent copy covers check-in text/photo and goal strategy only. Live general coaching **materially expands** processing scope.

Therefore:

- Version the consent record (do not silently reuse v1 acceptance for Live Tai).
- Request acceptance before the **first** Live Tai network request.
- Reuse the same sheet UX pattern; do not invent a parallel legal flow.
- Decline blocks the network call.

### 3. Context assembly Sendable snapshot

`LiveTaiContextAssembler` must consume a **lightweight immutable `Sendable` snapshot**.

- Do not hop SwiftData models or live `@Observable` state across actors.
- Build the snapshot on MainActor (or from repository value types), then assemble off-main.
- Snapshot includes confirmed meals/goals progress, bounded recent turns (text only), capability flags, known limitations — not JPEG bytes.

### 4. Endpoint

Use **`POST /ai/coach`** only (document in `Docs/ai-proxy-live-tai-contract.md` when implementing).

### 5. Identifiers

Omit `ownerID` from the proxy request unless a demonstrated backend requirement appears.  
If an identifier is required, use an **opaque** client/session id — never a human-readable owner string by default.

### 6. Response presentation

Default to **conversational assistant text** with:

- attached Evidence metadata
- a Why disclosure surface

Use structured visible cards **selectively** (e.g. safety refusal, strong recommendation requiring User Decision) — not for every response.

---

## Proposed live request flow

```text
Composer send (text, no photo)
  → consent gate (versioned for Live Tai)
  → ConversationRouter (targeted meal refinement vs Live Tai)
       ├─ targeted meal draftID → MealCapability.interpret / refine
       └─ otherwise → LiveTaiCapability
            → build Sendable context snapshot
            → assemble Context Prompt off MainActor
            → POST /ai/coach
            → validate typed LiveTaiResponse
            → append assistant text (+ optional Why / selective card)
            → single coalesced persist
            → activity → awaitingUser
```

No streaming in v1. Duplicate send while processing is ignored.

---

## Response contract (typed)

- `assistantText`
- optional `recommendation` (advisory)
- `evidence[]`
- `confidence` / data sufficiency
- `limitations[]`
- optional `quickActions`
- `requiresUserDecision`
- `safety` state

Must not create/mutate meals, goals, programs, reminders, preferences, Memory.

---

## Evidence

Grounded Why surface from confirmed context. No prompts / chain-of-thought.

---

## Safety

Worker rules + typed `safety` on response + honest missing-data limitations. Test diagnosis, urgent symptoms, unsafe restriction, disordered-eating, pain/injury, missing-data uncertainty.

---

## Failure recovery

Retain user message; append failure; Retry without duplicating user turn; heal interrupted `processing(live_tai)` on restore.

---

## Performance (post-attachment baseline)

Preserve:

- composer draft isolation + composer-only saves
- externalised attachments (no JPEG in `messagesJSON`)
- off-main encode/decode / coalesced persist coordinator
- lazy Tai mount + image cache
- bounded context; no images on `/ai/coach`
- no sensitive production logs

---

## Pre-implementation checklist

1. Re-inspect attachment store + persist coordinator APIs after that slice lands.
2. Update this plan with exact types/paths.
3. Then implement Live Tai (not before).
