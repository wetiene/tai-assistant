# AI proxy — Live Tai coaching contract

Operational contract for `POST /ai/coach`. Obeys `Docs/README.md` constitutional layer.

Related: `Docs/live-tai-plan.md`, `Docs/ai-proxy-meal-interpretation-contract.md`.

---

## Endpoint

```http
POST /ai/coach
Authorization: Bearer <TAI_PROXY_TOKEN>
Content-Type: application/json
```

iOS path config: `RuntimeAppConfig.aiCoachPath` → `/ai/coach`.

---

## Request

```json
{
  "message": "How much protein do I have left?",
  "context": {
    "localeIdentifier": "en_AU",
    "timeZoneIdentifier": "Australia/Sydney",
    "dayNutrition": {
      "mealCount": 2,
      "calories": 1200,
      "proteinGrams": 90,
      "carbsGrams": 110,
      "fatGrams": 40,
      "calorieTarget": 2200,
      "proteinTarget": 160,
      "carbsTarget": 200,
      "fatTarget": 70
    },
    "mealsToday": [
      {
        "label": "Lunch bowl",
        "eatenAtISO8601": "2026-07-11T01:00:00Z",
        "calories": 620,
        "proteinGrams": 45,
        "carbsGrams": 55,
        "fatGrams": 20
      }
    ],
    "goal": {
      "title": "Recomp",
      "calorieTarget": 2200,
      "proteinTarget": 160,
      "carbsTarget": 200,
      "fatTarget": 70
    },
    "recentTurns": [
      { "role": "user", "text": "I logged lunch" },
      { "role": "assistant", "text": "Nice work." }
    ],
    "limitations": [
      "Apple Health / HealthKit is not connected",
      "Sleep data is unavailable",
      "Weight data is unavailable",
      "Workout tracking is not available yet",
      "Location context is not available",
      "Meal Memory is not available yet"
    ],
    "capabilityFlags": {
      "hasHealthKit": false,
      "hasWorkouts": false,
      "hasLocation": false,
      "hasMealMemory": false
    }
  }
}
```

### Rules

- **No `ownerID`** on this route (omit unless a demonstrated backend requirement appears).
- **No meal photos / JPEG / image fields.**
- Context is a bounded snapshot of confirmed Artifacts + recent text turns.
- `limitations` are always sent; the client shows them to the user only when the response marks them as material (`response.limitations`).

---

## Response

```json
{
  "assistantText": "You have about 70g of protein left toward today’s target.",
  "recommendation": {
    "title": "Prioritise protein at dinner",
    "detail": "Eggs, fish, or Greek yogurt would help close the gap."
  },
  "evidence": [
    {
      "kind": "day_progress",
      "label": "Today’s protein progress",
      "detail": "About 70g remaining vs target"
    }
  ],
  "confidence": "medium",
  "limitations": [],
  "quickActions": [
    { "id": "liveTai.why", "title": "Why?" }
  ],
  "requiresUserDecision": false,
  "safety": {
    "state": "ok",
    "reason": null
  }
}
```

### Semantics

| Field | Meaning |
|-------|---------|
| `assistantText` | Primary conversational reply (always present) |
| `recommendation` | Optional advisory suggestion — never auto-applied |
| `evidence` | Citations grounded in confirmed context |
| `confidence` | `high` / `medium` / `low` (string) |
| `limitations` | Only limitations **material to this answer** |
| `quickActions` | Suggestions; client maps through a typed allowlist |
| `requiresUserDecision` | Advisory signal only — **must not** mutate Artifacts |
| `safety.state` | `ok` \| `refuse` \| `redirect` |

### Quick-action allowlist (iOS)

Unknown ids are ignored for behaviour (may be shown as non-interactive suggestion text):

- `meal.takePhoto`
- `meal.describeMeal`
- `meal.askTai`
- `meal.cancelRefine`
- `meal.logIt`
- `liveTai.askAboutIt`
- `liveTai.retry`
- `liveTai.why`

### assistantText hygiene

`assistantText` must be clean user-facing prose. Forbidden in `assistantText`:

- Bracketed annotations such as `[Confirmed today’s totals]`
- Capability jargon: Meal Memory / Location / HealthKit unavailable
- Lectures about not updating saved data

Evidence belongs in `evidence[]`. Material gaps only in `limitations[]`. The Worker sanitizes mapped output; the iOS renderer also sanitizes before display.

### Safety

Worker system rules refuse diagnosis, urgent symptoms, unsafe restriction, disordered-eating encouragement, and injury-pushing advice. Typed `safety` on the response; client validates.

### Non-goals

- Streaming
- Artifact mutation payloads
- Archive / Human Summary / Meal Memory
- HealthKit / workouts / location / notifications / voice

---

## iOS wiring

- `AIService.coach(request:)` → `OpenAIProxyAIService` / `MockAIService`
- Snapshot: `LiveTaiContextSnapshot` (Sendable) captured at repository boundary
- Assembly: `LiveTaiContextAssembler` actor (off MainActor)
- Presentation: conversational text + optional Why/Evidence disclosure; no ordinary structured coaching cards
