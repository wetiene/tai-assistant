# Tai AI Proxy Contract (Meal Interpretation)

This app lane intentionally does **not** call OpenAI from iOS.
All OpenAI traffic must be server-side through a backend proxy.

## Runtime switching (mock vs live)

AI provider mode is selected in `RuntimeAppConfig`:

- `mealInterpretationProvider: .mock` -> uses `MockAIService`
- `mealInterpretationProvider: .openAIProxy` -> app calls backend proxy via `OpenAIProxyAIService`

Config fields:

- required for `.openAIProxy`:
  - `aiProxyBaseURL`
- optional:
  - `aiInterpretMealPath` (defaults to `/ai/interpret-meal` in app config)
  - `aiProxyBearerToken` (if your backend requires app->proxy bearer auth)

If `.openAIProxy` is selected without `aiProxyBaseURL`, app wiring falls back to `MockAIService` and triggers an assertion in debug builds.

## Endpoint

- Method: `POST`
- Path: `/ai/interpret-meal`
- Auth: backend-defined (bearer/session); no OpenAI key in app
- Content-Type: `application/json`

## App -> Backend request

```json
{
  "text": "had eggs and toast for breakfast",
  "image": {
    "base64Data": "....",
    "mimeType": "image/jpeg",
    "uploadReference": null
  },
  "context": {
    "ownerID": "preview.user",
    "localeIdentifier": "en_US",
    "timeZoneIdentifier": "America/Los_Angeles"
  }
}
```

Notes:
- `text` is optional.
- `image` is optional and supports either inline payload (`base64Data`) or an upload handle (`uploadReference`).
- At least one of `text` or `image` should be present.

## Backend -> App response (structured contract)

```json
{
  "interpretedMeals": [
    {
      "label": "Breakfast",
      "timing": "breakfast",
      "eatenAtGuessISO8601": "2026-04-15T14:12:00Z",
      "items": [
        {
          "name": "Eggs",
          "amount": 120,
          "unit": "g",
          "calories": 180,
          "proteinGrams": 15.0,
          "carbsGrams": 1.0,
          "fatGrams": 13.0,
          "fiberGrams": 0.0
        }
      ],
      "calories": 430,
      "proteinGrams": 33.0,
      "carbsGrams": 46.0,
      "fatGrams": 14.0,
      "confidence": 0.83
    }
  ],
  "uiNotes": "Estimated from text and image. Please confirm portions."
}
```

`interpretedMeals` is the primary contract. Free-form prose should not be used as the primary data payload.

## Suggested backend -> OpenAI Responses API shape

Use model tier optimized for cost and multimodal meal parsing, e.g. `gpt-5.4-nano`.

1. Build a strict JSON schema that matches the response contract above.
2. Call Responses API with:
   - text instructions
   - optional image input (`input_image` from uploaded file URL or data URL)
   - schema-constrained JSON output
3. Validate and sanitize model output before returning to app.

Pseudo request (server-side):

```json
{
  "model": "gpt-5.4-nano",
  "input": [
    {
      "role": "system",
      "content": [
        {
          "type": "input_text",
          "text": "You are Tai meal parser. Return only valid JSON per schema."
        }
      ]
    },
    {
      "role": "user",
      "content": [
        { "type": "input_text", "text": "<user text>" },
        { "type": "input_image", "image_url": "<image url or data url>" }
      ]
    }
  ],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "tai_meal_interpretation",
      "schema": "<structured schema matching interpretedMeals/uiNotes>"
    }
  }
}
```

Security:
- OpenAI API key stored only on backend secret manager.
- Do not embed key in iOS binary, plist, or source.

## Live mode checklist

Before live testing from app:

1. Set `mealInterpretationProvider` to `.openAIProxy`.
2. Set `aiProxyBaseURL` to your backend host.
3. Verify backend route `POST /ai/interpret-meal` accepts app JSON contract above.
4. If backend enforces auth, set `aiProxyBearerToken` and validate `Authorization: Bearer <token>`.
5. Confirm backend returns strict structured JSON (`interpretedMeals`) even on low-confidence outputs.

Image payload caveats:

- `base64Data` increases request size significantly; enforce backend max body size.
- For larger photos, prefer upload flow and pass `uploadReference` instead of inline base64.
- Ensure backend strips EXIF/PII and normalizes image format before forwarding to OpenAI.

## Local contract stub (no OpenAI)

Repo path: `backend/server.mjs` — fixed JSON response for end-to-end transport checks.

Run:

```bash
cd backend && npm start
# or: node server.mjs
```

- Listens on **`http://0.0.0.0:8080`** (reachable as **`http://127.0.0.1:8080`** from the iOS Simulator on the same Mac).
- **Physical device:** use your Mac’s LAN IP, e.g. `http://192.168.1.42:8080`, in `RuntimeAppConfig.aiProxyBaseURL` (same Wi‑Fi as the Mac).
- Debug builds set **`NSAllowsLocalNetworking`** so plain HTTP to local hosts is allowed. Release builds do not add that key; use HTTPS for production APIs.

Health check: `GET http://127.0.0.1:8080/health` → `ok`.
