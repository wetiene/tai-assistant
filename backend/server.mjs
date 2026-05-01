/**
 * Minimal Tai AI proxy stub — no OpenAI.
 * Run from repo root: node backend/server.mjs
 * Binds 0.0.0.0:8080. iOS Simulator: http://127.0.0.1:8080
 */
import http from "node:http";

const PORT = 8080;
const OPENAI_API_URL = "https://api.openai.com/v1/responses";
const OPENAI_MODEL = process.env.OPENAI_MODEL ?? "gpt-5.1";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

/** ISO8601 UTC without fractional seconds (matches default Swift `ISO8601DateFormatter` parsing). */
function iso8601Basic(d = new Date()) {
  return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}

const RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["interpretedMeals", "uiNotes"],
  properties: {
    interpretedMeals: {
      type: "array",
      minItems: 1,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "label",
          "timing",
          "eatenAtGuessISO8601",
          "items",
          "calories",
          "proteinGrams",
          "carbsGrams",
          "fatGrams",
          "confidence",
          "alternatives",
        ],
        properties: {
          label: { type: "string" },
          timing: { type: "string" },
          eatenAtGuessISO8601: { type: "string" },
          items: {
            type: "array",
            minItems: 1,
            items: {
              type: "object",
              additionalProperties: false,
              required: [
                "name",
                "amount",
                "unit",
                "calories",
                "proteinGrams",
                "carbsGrams",
                "fatGrams",
                "fiberGrams",
              ],
              properties: {
                name: { type: "string" },
                amount: { type: "number" },
                unit: { type: "string" },
                calories: { type: "integer" },
                proteinGrams: { type: "number" },
                carbsGrams: { type: "number" },
                fatGrams: { type: "number" },
                fiberGrams: { type: "number" },
              },
            },
          },
          calories: { type: "integer" },
          proteinGrams: { type: "number" },
          carbsGrams: { type: "number" },
          fatGrams: { type: "number" },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          alternatives: {
            type: "array",
            description: "Alternative meal labels when visually ambiguous; empty when confident.",
            items: { type: "string" },
          },
        },
      },
    },
    uiNotes: { type: ["string", "null"] },
  },
};

function maybeLogDev(label, value) {
  if (process.env.NODE_ENV !== "production") {
    console.log(`${label}:`, value);
  }
}

function extractResponseText(payload) {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text;
  }
  const outputs = Array.isArray(payload?.output) ? payload.output : [];
  for (const out of outputs) {
    const contents = Array.isArray(out?.content) ? out.content : [];
    for (const content of contents) {
      if (content?.type === "output_text" && typeof content.text === "string" && content.text.trim()) {
        return content.text;
      }
    }
  }
  return "";
}

function parseRequestBody(raw) {
  const parsed = JSON.parse(raw.toString("utf8"));
  return {
    text: typeof parsed?.text === "string" ? parsed.text : "",
    image: parsed?.image && typeof parsed.image === "object" ? parsed.image : null,
    context: parsed?.context && typeof parsed.context === "object" ? parsed.context : null,
  };
}

function buildOpenAIInput({ text, image, context }) {
  const userContent = [];
  const trimmedText = text.trim();
  if (trimmedText) {
    userContent.push({ type: "input_text", text: `Meal input: ${trimmedText}` });
  }

  if (image?.base64Data && image?.mimeType) {
    const dataUrl = `data:${image.mimeType};base64,${image.base64Data}`;
    userContent.push({
      type: "input_image",
      image_url: dataUrl,
    });
  }

  if (context && Object.keys(context).length > 0) {
    userContent.push({
      type: "input_text",
      text: `Context: ${JSON.stringify(context)}`,
    });
  }

  if (userContent.length === 0) {
    userContent.push({ type: "input_text", text: "No meal details provided." });
  }

  return [
    {
      role: "system",
      content: [
        {
          type: "input_text",
          text:
            "You are Tai meal interpreter. Return only valid JSON matching the provided schema. " +
            "Do not include markdown or explanatory prose. " +
            "Use timing from: breakfast, lunch, dinner, snack, other. " +
            "Estimate nutritional values if uncertain and set confidence accordingly.",
        },
      ],
    },
    {
      role: "user",
      content: userContent,
    },
  ];
}

async function interpretMealWithOpenAI(requestPayload) {
  if (!OPENAI_API_KEY) {
    throw new Error("OPENAI_API_KEY is not set");
  }

  const openAIRequest = {
    model: OPENAI_MODEL,
    input: buildOpenAIInput(requestPayload),
    text: {
      format: {
        type: "json_schema",
        name: "tai_meal_interpretation",
        strict: true,
        schema: RESPONSE_SCHEMA,
      },
    },
  };

  maybeLogDev("[openai] request model", OPENAI_MODEL);
  const openAIResponse = await fetch(OPENAI_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify(openAIRequest),
  });

  const rawResponseText = await openAIResponse.text();
  maybeLogDev("[openai] status", openAIResponse.status);
  maybeLogDev("[openai] raw", rawResponseText);

  if (!openAIResponse.ok) {
    throw new Error(`OpenAI request failed with status ${openAIResponse.status}`);
  }

  let responseJson;
  try {
    responseJson = JSON.parse(rawResponseText);
  } catch {
    throw new Error("OpenAI returned non-JSON payload");
  }

  const structuredText = extractResponseText(responseJson);
  if (!structuredText) {
    throw new Error("OpenAI returned empty structured output");
  }

  try {
    return JSON.parse(structuredText);
  } catch {
    throw new Error("OpenAI returned invalid structured JSON");
  }
}

function logLine(parts) {
  console.log(`[interpret-meal] ${new Date().toISOString()}`, ...parts);
}

function extractTopLevelKeys(raw) {
  try {
    const parsed = JSON.parse(raw.toString("utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return [];
    }
    return Object.keys(parsed);
  } catch {
    return [];
  }
}

const server = http.createServer((req, res) => {
  const url = req.url ?? "";

  if (req.method === "POST" && url === "/ai/interpret-meal") {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", async () => {
      const raw = Buffer.concat(chunks);
      const len = raw.length;
      const topLevelKeys = extractTopLevelKeys(raw);
      logLine([
        `method=${req.method}`,
        `url=${url}`,
        `bytes=${len}`,
        `content-type=${req.headers["content-type"] ?? "(none)"}`,
        `topLevelKeys=${topLevelKeys.join(",") || "(unparsed)"}`,
      ]);
      try {
        const parsed = parseRequestBody(raw);
        const interpreted = await interpretMealWithOpenAI(parsed);
        res.writeHead(200, {
          "Content-Type": "application/json; charset=utf-8",
        });
        res.end(JSON.stringify(interpreted));
      } catch (error) {
        logLine(["openai_error", String(error)]);
        res.writeHead(500, {
          "Content-Type": "application/json; charset=utf-8",
        });
        res.end(
          JSON.stringify({
            error: "Meal interpretation failed.",
          })
        );
      }
    });
    req.on("error", (err) => {
      logLine(["request_error", String(err)]);
      res.writeHead(400);
      res.end();
    });
    return;
  }

  if (req.method === "GET" && url === "/health") {
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("ok\n");
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("not found\n");
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Tai AI proxy stub listening on http://127.0.0.1:${PORT}`);
  console.log(`POST http://127.0.0.1:${PORT}/ai/interpret-meal`);
});
