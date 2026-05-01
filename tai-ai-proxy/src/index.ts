export interface Env {
	OPENAI_API_KEY: string;
	TAI_PROXY_TOKEN: string;
}

const MAX_BODY_BYTES = 4_500_000;

type TaiInterpretMealRequest = {
	text?: string;
	/** Legacy / alternate shape */
	imageBase64?: string;
	image?: { base64Data?: string; mimeType?: string | null };
	context?: Record<string, unknown>;
};

/** Matches iOS `AIInterpretMealResponse` / nested meal types (Codable keys). */
type TaiInterpretMealItem = {
	name: string;
	amount: number;
	unit: string;
	calories: number;
	proteinGrams: number;
	carbsGrams: number;
	fatGrams: number;
	fiberGrams: number;
};

type TaiInterpretedMeal = {
	label: string;
	timing: string;
	eatenAtGuessISO8601?: string | null;
	items: TaiInterpretMealItem[];
	calories: number;
	proteinGrams: number;
	carbsGrams: number;
	fatGrams: number;
	confidence: number;
};

type TaiInterpretMealResponse = {
	interpretedMeals: TaiInterpretedMeal[];
	uiNotes?: string | null;
	/** Optional aggregate signal; iOS decoder ignores unknown keys. */
	confidence?: number;
};

function json(data: unknown, status = 200): Response {
	return new Response(JSON.stringify(data), {
		status,
		headers: {
			"Content-Type": "application/json",
			"Access-Control-Allow-Origin": "*",
			"Access-Control-Allow-Methods": "POST, OPTIONS",
			"Access-Control-Allow-Headers": "Content-Type, Authorization",
		},
	});
}

function asRecord(x: unknown): Record<string, unknown> | null {
	if (typeof x === "object" && x !== null && !Array.isArray(x)) {
		return x as Record<string, unknown>;
	}
	return null;
}

/**
 * OpenAI Responses API: assistant text is under output[].content[].text
 * (often output[0].content[0] with type output_text).
 */
function extractOutputText(raw: unknown): string | undefined {
	const root = asRecord(raw);
	if (!root) return undefined;
	const output = root.output;
	if (!Array.isArray(output)) return undefined;
	for (const block of output) {
		const b = asRecord(block);
		if (!b) continue;
		const content = b.content;
		if (!Array.isArray(content)) continue;
		for (const part of content) {
			const p = asRecord(part);
			if (!p) continue;
			if (typeof p.text === "string" && p.text.length > 0) {
				return p.text;
			}
		}
	}
	return undefined;
}

function parseJsonFromModelText(text: string): unknown {
	const trimmed = text.trim();
	const unfenced = trimmed
		.replace(/^```(?:json)?\s*/i, "")
		.replace(/\s*```\s*$/i, "")
		.trim();
	return JSON.parse(unfenced);
}

function readFiniteNumber(v: unknown, fallback = 0): number {
	if (typeof v === "number" && Number.isFinite(v)) return v;
	if (typeof v === "string" && v.trim() !== "") {
		const n = Number(v);
		if (Number.isFinite(n)) return n;
	}
	return fallback;
}

function readInt(v: unknown, fallback = 0): number {
	const n = readFiniteNumber(v, NaN);
	if (!Number.isFinite(n)) return fallback;
	return Math.round(n);
}

function readString(v: unknown): string | undefined {
	if (typeof v === "string") return v;
	return undefined;
}

function pickMealsArray(parsed: Record<string, unknown>): unknown[] | null {
	if (Array.isArray(parsed.interpretedMeals)) return parsed.interpretedMeals;
	if (Array.isArray(parsed.interpreted_meals)) return parsed.interpreted_meals;
	if (Array.isArray(parsed.meals)) return parsed.meals;
	return null;
}

function mapItem(raw: unknown): TaiInterpretMealItem | null {
	const o = asRecord(raw);
	if (!o) return null;
	const name = readString(o.name);
	const unit = readString(o.unit);
	if (name === undefined || unit === undefined) return null;
	return {
		name,
		amount: readFiniteNumber(o.amount, 0),
		unit,
		calories: readInt(o.calories ?? o.kcal, 0),
		proteinGrams: readFiniteNumber(o.proteinGrams ?? o.protein_g, 0),
		carbsGrams: readFiniteNumber(o.carbsGrams ?? o.carbs_g, 0),
		fatGrams: readFiniteNumber(o.fatGrams ?? o.fat_g, 0),
		fiberGrams: readFiniteNumber(o.fiberGrams ?? o.fiber_g, 0),
	};
}

function mapMeal(raw: unknown): TaiInterpretedMeal | null {
	const o = asRecord(raw);
	if (!o) return null;
	const label = readString(o.label);
	const timing = readString(o.timing);
	if (label === undefined || timing === undefined) return null;
	const itemsRaw = o.items;
	if (!Array.isArray(itemsRaw)) return null;
	const items: TaiInterpretMealItem[] = [];
	for (const ir of itemsRaw) {
		const it = mapItem(ir);
		if (!it) return null;
		items.push(it);
	}
	const eatenAtGuessISO8601 =
		readString(o.eatenAtGuessISO8601) ??
		readString(o.eatenAt) ??
		readString(o.eaten_at) ??
		null;
	const calories = readInt(o.calories ?? o.totalCalories ?? o.total_calories, 0);
	return {
		label,
		timing,
		eatenAtGuessISO8601: eatenAtGuessISO8601 ?? undefined,
		items,
		calories,
		proteinGrams: readFiniteNumber(o.proteinGrams ?? o.protein_g, 0),
		carbsGrams: readFiniteNumber(o.carbsGrams ?? o.carbs_g, 0),
		fatGrams: readFiniteNumber(o.fatGrams ?? o.fat_g, 0),
		confidence: readFiniteNumber(o.confidence, 0),
	};
}

function mapUiNotes(v: unknown): string | undefined {
	if (typeof v === "string") return v;
	if (Array.isArray(v)) {
		const parts = v.filter((x): x is string => typeof x === "string");
		if (parts.length) return parts.join("\n");
	}
	return undefined;
}

function mapProviderJsonToAppResponse(providerJson: unknown): TaiInterpretMealResponse | null {
	const text = extractOutputText(providerJson);
	if (text === undefined) return null;
	let parsed: unknown;
	try {
		parsed = parseJsonFromModelText(text);
	} catch {
		return null;
	}
	const root = asRecord(parsed);
	if (!root) return null;
	const mealsRaw = pickMealsArray(root);
	if (mealsRaw === null) return null;
	const interpretedMeals: TaiInterpretedMeal[] = [];
	for (const m of mealsRaw) {
		const meal = mapMeal(m);
		if (!meal) return null;
		interpretedMeals.push(meal);
	}
	const uiNotes = mapUiNotes(root.uiNotes ?? root.ui_notes);
	const out: TaiInterpretMealResponse = { interpretedMeals };
	if (uiNotes !== undefined) out.uiNotes = uiNotes;
	const rootConf = readFiniteNumber(root.confidence, NaN);
	if (Number.isFinite(rootConf)) {
		out.confidence = rootConf;
	} else if (interpretedMeals.length > 0) {
		const sum = interpretedMeals.reduce((a, m) => a + m.confidence, 0);
		out.confidence = sum / interpretedMeals.length;
	}
	return out;
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		if (request.method === "OPTIONS") {
			return json({}, 204);
		}

		const url = new URL(request.url);

		if (url.pathname !== "/ai/interpret-meal") {
			return json({ error: "not_found" }, 404);
		}

		if (request.method !== "POST") {
			return json({ error: "method_not_allowed" }, 405);
		}

		const auth = request.headers.get("Authorization");
		if (auth !== `Bearer ${env.TAI_PROXY_TOKEN}`) {
			return json({ error: "unauthorized" }, 401);
		}

		const contentLength = Number(request.headers.get("Content-Length") ?? "0");
		if (contentLength > MAX_BODY_BYTES) {
			return json({ error: "payload_too_large" }, 413);
		}

		let body: TaiInterpretMealRequest;
		try {
			body = (await request.json()) as TaiInterpretMealRequest;
		} catch {
			return json({ error: "invalid_json" }, 400);
		}

		const approximateJsonBytes = new TextEncoder().encode(JSON.stringify(body)).length;
		console.log("[interpret-meal] content_length_header=", contentLength, "approx_parsed_body_bytes=", approximateJsonBytes);

		const imageB64 = body.imageBase64 ?? body.image?.base64Data;
		if (!body.text && !imageB64) {
			return json({ error: "text_or_image_required" }, 400);
		}

		const schemaHint = [
			"Return a single JSON object with exactly these keys:",
			'- "interpretedMeals": array of meals',
			'- "uiNotes": optional string (short guidance for the user)',
			"",
			'Each meal object must have: "label", "timing", "items", "calories" (integer),',
			'"proteinGrams", "carbsGrams", "fatGrams", "confidence" (0-1).',
			'Optional per meal: "eatenAtGuessISO8601" (ISO-8601 string).',
			"",
			'Each item in "items" must have: "name", "amount", "unit", "calories" (integer),',
			'"proteinGrams", "carbsGrams", "fatGrams", "fiberGrams".',
		].join("\n");

		const prompt = [
			"You are Tai, an AI nutrition strategist.",
			"Return JSON only, no markdown fences.",
			schemaHint,
			"",
			"Request:",
			JSON.stringify({
				text: body.text ?? null,
				hasImage: Boolean(imageB64),
				context: body.context ?? {},
			}),
		].join("\n");

		const inputContent: Array<Record<string, unknown>> = [
			{
				type: "input_text",
				text: prompt,
			},
		];

		if (imageB64) {
			const mime = body.image?.mimeType?.trim() || "image/jpeg";
			inputContent.push({
				type: "input_image",
				image_url: `data:${mime};base64,${imageB64}`,
			});
		}

		const openAIT0 = Date.now();
		const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.OPENAI_API_KEY}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify({
				model: "gpt-5.4-nano",
				input: [
					{
						role: "user",
						content: inputContent,
					},
				],
			}),
		});
		console.log("[interpret-meal] openai_fetch_ms=", Date.now() - openAIT0);

		if (!openAIResponse.ok) {
			return json(
				{
					error: "ai_provider_error",
					status: openAIResponse.status,
				},
				502
			);
		}

		let providerJson: unknown;
		try {
			providerJson = await openAIResponse.json();
		} catch {
			return json({ error: "malformed_ai_response" }, 502);
		}

		const appPayload = mapProviderJsonToAppResponse(providerJson);
		if (!appPayload) {
			return json({ error: "malformed_ai_response" }, 502);
		}

		return json(appPayload, 200);
	},
};
