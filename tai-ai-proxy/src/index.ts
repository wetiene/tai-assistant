export interface Env {
	OPENAI_API_KEY: string;
	TAI_PROXY_TOKEN: string;
}

const MAX_BODY_BYTES = 4_500_000;

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
/** Stronger multimodal tier than nano; aligns with Phase 2 accuracy goals. */
const OPENAI_MEAL_MODEL = "gpt-5.4-mini";

export type TaiInterpretMealRequest = {
	text?: string;
	/** Legacy / alternate shape */
	imageBase64?: string;
	image?: { base64Data?: string; mimeType?: string | null };
	context?: Record<string, unknown>;
};

export type TaiInterpretGoalRequest = {
	prompt: string;
	context?: Record<string, unknown>;
};

/** Matches iOS `AIInterpretGoalResponse` camelCase keys. */
export type TaiInterpretGoalResponse = {
	originalPrompt: string;
	goalType: string;
	title: string;
	calorieTarget: number;
	proteinTarget: number;
	carbsTarget: number;
	fatTarget: number;
	fiberTarget: number;
	waterTarget: number;
	activityIntent: string;
	uiNotes: string;
	confidence: number;
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
	/** 0–3 short alternative meal labels when visually ambiguous; empty when confident. */
	alternatives: string[];
};

type TaiInterpretMealResponse = {
	interpretedMeals: TaiInterpretedMeal[];
	uiNotes?: string | null;
	/** Optional aggregate signal; iOS decoder ignores unknown keys. */
	confidence?: number;
};

/** JSON Schema for Responses API structured outputs (`strict: true`). Matches app contract camelCase keys. */
const TAI_MEAL_RESPONSE_JSON_SCHEMA = {
	type: "object",
	additionalProperties: false,
	properties: {
		interpretedMeals: {
			type: "array",
			items: {
				type: "object",
				additionalProperties: false,
				properties: {
					label: { type: "string" },
					timing: { type: "string" },
					eatenAtGuessISO8601: {
						type: "string",
						description: "ISO-8601 guess when the meal was eaten; use empty string if unknown",
					},
					items: {
						type: "array",
						items: {
							type: "object",
							additionalProperties: false,
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
						},
					},
					calories: { type: "integer" },
					proteinGrams: { type: "number" },
					carbsGrams: { type: "number" },
					fatGrams: { type: "number" },
					confidence: { type: "number" },
					alternatives: {
						type: "array",
						description: "1–2 alternative meal labels if visually ambiguous; otherwise []",
						items: { type: "string" },
					},
				},
				// Strict JSON Schema requires `required` to list every key in `properties`.
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
			},
		},
		uiNotes: {
			type: "string",
			description: "Short guidance for the user; use empty string if none",
		},
		confidence: {
			type: "number",
			description: "Aggregate confidence 0–1; use 0 if not applicable",
		},
	},
	required: ["interpretedMeals", "uiNotes", "confidence"],
} satisfies Record<string, unknown>;

/** JSON Schema for goal interpretation (`POST /ai/interpret-goal`). Every property is required for `strict: true`. */
const TAI_GOAL_RESPONSE_JSON_SCHEMA = {
	type: "object",
	additionalProperties: false,
	properties: {
		originalPrompt: { type: "string", description: "Echo the user's goal text verbatim" },
		goalType: {
			type: "string",
			description: "Short machine tag e.g. fat_loss, maintenance, muscle_gain, performance, other",
		},
		title: { type: "string", description: "Human-readable goal title" },
		calorieTarget: { type: "integer", description: "Daily calorie target (kcal)" },
		proteinTarget: { type: "number", description: "Daily protein grams" },
		carbsTarget: { type: "number", description: "Daily carbohydrate grams" },
		fatTarget: { type: "number", description: "Daily fat grams" },
		fiberTarget: { type: "integer", description: "Daily fiber grams target; use 0 if unknown" },
		waterTarget: { type: "integer", description: "Daily water milliliters; use 0 if unknown" },
		activityIntent: { type: "string", description: "Training or lifestyle intent; empty string if none" },
		uiNotes: {
			type: "string",
			description: "1–2 short sentences for the user; empty string if none",
		},
		confidence: { type: "number", description: "0–1 confidence in the macro targets" },
	},
	required: [
		"originalPrompt",
		"goalType",
		"title",
		"calorieTarget",
		"proteinTarget",
		"carbsTarget",
		"fatTarget",
		"fiberTarget",
		"waterTarget",
		"activityIntent",
		"uiNotes",
		"confidence",
	],
} satisfies Record<string, unknown>;

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
 * OpenAI Responses API: assistant structured text is under output[].content[].text
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

function extractFirstRefusal(raw: unknown): string | undefined {
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
			if (p.type === "refusal" && typeof p.refusal === "string") {
				return p.refusal;
			}
		}
	}
	return undefined;
}

/** Structured outputs normally return bare JSON; keep fence stripping for defensive parsing. */
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

/** Preserves model order; trims; caps length for safety (prompt limits count). */
function readStringArray(v: unknown, maxItems: number): string[] {
	if (!Array.isArray(v)) return [];
	const out: string[] = [];
	for (const x of v) {
		if (typeof x !== "string") continue;
		const t = x.trim();
		if (t.length === 0) continue;
		out.push(t);
		if (out.length >= maxItems) break;
	}
	return out;
}

function pickMealsArray(parsed: Record<string, unknown>): unknown[] | null {
	if (Array.isArray(parsed.interpretedMeals)) return parsed.interpretedMeals;
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
	let eatenRaw = o.eatenAtGuessISO8601;
	const eatenStr =
		typeof eatenRaw === "string" && eatenRaw.trim().length > 0 ? eatenRaw.trim() : undefined;
	const calories = readInt(o.calories ?? o.totalCalories ?? o.total_calories, 0);
	const alternatives = readStringArray(o.alternatives, 3);
	return {
		label,
		timing,
		eatenAtGuessISO8601: eatenStr ?? undefined,
		items,
		calories,
		proteinGrams: readFiniteNumber(o.proteinGrams ?? o.protein_g, 0),
		carbsGrams: readFiniteNumber(o.carbsGrams ?? o.carbs_g, 0),
		fatGrams: readFiniteNumber(o.fatGrams ?? o.fat_g, 0),
		confidence: readFiniteNumber(o.confidence, 0),
		alternatives,
	};
}

function mapProviderStructuredToAppResponse(providerJson: unknown): TaiInterpretMealResponse | null {
	const refusal = extractFirstRefusal(providerJson);
	if (refusal !== undefined) {
		console.log("[interpret-meal] openai_refusal");
		return null;
	}
	const text = extractOutputText(providerJson);
	if (text === undefined) return null;
	let parsed: unknown;
	try {
		parsed = parseJsonFromModelText(text);
	} catch {
		console.log("[interpret-meal] json_parse_failed");
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
	const out: TaiInterpretMealResponse = { interpretedMeals };
	const notesCandidate = root.uiNotes ?? root.ui_notes;
	const trimmedNotes = typeof notesCandidate === "string" ? notesCandidate.trim() : "";
	if (trimmedNotes.length > 0) out.uiNotes = trimmedNotes;
	const rc = root.confidence;
	if (typeof rc === "number" && Number.isFinite(rc)) out.confidence = rc;
	if (out.confidence === undefined && interpretedMeals.length > 0) {
		const sum = interpretedMeals.reduce((a, m) => a + m.confidence, 0);
		out.confidence = sum / interpretedMeals.length;
	}
	return out;
}

function mapProviderStructuredToGoalResponse(providerJson: unknown): TaiInterpretGoalResponse | null {
	const refusal = extractFirstRefusal(providerJson);
	if (refusal !== undefined) {
		console.log("[interpret-goal] openai_refusal");
		return null;
	}
	const text = extractOutputText(providerJson);
	if (text === undefined) return null;
	let parsed: unknown;
	try {
		parsed = parseJsonFromModelText(text);
	} catch {
		console.log("[interpret-goal] json_parse_failed");
		return null;
	}
	const root = asRecord(parsed);
	if (!root) return null;
	const originalPrompt = readString(root.originalPrompt);
	const goalType = readString(root.goalType);
	const title = readString(root.title);
	if (originalPrompt === undefined || goalType === undefined || title === undefined) return null;
	const out: TaiInterpretGoalResponse = {
		originalPrompt,
		goalType,
		title,
		calorieTarget: readInt(root.calorieTarget, 0),
		proteinTarget: readFiniteNumber(root.proteinTarget, 0),
		carbsTarget: readFiniteNumber(root.carbsTarget, 0),
		fatTarget: readFiniteNumber(root.fatTarget, 0),
		fiberTarget: readInt(root.fiberTarget, 0),
		waterTarget: readInt(root.waterTarget, 0),
		activityIntent: readString(root.activityIntent) ?? "",
		uiNotes: readString(root.uiNotes) ?? "",
		confidence: readFiniteNumber(root.confidence, 0),
	};
	return out;
}

function readContextString(ctx: Record<string, unknown> | undefined, key: string): string | undefined {
	if (!ctx) return undefined;
	const v = ctx[key];
	return typeof v === "string" && v.trim() !== "" ? v.trim() : undefined;
}

function readBoolean(v: unknown): boolean | undefined {
	if (typeof v === "boolean") return v;
	return undefined;
}

type MealRefinementLineItem = {
	name: string;
	amount: number;
	unit: string;
	calories: number;
	proteinGrams: number;
	carbsGrams: number;
	fatGrams: number;
	fiberGrams: number;
};

type MealRefinementMeal = {
	label: string;
	timing: string;
	calories: number;
	proteinGrams: number;
	carbsGrams: number;
	fatGrams: number;
	confidence: number;
	isUserConfirmedLabel: boolean;
	items: MealRefinementLineItem[];
};

type MealRefinementPayload = {
	meals: MealRefinementMeal[];
	priorUserTextLines: string[];
	hasPhotoAttachment: boolean;
};

function mapRefinementLineItem(raw: unknown): MealRefinementLineItem | null {
	const o = asRecord(raw);
	if (!o) return null;
	const name = readString(o.name);
	const unit = readString(o.unit);
	if (name === undefined || unit === undefined) return null;
	return {
		name,
		amount: readFiniteNumber(o.amount, 0),
		unit,
		calories: readInt(o.calories, 0),
		proteinGrams: readFiniteNumber(o.proteinGrams, 0),
		carbsGrams: readFiniteNumber(o.carbsGrams, 0),
		fatGrams: readFiniteNumber(o.fatGrams, 0),
		fiberGrams: readFiniteNumber(o.fiberGrams, 0),
	};
}

function parseMealRefinementFromContext(ctx: Record<string, unknown> | undefined): MealRefinementPayload | null {
	if (!ctx) return null;
	const root = ctx["mealRefinement"];
	if (root === undefined || root === null) return null;
	const rec = asRecord(root);
	if (!rec) return null;
	const mealsRaw = rec["meals"];
	if (!Array.isArray(mealsRaw) || mealsRaw.length === 0) return null;
	const meals: MealRefinementMeal[] = [];
	for (const m of mealsRaw) {
		const mr = asRecord(m);
		if (!mr) return null;
		const label = readString(mr.label);
		const timing = readString(mr.timing);
		if (label === undefined || timing === undefined) return null;
		const itemsRaw = mr["items"];
		if (!Array.isArray(itemsRaw)) return null;
		const items: MealRefinementLineItem[] = [];
		for (const ir of itemsRaw) {
			const li = mapRefinementLineItem(ir);
			if (!li) return null;
			items.push(li);
		}
		const isUserConfirmed = readBoolean(mr.isUserConfirmedLabel) ?? false;
		meals.push({
			label,
			timing,
			calories: readInt(mr.calories, 0),
			proteinGrams: readFiniteNumber(mr.proteinGrams, 0),
			carbsGrams: readFiniteNumber(mr.carbsGrams, 0),
			fatGrams: readFiniteNumber(mr.fatGrams, 0),
			confidence: readFiniteNumber(mr.confidence, 0),
			isUserConfirmedLabel: isUserConfirmed,
			items,
		});
	}
	const priorRaw = rec["priorUserTextLines"];
	const priorUserTextLines: string[] = [];
	if (Array.isArray(priorRaw)) {
		for (const line of priorRaw) {
			if (typeof line !== "string") continue;
			const t = line.trim();
			if (t.length > 0) priorUserTextLines.push(t);
		}
	}
	const hasPhotoAttachment = readBoolean(rec.hasPhotoAttachment) ?? false;
	return { meals, priorUserTextLines, hasPhotoAttachment };
}

function buildSystemPrompt(): string {
	return [
		"You are Tai, a practical nutrition coach helping users log meals from photos and short notes.",
		"Tone: concise and outcome-focused. Avoid long reasoning, chain-of-thought, or internal-model narration. Prefer short confirmations and clear adjustment outcomes.",
		"",
		"A) Instruction priority (highest authority first — never invert):",
		"1) Latest user message in the request `text` field when non-empty. Treat it as authoritative for corrections: dish type, ingredients, portions, exclusions, preparation, and quantities.",
		"2) Earlier user lines from structured context `priorUserTextLines` when present.",
		"3) Structured prior meal estimate in `mealRefinement` (labels, macros, items, flags). This is the current estimate to revise, not a substitute for new user instructions.",
		"4) Image interpretation — informs composition and portions when the user has not contradicted it.",
		"5) Free-floating prior AI guesses not reflected in structured state — lowest authority.",
		"",
		"When user text conflicts with the image, follow the user and update the estimate. Do not treat explicit corrections as weak optional notes.",
		"",
		"B) First pass (no `mealRefinement` and empty user `text`): use the image with cautious labeling, honest confidence, and alternatives when ambiguous.",
		"",
		"C) Generic correction rules (no food-specific shortcuts):",
		"- Dish type: update `label` to align with the user's correction.",
		"- If `isUserConfirmedLabel` is true for a meal row, keep that `label` exactly unless the user's latest text clearly renames or re-identifies the dish; still refresh `items` and macro totals for their corrections.",
		"- Ingredients: add/remove items and adjust macros; honor removals and exclusions.",
		"- Portion / quantity: when the user states a clear portion change, serving count, or scalar multiplier, scale calories and macros proportionally from the structured prior meal totals unless new details require a full re-estimate.",
		"- Uncertainty: reflect in `confidence` and briefly in `uiNotes` without overriding user-stated facts.",
		"",
		"D) `uiNotes`: at most 1–2 short sentences. After a refinement, state the outcome plainly (what changed). Do not claim the result is mainly from the photo when the user corrected it. Do not repeat that the image is unclear after the user already clarified.",
		"",
		"E) `confidence`: reflect genuine limits of evidence. Never use low confidence to ignore explicit user corrections. If photo and user disagree, follow the user. When totals are driven mainly by user-stated corrections rather than new independent visual evidence, do not output very high confidence — obedience to instructions is not the same as visual certainty.",
		"",
		"F) If instructions are impossible or unsafe, refuse briefly in `uiNotes` and keep JSON schema-valid output.",
		"",
		"G) Output only JSON matching the schema (no markdown fences, no extra prose). `alternatives` must always be an array ([] when none).",
	].join("\n");
}

function buildUserContentParts(
	body: TaiInterpretMealRequest,
	imageB64: string | undefined,
	mime: string,
	isRetryHint: boolean
): Array<{ type: string; detail?: string; image_url?: string; text?: string }> {
	const parts: Array<{ type: string; detail?: string; image_url?: string; text?: string }> = [];
	const ctx = body.context !== undefined ? asRecord(body.context) ?? undefined : undefined;
	const refinement = parseMealRefinementFromContext(ctx);

	parts.push({
		type: "input_text",
		text: "Apply SYSTEM priority rules. Blocks below may include an image, the latest user message, and JSON `mealRefinement` prior state.",
	});

	if (imageB64) {
		parts.push({
			type: "input_image",
			detail: "high",
			image_url: `data:${mime};base64,${imageB64}`,
		});
	}

	const trimmed = typeof body.text === "string" ? body.text.trim() : "";
	if (trimmed.length > 0) {
		parts.push({
			type: "input_text",
			text: `Latest user message (highest authority):\n${trimmed}`,
		});
	} else {
		parts.push({
			type: "input_text",
			text: "Latest user message (highest authority): (empty — use structured prior and image per SYSTEM rules.)",
		});
	}

	if (refinement !== null) {
		parts.push({
			type: "input_text",
			text: `Structured prior meal state (JSON). Revise this estimate; photo attached this round: ${refinement.hasPhotoAttachment}.\n${JSON.stringify(refinement)}`,
		});
	}

	const locale = readContextString(ctx, "localeIdentifier");
	const tz = readContextString(ctx, "timeZoneIdentifier");
	const lines: string[] = [];
	if (locale) lines.push(`User locale: ${locale}`);
	if (tz) lines.push(`Local time zone: ${tz}`);
	if (lines.length > 0) {
		parts.push({ type: "input_text", text: lines.join("\n") });
	}

	if (isRetryHint) {
		parts.push({
			type: "input_text",
			text: "Return valid JSON matching the schema exactly. No explanation or markdown.",
		});
	}
	return parts;
}

/** Concatenates user `input_text` parts for unit tests (prompt wiring). */
function collectUserTextBlocksForTests(
	body: TaiInterpretMealRequest,
	imageB64: string | undefined,
	mime: string,
	isRetryHint: boolean
): string[] {
	const parts = buildUserContentParts(body, imageB64, mime, isRetryHint);
	return parts
		.filter((p) => p.type === "input_text" && typeof p.text === "string")
		.map((p) => p.text as string);
}

type OpenAIMealAttemptResult =
	| { kind: "ok"; payload: TaiInterpretMealResponse }
	| { kind: "http_error"; status: number; openAIDetail?: string }
	| { kind: "structured_output_failed" };

type InterpretMealOutcome =
	| { status: "success"; payload: TaiInterpretMealResponse }
	| { status: "ai_provider_error"; openaiHttpStatus: number; openAIDetail?: string }
	| { status: "malformed_ai_response" };

/** Parses OpenAI JSON error payloads; trims length only (never echo secrets beyond API error.message). */
function summarizeOpenAITextError(rawBody: string): string | undefined {
	const trimmed = rawBody.trim();
	if (!trimmed) return undefined;
	let parsed: unknown;
	try {
		parsed = JSON.parse(trimmed);
	} catch {
		return trimmed.slice(0, 900);
	}
	const root = asRecord(parsed);
	const errBlob = root && asRecord(root.error);
	const msg = errBlob !== null ? readString(errBlob.message) : undefined;
	const code = errBlob !== null ? readString(errBlob.code) : undefined;
	const param = errBlob !== null ? readString(errBlob.param) : undefined;
	const parts = [msg, code && `(${code})`, param && `[${param}]`].filter(Boolean);
	if (parts.length === 0) return trimmed.slice(0, 900);
	return parts.join(" ").slice(0, 1200);
}

async function interpretWithOpenAIStructured(env: Env, body: TaiInterpretMealRequest, imageB64: string | undefined): Promise<InterpretMealOutcome> {
	const mime = body.image?.mimeType?.trim() || "image/jpeg";

	const attempt = async (isRetryHint: boolean): Promise<OpenAIMealAttemptResult> => {
		const requestBody = {
			model: OPENAI_MEAL_MODEL,
			input: [
				{
					role: "system",
					content: [{ type: "input_text", text: buildSystemPrompt() }],
				},
				{
					role: "user",
					content: buildUserContentParts(body, imageB64, mime, isRetryHint),
				},
			],
			text: {
				format: {
					type: "json_schema",
					name: "tai_meal_interpretation",
					strict: true,
					schema: TAI_MEAL_RESPONSE_JSON_SCHEMA,
				},
			},
		};

		const openAIT0 = Date.now();
		const openAIResponse = await fetch(OPENAI_RESPONSES_URL, {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.OPENAI_API_KEY}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(requestBody),
		});
		console.log("[interpret-meal] openai_fetch_ms=", Date.now() - openAIT0, "retry_hint=", isRetryHint);

		if (!openAIResponse.ok) {
			const errText = await openAIResponse.text();
			const openAIDetail = summarizeOpenAITextError(errText);
			console.log("[interpret-meal] openai_http_status=", openAIResponse.status);
			return { kind: "http_error", status: openAIResponse.status, openAIDetail };
		}

		let providerJson: unknown;
		try {
			providerJson = await openAIResponse.json();
		} catch {
			return { kind: "structured_output_failed" };
		}

		const payload = mapProviderStructuredToAppResponse(providerJson);
		if (payload) return { kind: "ok", payload };
		return { kind: "structured_output_failed" };
	};

	let first = await attempt(false);
	if (first.kind === "ok") return { status: "success", payload: first.payload };
	if (first.kind === "http_error")
		return { status: "ai_provider_error", openaiHttpStatus: first.status, openAIDetail: first.openAIDetail };

	console.log("[interpret-meal] retrying_structured_output");
	let second = await attempt(true);
	if (second.kind === "ok") return { status: "success", payload: second.payload };
	if (second.kind === "http_error")
		return { status: "ai_provider_error", openaiHttpStatus: second.status, openAIDetail: second.openAIDetail };
	return { status: "malformed_ai_response" };
}

function buildGoalSystemPrompt(): string {
	return [
		"You are Tai, a practical nutrition coach.",
		"Convert the user's natural-language nutrition goal into safe, realistic daily macro targets for a healthy adult.",
		"Prefer moderate deficits for fat loss; avoid extreme restriction. If details are missing, choose sensible defaults and reflect uncertainty in confidence.",
		"Output only JSON matching the schema (no markdown fences, no extra prose).",
		"Use empty string \"\" only where the schema allows a string field you truly have no content for.",
	].join("\n");
}

function buildGoalUserContentParts(prompt: string, ctx: Record<string, unknown> | undefined): Array<{ type: string; text?: string }> {
	const parts: Array<{ type: string; text?: string }> = [];
	parts.push({
		type: "input_text",
		text: `User goal (verbatim):\n${prompt}`,
	});
	const locale = readContextString(ctx, "localeIdentifier");
	const tz = readContextString(ctx, "timeZoneIdentifier");
	const lines: string[] = [];
	if (locale) lines.push(`User locale: ${locale}`);
	if (tz) lines.push(`Local time zone: ${tz}`);
	if (lines.length > 0) {
		parts.push({ type: "input_text", text: lines.join("\n") });
	}
	return parts;
}

type OpenAIGoalAttemptResult =
	| { kind: "ok"; payload: TaiInterpretGoalResponse }
	| { kind: "http_error"; status: number; openAIDetail?: string }
	| { kind: "structured_output_failed" };

type InterpretGoalOutcome =
	| { status: "success"; payload: TaiInterpretGoalResponse }
	| { status: "ai_provider_error"; openaiHttpStatus: number; openAIDetail?: string }
	| { status: "malformed_ai_response" };

async function interpretWithOpenAIStructuredGoal(
	env: Env,
	prompt: string,
	ctx: Record<string, unknown> | undefined
): Promise<InterpretGoalOutcome> {
	const attempt = async (isRetryHint: boolean): Promise<OpenAIGoalAttemptResult> => {
		const userParts = buildGoalUserContentParts(prompt, ctx);
		if (isRetryHint) {
			userParts.push({
				type: "input_text",
				text: "Return valid JSON matching the schema exactly. No explanation or markdown.",
			});
		}
		const requestBody = {
			model: OPENAI_MEAL_MODEL,
			input: [
				{
					role: "system",
					content: [{ type: "input_text", text: buildGoalSystemPrompt() }],
				},
				{
					role: "user",
					content: userParts,
				},
			],
			text: {
				format: {
					type: "json_schema",
					name: "tai_goal_interpretation",
					strict: true,
					schema: TAI_GOAL_RESPONSE_JSON_SCHEMA,
				},
			},
		};

		const openAIT0 = Date.now();
		const openAIResponse = await fetch(OPENAI_RESPONSES_URL, {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.OPENAI_API_KEY}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(requestBody),
		});
		console.log("[interpret-goal] openai_fetch_ms=", Date.now() - openAIT0, "retry_hint=", isRetryHint);

		if (!openAIResponse.ok) {
			const errText = await openAIResponse.text();
			const openAIDetail = summarizeOpenAITextError(errText);
			console.log("[interpret-goal] openai_http_status=", openAIResponse.status);
			return { kind: "http_error", status: openAIResponse.status, openAIDetail };
		}

		let providerJson: unknown;
		try {
			providerJson = await openAIResponse.json();
		} catch {
			return { kind: "structured_output_failed" };
		}

		const payload = mapProviderStructuredToGoalResponse(providerJson);
		if (payload) return { kind: "ok", payload };
		return { kind: "structured_output_failed" };
	};

	let first = await attempt(false);
	if (first.kind === "ok") return { status: "success", payload: first.payload };
	if (first.kind === "http_error")
		return { status: "ai_provider_error", openaiHttpStatus: first.status, openAIDetail: first.openAIDetail };

	console.log("[interpret-goal] retrying_structured_output");
	let second = await attempt(true);
	if (second.kind === "ok") return { status: "success", payload: second.payload };
	if (second.kind === "http_error")
		return { status: "ai_provider_error", openaiHttpStatus: second.status, openAIDetail: second.openAIDetail };
	return { status: "malformed_ai_response" };
}

function requireProxyAuth(request: Request, env: Env): Response | null {
	const auth = request.headers.get("Authorization");
	if (auth !== `Bearer ${env.TAI_PROXY_TOKEN}`) {
		return json({ error: "unauthorized" }, 401);
	}
	return null;
}

async function handleInterpretMeal(request: Request, env: Env): Promise<Response> {
	if (request.method !== "POST") {
		return json({ error: "method_not_allowed" }, 405);
	}
	const unauthorized = requireProxyAuth(request, env);
	if (unauthorized) return unauthorized;

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

	const outcome = await interpretWithOpenAIStructured(env, body, imageB64);
	if (outcome.status === "success") return json(outcome.payload, 200);
	if (outcome.status === "ai_provider_error") {
		const payload: Record<string, unknown> = {
			error: "ai_provider_error",
			status: outcome.openaiHttpStatus,
		};
		if (outcome.openAIDetail) payload.openai_detail = outcome.openAIDetail;
		return json(payload, 502);
	}
	return json({ error: "malformed_ai_response" }, 502);
}

async function handleInterpretGoal(request: Request, env: Env): Promise<Response> {
	if (request.method !== "POST") {
		return json({ error: "method_not_allowed" }, 405);
	}
	const unauthorized = requireProxyAuth(request, env);
	if (unauthorized) return unauthorized;

	const contentLength = Number(request.headers.get("Content-Length") ?? "0");
	if (contentLength > MAX_BODY_BYTES) {
		return json({ error: "payload_too_large" }, 413);
	}

	let body: TaiInterpretGoalRequest;
	try {
		body = (await request.json()) as TaiInterpretGoalRequest;
	} catch {
		return json({ error: "invalid_json" }, 400);
	}

	const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
	if (prompt.length === 0) {
		return json({ error: "prompt_required" }, 400);
	}

	const ctx = body.context !== undefined ? asRecord(body.context) ?? undefined : undefined;
	const approximateJsonBytes = new TextEncoder().encode(JSON.stringify(body)).length;
	console.log("[interpret-goal] content_length_header=", contentLength, "approx_parsed_body_bytes=", approximateJsonBytes);

	const outcome = await interpretWithOpenAIStructuredGoal(env, prompt, ctx);
	if (outcome.status === "success") {
		const payload = { ...outcome.payload, originalPrompt: prompt };
		return json(payload, 200);
	}
	if (outcome.status === "ai_provider_error") {
		const payload: Record<string, unknown> = {
			error: "ai_provider_error",
			status: outcome.openaiHttpStatus,
		};
		if (outcome.openAIDetail) payload.openai_detail = outcome.openAIDetail;
		return json(payload, 502);
	}
	return json({ error: "malformed_ai_response" }, 502);
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		if (request.method === "OPTIONS") {
			return json({}, 204);
		}

		const url = new URL(request.url);

		if (url.pathname === "/ai/interpret-meal") {
			return handleInterpretMeal(request, env);
		}
		if (url.pathname === "/ai/interpret-goal") {
			return handleInterpretGoal(request, env);
		}

		return json({ error: "not_found" }, 404);
	},
};

export const __test = {
	TAI_MEAL_RESPONSE_JSON_SCHEMA,
	TAI_GOAL_RESPONSE_JSON_SCHEMA,
	buildSystemPrompt,
	buildGoalSystemPrompt,
	mapProviderStructuredToAppResponse,
	mapProviderStructuredToGoalResponse,
	parseMealRefinementFromContext,
	collectUserTextBlocksForTests,
};
