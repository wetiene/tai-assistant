import {
	buildWorkoutPlanSystemPrompt,
	filterUnknownExerciseIDs,
	mapProviderStructuredToWorkoutPlanResponse,
	redactWorkoutPlanRequestForLogging,
	TAI_WORKOUT_PLAN_RESPONSE_JSON_SCHEMA,
	validateWorkoutPlanRequest,
	type TaiInterpretWorkoutPlanRequest,
	type TaiInterpretWorkoutPlanResponse,
} from "./interpret-workout-plan";

export interface Env {
	OPENAI_API_KEY: string;
	TAI_PROXY_TOKEN: string;
	/** Set to "1" or "true" in dev to include OpenAI diagnostics in malformed_ai_response payloads. */
	TAI_PROXY_DEBUG?: string;
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
	confidence?: number;
	contentType?: "meal" | "gymEquipment" | "ambiguous" | "unsupported";
	classificationConfidence?: number;
	classificationReason?: string;
	containsFood?: boolean;
	containsGymEquipment?: boolean;
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
		contentType: {
			type: "string",
			enum: ["meal", "gymEquipment", "ambiguous", "unsupported"],
		},
		classificationConfidence: { type: "number" },
		classificationReason: { type: "string" },
		containsFood: { type: "boolean" },
		containsGymEquipment: { type: "boolean" },
	},
	required: [
		"interpretedMeals",
		"uiNotes",
		"confidence",
		"contentType",
		"classificationConfidence",
		"classificationReason",
		"containsFood",
		"containsGymEquipment",
	],
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

function extractStructuredJsonFromResponse(raw: unknown): unknown | undefined {
	const text = extractOutputText(raw);
	if (text !== undefined) {
		try {
			return parseJsonFromModelText(text);
		} catch {
			// fall through to output_json
		}
	}
	const root = asRecord(raw);
	if (!root) return undefined;
	const output = root.output;
	if (!Array.isArray(output)) return undefined;
	for (const block of output) {
		const b = asRecord(block);
		if (!b || !Array.isArray(b.content)) continue;
		for (const part of b.content) {
			const p = asRecord(part);
			if (!p) continue;
			if (p.type === "output_json" && p.json !== undefined) {
				return p.json;
			}
		}
	}
	return undefined;
}

type WorkoutPlanMalformedStage =
	| "openai_body_parse"
	| "extract_output_text"
	| "json_parse"
	| "map_response";

function summarizeOutputTypes(raw: unknown): string[] {
	const root = asRecord(raw);
	if (!root || !Array.isArray(root.output)) return [];
	return root.output.flatMap((block) => {
		const b = asRecord(block);
		if (!b) return [];
		const blockType = readString(b.type) ?? "unknown";
		const contentTypes = Array.isArray(b.content)
			? b.content.flatMap((part) => {
					const p = asRecord(part);
					return p ? [readString(p.type) ?? "unknown"] : [];
				})
			: [];
		return [`${blockType}(${contentTypes.join("|") || "no-content"})`];
	});
}

type WorkoutPlanOpenAIDiagnostics = {
	openaiHttpStatus: number;
	contentType: string | null;
	responsePreview: string;
	providerError?: string;
	requestID?: string;
	model?: string;
	stage: WorkoutPlanMalformedStage;
};

function buildWorkoutPlanOpenAIDiagnostics(args: {
	stage: WorkoutPlanMalformedStage;
	openAIResponse: Response;
	responseText: string;
	requestBody: Record<string, unknown>;
	raw?: unknown;
	providerError?: string;
}): WorkoutPlanOpenAIDiagnostics {
	const root = args.raw ? asRecord(args.raw) : null;
	const errorRecord = root?.error ? asRecord(root.error) : null;
	return {
		stage: args.stage,
		openaiHttpStatus: args.openAIResponse.status,
		contentType: args.openAIResponse.headers.get("Content-Type"),
		responsePreview: args.responseText.slice(0, 2000),
		requestID: readString(root?.id) ?? args.openAIResponse.headers.get("x-request-id") ?? undefined,
		model: readString(root?.model) ?? readString(args.requestBody.model),
		providerError: args.providerError ?? readString(errorRecord?.message),
	};
}

function logWorkoutPlanOpenAIDiagnostics(args: {
	stage: string;
	openAIResponse: Response;
	responseText: string;
	requestBody: Record<string, unknown>;
	raw?: unknown;
	providerError?: string;
}) {
	const root = args.raw ? asRecord(args.raw) : null;
	const errorRecord = root?.error ? asRecord(root.error) : null;
	console.log(
		"[interpret-workout-plan] openai_diagnostics",
		JSON.stringify({
			stage: args.stage,
			openaiHttpStatus: args.openAIResponse.status,
			contentType: args.openAIResponse.headers.get("Content-Type"),
			responseByteCount: args.responseText.length,
			requestID: readString(root?.id) ?? args.openAIResponse.headers.get("x-request-id"),
			model: readString(root?.model) ?? readString(args.requestBody.model),
			responseFormat: "json_schema",
			requestPayloadBytes: JSON.stringify(args.requestBody).length,
			outputTypes: args.raw ? summarizeOutputTypes(args.raw) : [],
			providerError: args.providerError ?? readString(errorRecord?.message),
			responsePreview: args.responseText.slice(0, 2000),
		})
	);
}

function isWorkoutPlanDebugEnabled(env: Env): boolean {
	return env.TAI_PROXY_DEBUG === "1" || env.TAI_PROXY_DEBUG === "true";
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
	const contentType = readContentType(root.contentType);
	if (contentType) out.contentType = contentType;
	if (typeof root.classificationConfidence === "number" && Number.isFinite(root.classificationConfidence)) {
		out.classificationConfidence = root.classificationConfidence;
	}
	const reason = readString(root.classificationReason);
	if (reason !== undefined) out.classificationReason = reason;
	if (readBoolean(root.containsFood) !== undefined) out.containsFood = readBoolean(root.containsFood);
	if (readBoolean(root.containsGymEquipment) !== undefined) {
		out.containsGymEquipment = readBoolean(root.containsGymEquipment);
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
		"B) First pass (no `mealRefinement` and empty user `text`): classify the image first. If the image shows gym equipment rather than food, set contentType to gymEquipment and return an empty interpretedMeals array.",
		"C) User intent hints (meal photo vs gym photo) are not ground truth. A gym-photo submission may contain food; a meal-photo submission may contain equipment. Report what is actually visible.",
		"D) Generic correction rules (no food-specific shortcuts):",
		"- Dish type: update `label` to align with the user's correction.",
		"- If `isUserConfirmedLabel` is true for a meal row, keep that `label` exactly unless the user's latest text clearly renames or re-identifies the dish; still refresh `items` and macro totals for their corrections.",
		"- Ingredients: add/remove items and adjust macros; honor removals and exclusions.",
		"- Portion / quantity: when the user states a clear portion change, serving count, or scalar multiplier, scale calories and macros proportionally from the structured prior meal totals unless new details require a full re-estimate.",
		"- Uncertainty: reflect in `confidence` and briefly in `uiNotes` without overriding user-stated facts.",
		"",
		"E) `uiNotes`: at most 1–2 short sentences. After a refinement, state the outcome plainly (what changed). Do not claim the result is mainly from the photo when the user corrected it. Do not repeat that the image is unclear after the user already clarified.",
		"",
		"F) `confidence`: reflect genuine limits of evidence. Never use low confidence to ignore explicit user corrections. If photo and user disagree, follow the user. When totals are driven mainly by user-stated corrections rather than new independent visual evidence, do not output very high confidence — obedience to instructions is not the same as visual certainty.",
		"",
		"G) If instructions are impossible or unsafe, refuse briefly in `uiNotes` and keep JSON schema-valid output.",
		"",
		"H) Output only JSON matching the schema (no markdown fences, no extra prose). `alternatives` must always be an array ([] when none).",
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

export type TaiInterpretGymPhotoRequest = {
	image?: { base64Data?: string; mimeType?: string | null };
	images?: Array<{ base64Data?: string; mimeType?: string | null }>;
	context?: Record<string, unknown>;
};

function resolveGymPhotoImages(body: TaiInterpretGymPhotoRequest): Array<{ base64Data: string; mimeType: string }> {
	if (Array.isArray(body.images) && body.images.length > 0) {
		return body.images.flatMap((item) => {
			const base64Data = item?.base64Data?.trim();
			if (!base64Data) return [];
			return [{ base64Data, mimeType: item?.mimeType?.trim() || "image/jpeg" }];
		});
	}
	const single = body.image?.base64Data?.trim();
	if (!single) return [];
	return [{ base64Data: single, mimeType: body.image?.mimeType?.trim() || "image/jpeg" }];
}

export type TaiInterpretGymPhotoResponse = {
	schemaVersion: number;
	exerciseCandidates: Array<{ exerciseID: string; confidence: number; reason: string }>;
	detectedWeight?: { value: number; unit: string; confidence: number; reason: string } | null;
	limitations: string[];
	requiresConfirmation: boolean;
	contentType: "meal" | "gymEquipment" | "ambiguous" | "unsupported";
	classificationConfidence: number;
	classificationReason: string;
	containsFood: boolean;
	containsGymEquipment: boolean;
};

const TAI_GYM_PHOTO_RESPONSE_JSON_SCHEMA = {
	type: "object",
	additionalProperties: false,
	properties: {
		schemaVersion: { type: "integer" },
		exerciseCandidates: {
			type: "array",
			items: {
				type: "object",
				additionalProperties: false,
				properties: {
					exerciseID: { type: "string" },
					confidence: { type: "number" },
					reason: { type: "string" },
				},
				required: ["exerciseID", "confidence", "reason"],
			},
		},
		detectedWeight: {
			anyOf: [
				{ type: "null" },
				{
					type: "object",
					additionalProperties: false,
					properties: {
						value: { type: "number" },
						unit: { type: "string" },
						confidence: { type: "number" },
						reason: { type: "string" },
					},
					required: ["value", "unit", "confidence", "reason"],
				},
			],
		},
		limitations: { type: "array", items: { type: "string" } },
		requiresConfirmation: { type: "boolean" },
		contentType: {
			type: "string",
			enum: ["meal", "gymEquipment", "ambiguous", "unsupported"],
		},
		classificationConfidence: { type: "number" },
		classificationReason: { type: "string" },
		containsFood: { type: "boolean" },
		containsGymEquipment: { type: "boolean" },
	},
	required: [
		"schemaVersion",
		"exerciseCandidates",
		"detectedWeight",
		"limitations",
		"requiresConfirmation",
		"contentType",
		"classificationConfidence",
		"classificationReason",
		"containsFood",
		"containsGymEquipment",
	],
} as const;

function buildGymPhotoSystemPrompt(): string {
	return [
		"You are Tai's gym equipment vision assistant.",
		"First classify what the image actually shows. User intent hints and workout context are not ground truth.",
		"A gym-photo submission may contain food. A meal-photo submission may contain gym equipment. Report visible evidence only.",
		"Identify the exercise or machine only when gym equipment is actually visible.",
		"Only choose exerciseID values from allowedExerciseCandidates when equipment is visible and plausibly matches.",
		"Never identify an exercise merely because expectedExerciseID or allowedExerciseCandidates were provided.",
		"Return schemaVersion 1 JSON only.",
		"If the image shows food rather than equipment, set contentType to meal, containsFood true, containsGymEquipment false, and return an empty exerciseCandidates array.",
		"If equipment is visible, set contentType to gymEquipment.",
		"Weight is optional evidence. If the weight label, pin, or plates are unclear, set detectedWeight to null and explain why in limitations.",
		"Never guess or infer a weight value.",
		"Never identify people.",
		"requiresConfirmation must always be true.",
	].join(" ");
}

function readAllowedExerciseIDsFromContext(context: Record<string, unknown> | undefined): Set<string> | null {
	if (!context) return null;
	const allowed = context.allowedExerciseCandidates;
	if (!Array.isArray(allowed)) return null;
	const ids = new Set<string>();
	for (const item of allowed) {
		const rec = asRecord(item);
		const id = rec ? readString(rec.exerciseID) : undefined;
		if (id) ids.add(id);
	}
	return ids.size > 0 ? ids : null;
}

function filterGymExerciseCandidates(
	payload: TaiInterpretGymPhotoResponse,
	allowedExerciseIDs: Set<string> | null
): TaiInterpretGymPhotoResponse {
	if (!allowedExerciseIDs) return { ...payload, requiresConfirmation: true };
	return {
		...payload,
		exerciseCandidates: payload.exerciseCandidates.filter((c) => allowedExerciseIDs.has(c.exerciseID)),
		requiresConfirmation: true,
	};
}

function redactGymPhotoRequestForLogging(body: TaiInterpretGymPhotoRequest): Record<string, unknown> {
	return {
		hasImage: Boolean(body.image?.base64Data),
		imageMimeType: body.image?.mimeType ?? null,
		contextKeys: body.context && typeof body.context === "object" ? Object.keys(body.context) : [],
	};
}

function mapProviderStructuredToGymPhotoResponse(providerJson: unknown): TaiInterpretGymPhotoResponse | null {
	const text = extractOutputText(providerJson);
	if (text === undefined) return null;
	let parsed: unknown;
	try {
		parsed = parseJsonFromModelText(text);
	} catch {
		console.log("[interpret-gym-photo] json_parse_failed");
		return null;
	}
	const root = asRecord(parsed);
	if (!root) return null;
	const candidatesRaw = root.exerciseCandidates;
	if (!Array.isArray(candidatesRaw)) return null;
	const exerciseCandidates: TaiInterpretGymPhotoResponse["exerciseCandidates"] = [];
	for (const c of candidatesRaw) {
		const o = asRecord(c);
		if (!o) return null;
		const exerciseID = readString(o.exerciseID);
		const reason = readString(o.reason);
		if (exerciseID === undefined || reason === undefined) return null;
		exerciseCandidates.push({
			exerciseID,
			confidence: readFiniteNumber(o.confidence, 0),
			reason,
		});
	}
	let detectedWeight: TaiInterpretGymPhotoResponse["detectedWeight"] = null;
	const weightRaw = root.detectedWeight;
	if (weightRaw !== null && weightRaw !== undefined) {
		const w = asRecord(weightRaw);
		if (w) {
			const unit = readString(w.unit);
			const reason = readString(w.reason);
			if (unit !== undefined && reason !== undefined) {
				detectedWeight = {
					value: readFiniteNumber(w.value, 0),
					unit,
					confidence: readFiniteNumber(w.confidence, 0),
					reason,
				};
			}
		}
	}
	return {
		schemaVersion: readInt(root.schemaVersion, 1),
		exerciseCandidates,
		detectedWeight,
		limitations: readStringArray(root.limitations, 8),
		requiresConfirmation: root.requiresConfirmation === true || root.requiresConfirmation === undefined,
		contentType: readContentType(root.contentType) ?? "ambiguous",
		classificationConfidence: readFiniteNumber(root.classificationConfidence, 0),
		classificationReason: readString(root.classificationReason) ?? "",
		containsFood: readBoolean(root.containsFood) ?? false,
		containsGymEquipment: readBoolean(root.containsGymEquipment) ?? false,
	};
}

function readContentType(value: unknown): TaiInterpretGymPhotoResponse["contentType"] | null {
	const raw = readString(value);
	if (raw === "meal" || raw === "gymEquipment" || raw === "ambiguous" || raw === "unsupported") {
		return raw;
	}
	return null;
}

async function interpretGymPhotoWithOpenAI(
	env: Env,
	body: TaiInterpretGymPhotoRequest,
	images: Array<{ base64Data: string; mimeType: string }>
): Promise<
	| { status: "success"; payload: TaiInterpretGymPhotoResponse }
	| { status: "ai_provider_error"; openaiHttpStatus: number; openAIDetail?: string }
	| { status: "malformed_ai_response" }
> {
	const ctx = body.context !== undefined ? JSON.stringify(body.context) : "{}";
	const attempt = async (isRetry: boolean) => {
		const imageBlocks = images.map((image) => ({
			type: "input_image",
			image_url: `data:${image.mimeType};base64,${image.base64Data}`,
		}));
		const requestBody = {
			model: OPENAI_MEAL_MODEL,
			input: [
				{ role: "system", content: [{ type: "input_text", text: buildGymPhotoSystemPrompt() }] },
				{
					role: "user",
					content: [
						{ type: "input_text", text: `Workout context JSON:\n${ctx}` },
						...imageBlocks,
						...(isRetry
							? [{ type: "input_text", text: "Return valid JSON matching the schema exactly." }]
							: []),
					],
				},
			],
			text: {
				format: {
					type: "json_schema",
					name: "tai_gym_photo_interpretation",
					schema: TAI_GYM_PHOTO_RESPONSE_JSON_SCHEMA,
					strict: true,
				},
			},
		};
		const openAIResponse = await fetch(OPENAI_RESPONSES_URL, {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.OPENAI_API_KEY}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(requestBody),
		});
		if (!openAIResponse.ok) {
			const detail = summarizeOpenAITextError(await openAIResponse.text());
			return { kind: "http_error" as const, status: openAIResponse.status, openAIDetail: detail };
		}
		const raw = await openAIResponse.json();
		const payload = mapProviderStructuredToGymPhotoResponse(raw);
		if (!payload) return { kind: "structured_output_failed" as const };
		return { kind: "ok" as const, payload };
	};

	let first = await attempt(false);
	if (first.kind === "ok") return { status: "success", payload: first.payload };
	if (first.kind === "http_error")
		return { status: "ai_provider_error", openaiHttpStatus: first.status, openAIDetail: first.openAIDetail };
	let second = await attempt(true);
	if (second.kind === "ok") return { status: "success", payload: second.payload };
	if (second.kind === "http_error")
		return { status: "ai_provider_error", openaiHttpStatus: second.status, openAIDetail: second.openAIDetail };
	return { status: "malformed_ai_response" };
}

async function handleInterpretGymPhoto(request: Request, env: Env): Promise<Response> {
	if (request.method !== "POST") {
		return json({ error: "method_not_allowed" }, 405);
	}
	const unauthorized = requireProxyAuth(request, env);
	if (unauthorized) return unauthorized;

	const contentLength = Number(request.headers.get("Content-Length") ?? "0");
	if (contentLength > MAX_BODY_BYTES) {
		return json({ error: "payload_too_large" }, 413);
	}

	let body: TaiInterpretGymPhotoRequest;
	try {
		body = (await request.json()) as TaiInterpretGymPhotoRequest;
	} catch {
		return json({ error: "invalid_json" }, 400);
	}

	const imageB64List = resolveGymPhotoImages(body);
	if (imageB64List.length === 0) {
		return json({ error: "image_required" }, 400);
	}

	console.log("[interpret-gym-photo] content_length_header=", contentLength, "request_meta=", JSON.stringify(redactGymPhotoRequestForLogging(body)));
	const outcome = await interpretGymPhotoWithOpenAI(env, body, imageB64List);
	if (outcome.status === "success") {
		const allowed = readAllowedExerciseIDsFromContext(
			body.context && typeof body.context === "object" ? (body.context as Record<string, unknown>) : undefined
		);
		const payload = filterGymExerciseCandidates(outcome.payload, allowed);
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

function readKnownExerciseIDsFromWorkoutPlanContext(
	context: Record<string, unknown> | undefined
): Set<string> {
	const known = context?.knownExercises;
	if (!Array.isArray(known)) return new Set();
	const ids = known.flatMap((item) => {
		const record = asRecord(item);
		const id = record ? readString(record.id) : undefined;
		return id ? [id] : [];
	});
	return new Set(ids);
}

async function interpretWorkoutPlanWithOpenAI(
	env: Env,
	body: TaiInterpretWorkoutPlanRequest
): Promise<
	| { status: "success"; payload: TaiInterpretWorkoutPlanResponse }
	| { status: "ai_provider_error"; openaiHttpStatus: number; openAIDetail?: string }
	| {
			status: "malformed_ai_response";
			stage: WorkoutPlanMalformedStage;
			diagnostics?: WorkoutPlanOpenAIDiagnostics;
	  }
> {
	const userBlocks: Array<Record<string, unknown>> = [
		{ type: "input_text", text: `Workout plan context JSON:\n${JSON.stringify(body.context ?? {})}` },
	];
	if (body.source.type === "text") {
		userBlocks.push({ type: "input_text", text: body.source.text ?? "" });
	} else {
		const mime = body.source.attachment?.mimeType?.trim() || "application/octet-stream";
		const b64 = body.source.attachment?.base64Data ?? "";
		userBlocks.push({ type: "input_image", image_url: `data:${mime};base64,${b64}` });
	}
	const requestBody: Record<string, unknown> = {
		model: OPENAI_MEAL_MODEL,
		input: [
			{ role: "system", content: [{ type: "input_text", text: buildWorkoutPlanSystemPrompt() }] },
			{ role: "user", content: userBlocks },
		],
		text: {
			format: {
				type: "json_schema",
				name: "tai_workout_plan_interpretation",
				schema: TAI_WORKOUT_PLAN_RESPONSE_JSON_SCHEMA,
				strict: true,
			},
		},
	};
	const openAIResponse = await fetch(OPENAI_RESPONSES_URL, {
		method: "POST",
		headers: {
			Authorization: `Bearer ${env.OPENAI_API_KEY}`,
			"Content-Type": "application/json",
		},
		body: JSON.stringify(requestBody),
	});
	const responseText = await openAIResponse.text();
	if (!openAIResponse.ok) {
		logWorkoutPlanOpenAIDiagnostics({
			stage: "openai_http_error",
			openAIResponse,
			responseText,
			requestBody,
			providerError: summarizeOpenAITextError(responseText),
		});
		return {
			status: "ai_provider_error",
			openaiHttpStatus: openAIResponse.status,
			openAIDetail: summarizeOpenAITextError(responseText),
		};
	}
	let raw: unknown;
	try {
		raw = JSON.parse(responseText);
	} catch {
		logWorkoutPlanOpenAIDiagnostics({
			stage: "openai_body_parse",
			openAIResponse,
			responseText,
			requestBody,
			providerError: "openai_body_not_json",
		});
		const contentType = openAIResponse.headers.get("Content-Type") ?? "";
		if (contentType && !contentType.toLowerCase().includes("json")) {
			return {
				status: "ai_provider_error",
				openaiHttpStatus: openAIResponse.status,
				openAIDetail: summarizeOpenAITextError(responseText),
			};
		}
		return {
			status: "malformed_ai_response",
			stage: "openai_body_parse",
			diagnostics: buildWorkoutPlanOpenAIDiagnostics({
				stage: "openai_body_parse",
				openAIResponse,
				responseText,
				requestBody,
				providerError: "openai_body_not_json",
			}),
		};
	}

	logWorkoutPlanOpenAIDiagnostics({
		stage: "openai_response_received",
		openAIResponse,
		responseText,
		requestBody,
		raw,
	});

	const refusal = extractFirstRefusal(raw);
	if (refusal) {
		console.log("[interpret-workout-plan] model_refusal=", refusal.slice(0, 200));
		return {
			status: "malformed_ai_response",
			stage: "extract_output_text",
			diagnostics: buildWorkoutPlanOpenAIDiagnostics({
				stage: "extract_output_text",
				openAIResponse,
				responseText,
				requestBody,
				raw,
				providerError: "model_refusal",
			}),
		};
	}

	const parsed = extractStructuredJsonFromResponse(raw);
	if (parsed === undefined) {
		logWorkoutPlanOpenAIDiagnostics({
			stage: "extract_output_text_failed",
			openAIResponse,
			responseText,
			requestBody,
			raw,
		});
		return {
			status: "malformed_ai_response",
			stage: "extract_output_text",
			diagnostics: buildWorkoutPlanOpenAIDiagnostics({
				stage: "extract_output_text",
				openAIResponse,
				responseText,
				requestBody,
				raw,
				providerError: "missing_structured_output",
			}),
		};
	}
	const payload = mapProviderStructuredToWorkoutPlanResponse(parsed);
	if (!payload) {
		logWorkoutPlanOpenAIDiagnostics({
			stage: "map_response_failed",
			openAIResponse,
			responseText,
			requestBody,
			raw,
		});
		return {
			status: "malformed_ai_response",
			stage: "map_response",
			diagnostics: buildWorkoutPlanOpenAIDiagnostics({
				stage: "map_response",
				openAIResponse,
				responseText,
				requestBody,
				raw,
				providerError: "schema_mapping_failed",
			}),
		};
	}
	return { status: "success", payload };
}

async function handleInterpretWorkoutPlan(request: Request, env: Env): Promise<Response> {
	if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
	const unauthorized = requireProxyAuth(request, env);
	if (unauthorized) return unauthorized;

	const contentLength = Number(request.headers.get("Content-Length") ?? "0");
	if (contentLength > MAX_BODY_BYTES) return json({ error: "payload_too_large" }, 413);

	let body: TaiInterpretWorkoutPlanRequest;
	try {
		body = (await request.json()) as TaiInterpretWorkoutPlanRequest;
	} catch {
		return json({ error: "invalid_json" }, 400);
	}

	const validationError = validateWorkoutPlanRequest(body);
	if (validationError) return json({ error: validationError }, 400);

	console.log(
		"[interpret-workout-plan] content_length_header=",
		contentLength,
		"request_meta=",
		JSON.stringify(redactWorkoutPlanRequestForLogging(body))
	);

	const outcome = await interpretWorkoutPlanWithOpenAI(env, body);
	if (outcome.status === "success") {
		const known = readKnownExerciseIDsFromWorkoutPlanContext(
			body.context && typeof body.context === "object" ? (body.context as Record<string, unknown>) : undefined
		);
		return json(filterUnknownExerciseIDs(outcome.payload, known), 200);
	}
	if (outcome.status === "ai_provider_error") {
		return json(
			{
				error: {
					code: "provider_error",
					message: "Workout plan analysis is temporarily unavailable",
					requestID: crypto.randomUUID(),
					status: outcome.openaiHttpStatus,
				},
			},
			502
		);
	}
	return json(
		{
			error: {
				code: "malformed_ai_response",
				message: "Workout plan analysis is temporarily unavailable",
				requestID: crypto.randomUUID(),
				...(isWorkoutPlanDebugEnabled(env) && outcome.diagnostics
					? { debug: outcome.diagnostics }
					: {}),
			},
		},
		502
	);
}

export type TaiCoachRequest = {
	message: string;
	context?: Record<string, unknown>;
};

export type TaiCoachResponse = {
	assistantText: string;
	recommendation?: { title: string; detail?: string | null } | null;
	evidence: Array<{ kind: string; label: string; detail?: string | null }>;
	confidence: string;
	limitations: string[];
	quickActions: Array<{ id: string; title: string }>;
	requiresUserDecision: boolean;
	safety: { state: string; reason?: string | null };
};

const TAI_COACH_RESPONSE_JSON_SCHEMA = {
	type: "object",
	additionalProperties: false,
	properties: {
		assistantText: { type: "string" },
		recommendation: {
			anyOf: [
				{
					type: "object",
					additionalProperties: false,
					properties: {
						title: { type: "string" },
						detail: { type: ["string", "null"] },
					},
					required: ["title", "detail"],
				},
				{ type: "null" },
			],
		},
		evidence: {
			type: "array",
			items: {
				type: "object",
				additionalProperties: false,
				properties: {
					kind: { type: "string" },
					label: { type: "string" },
					detail: { type: ["string", "null"] },
				},
				required: ["kind", "label", "detail"],
			},
		},
		confidence: { type: "string" },
		limitations: { type: "array", items: { type: "string" } },
		quickActions: {
			type: "array",
			items: {
				type: "object",
				additionalProperties: false,
				properties: {
					id: { type: "string" },
					title: { type: "string" },
				},
				required: ["id", "title"],
			},
		},
		requiresUserDecision: { type: "boolean" },
		safety: {
			type: "object",
			additionalProperties: false,
			properties: {
				state: { type: "string" },
				reason: { type: ["string", "null"] },
			},
			required: ["state", "reason"],
		},
	},
	required: [
		"assistantText",
		"recommendation",
		"evidence",
		"confidence",
		"limitations",
		"quickActions",
		"requiresUserDecision",
		"safety",
	],
} as const;

function sanitizeCoachAssistantText(raw: string): string {
	let text = raw.trim();
	// Strip [bracketed annotations]
	text = text.replace(/\[[^\]]{0,120}\]/g, "");
	const banned = [
		/Meal Memory unavailable/gi,
		/Location context unavailable/gi,
		/Location unavailable/gi,
		/HealthKit unavailable/gi,
		/Apple Health \/ HealthKit is not connected/gi,
		/Workout tracking is not available[^.]*\.?/gi,
		/Confirmed today['’]s totals/gi,
		/Confirmed Artifact/gi,
		/capability flags/gi,
		/I don['’]t have meal memory[^.]*\.?/gi,
		/I won['’]t update your saved data[^.]*\.?/gi,
		/I will not update your saved data[^.]*\.?/gi,
	];
	for (const re of banned) {
		text = text.replace(re, "");
	}
	text = text.replace(/\n{3,}/g, "\n\n").replace(/ {2,}/g, " ").trim();
	return text;
}

function buildCoachSystemPrompt(): string {
	return [
		"You are Tai, an advisory AI health and performance coach.",
		"Ground answers ONLY in the provided confirmed meals, goals, recent conversation text, and limitations.",
		"Never invent HealthKit, sleep, weight, workouts, location, or Meal Memory when those signals are unavailable.",
		"Do not mutate, create, or claim to have saved meals, goals, programs, reminders, preferences, or Memory.",
		"requiresUserDecision is an advisory flag only — never treat it as permission to write data, and do not lecture the user about not updating saved data in assistantText.",
		"Safety: refuse medical diagnosis, urgent/emergency symptoms, unsafe restriction, disordered-eating encouragement, and injury-pushing advice. Use safety.state refuse or redirect.",
		"assistantText must be concise, conversational, actionable user-facing prose only.",
		"Never put evidence markers, bracketed annotations, capability flags, or internal labels in assistantText.",
		"Forbidden in assistantText: strings like [Confirmed…], Meal Memory unavailable, Location unavailable, HealthKit unavailable, Confirmed Artifact, capability jargon, or debug provenance.",
		"Put grounded facts in the evidence array. Put only material answer-specific gaps in limitations — never dump the full unavailable-signal catalogue.",
		"Do not repeat generic disclaimers. Prefer short answers (2–4 sentences) unless safety requires more.",
		"quickActions ids must be from this allowlist only when used: meal.takePhoto, meal.describeMeal, meal.askTai, meal.cancelRefine, meal.logIt, liveTai.askAboutIt, liveTai.retry, liveTai.why. Prefer liveTai.why when evidence is present.",
		"No meal photos are in this request.",
	].join(" ");
}

function mapProviderStructuredToCoachResponse(parsed: unknown): TaiCoachResponse | null {
	const o = asRecord(parsed);
	if (!o) return null;
	const assistantTextRaw = readString(o.assistantText)?.trim();
	if (!assistantTextRaw) return null;
	const assistantText = sanitizeCoachAssistantText(assistantTextRaw);
	if (!assistantText) return null;

	let recommendation: TaiCoachResponse["recommendation"] = null;
	if (o.recommendation != null) {
		const r = asRecord(o.recommendation);
		const title = r ? readString(r.title)?.trim() : undefined;
		if (title) {
			recommendation = {
				title,
				detail: r ? readString(r.detail) ?? null : null,
			};
		}
	}

	const evidence: TaiCoachResponse["evidence"] = [];
	if (Array.isArray(o.evidence)) {
		for (const item of o.evidence) {
			const e = asRecord(item);
			if (!e) continue;
			const kind = readString(e.kind)?.trim();
			const label = readString(e.label)?.trim();
			if (!kind || !label) continue;
			evidence.push({
				kind,
				label,
				detail: readString(e.detail) ?? null,
			});
		}
	}

	const limitations = readStringArray(o.limitations, 8);
	const quickActions: TaiCoachResponse["quickActions"] = [];
	if (Array.isArray(o.quickActions)) {
		for (const item of o.quickActions) {
			const q = asRecord(item);
			if (!q) continue;
			const id = readString(q.id)?.trim();
			const title = readString(q.title)?.trim();
			if (!id || !title) continue;
			quickActions.push({ id, title });
		}
	}

	const safetyRaw = asRecord(o.safety);
	const safetyState = (safetyRaw && readString(safetyRaw.state)?.trim()) || "ok";
	const safety = {
		state: safetyState,
		reason: safetyRaw ? readString(safetyRaw.reason) ?? null : null,
	};

	return {
		assistantText,
		recommendation,
		evidence,
		confidence: readString(o.confidence)?.trim() || "medium",
		limitations,
		quickActions,
		requiresUserDecision: o.requiresUserDecision === true,
		safety,
	};
}

async function interpretWithOpenAIStructuredCoach(
	env: Env,
	message: string,
	context: Record<string, unknown> | undefined,
): Promise<
	| { status: "success"; payload: TaiCoachResponse }
	| { status: "ai_provider_error"; openaiHttpStatus: number; openAIDetail?: string }
	| { status: "malformed_ai_response" }
> {
	const contextJson = JSON.stringify(context ?? {}, null, 2);
	const userText = [
		`User question:\n${message}`,
		`Confirmed context JSON (no photos; respect limitations and capability flags):\n${contextJson}`,
	].join("\n\n");

	const openaiRes = await fetch(OPENAI_RESPONSES_URL, {
		method: "POST",
		headers: {
			Authorization: `Bearer ${env.OPENAI_API_KEY}`,
			"Content-Type": "application/json",
		},
		body: JSON.stringify({
			model: OPENAI_MEAL_MODEL,
			input: [
				{
					role: "system",
					content: [{ type: "input_text", text: buildCoachSystemPrompt() }],
				},
				{
					role: "user",
					content: [{ type: "input_text", text: userText }],
				},
			],
			text: {
				format: {
					type: "json_schema",
					name: "tai_coach_response",
					strict: true,
					schema: TAI_COACH_RESPONSE_JSON_SCHEMA,
				},
			},
		}),
	});

	if (!openaiRes.ok) {
		const detail = await openaiRes.text().catch(() => undefined);
		return {
			status: "ai_provider_error",
			openaiHttpStatus: openaiRes.status,
			openAIDetail: detail?.slice(0, 2000),
		};
	}

	const raw = await openaiRes.json();
	const refusal = extractFirstRefusal(raw);
	if (refusal) {
		return {
			status: "success",
			payload: {
				assistantText: refusal,
				recommendation: null,
				evidence: [],
				confidence: "high",
				limitations: [],
				quickActions: [],
				requiresUserDecision: false,
				safety: { state: "refuse", reason: "model_refusal" },
			},
		};
	}

	const text = extractOutputText(raw);
	if (!text) return { status: "malformed_ai_response" };
	try {
		const parsed = parseJsonFromModelText(text);
		const mapped = mapProviderStructuredToCoachResponse(parsed);
		if (!mapped) return { status: "malformed_ai_response" };
		return { status: "success", payload: mapped };
	} catch {
		return { status: "malformed_ai_response" };
	}
}

async function handleCoach(request: Request, env: Env): Promise<Response> {
	if (request.method !== "POST") {
		return json({ error: "method_not_allowed" }, 405);
	}
	const unauthorized = requireProxyAuth(request, env);
	if (unauthorized) return unauthorized;

	const contentLength = Number(request.headers.get("Content-Length") ?? "0");
	if (contentLength > MAX_BODY_BYTES) {
		return json({ error: "payload_too_large" }, 413);
	}

	let body: TaiCoachRequest;
	try {
		body = (await request.json()) as TaiCoachRequest;
	} catch {
		return json({ error: "invalid_json" }, 400);
	}

	const message = typeof body.message === "string" ? body.message.trim() : "";
	if (message.length === 0) {
		return json({ error: "message_required" }, 400);
	}

	const ctx = body.context !== undefined ? asRecord(body.context) ?? undefined : undefined;
	// Never accept or forward ownerID / image payloads on this route.
	if (ctx && "ownerID" in ctx) {
		delete ctx.ownerID;
	}

	const outcome = await interpretWithOpenAIStructuredCoach(env, message, ctx);
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
		if (url.pathname === "/ai/interpret-gym-photo") {
			return handleInterpretGymPhoto(request, env);
		}
		if (url.pathname === "/ai/interpret-workout-plan") {
			return handleInterpretWorkoutPlan(request, env);
		}
		if (url.pathname === "/ai/coach") {
			return handleCoach(request, env);
		}

		return json({ error: "not_found" }, 404);
	},
};

export const __test = {
	TAI_MEAL_RESPONSE_JSON_SCHEMA,
	TAI_GOAL_RESPONSE_JSON_SCHEMA,
	TAI_COACH_RESPONSE_JSON_SCHEMA,
	TAI_GYM_PHOTO_RESPONSE_JSON_SCHEMA,
	TAI_WORKOUT_PLAN_RESPONSE_JSON_SCHEMA,
	buildSystemPrompt,
	buildGoalSystemPrompt,
	buildCoachSystemPrompt,
	buildGymPhotoSystemPrompt,
	mapProviderStructuredToAppResponse,
	mapProviderStructuredToGoalResponse,
	mapProviderStructuredToCoachResponse,
	mapProviderStructuredToGymPhotoResponse,
	filterGymExerciseCandidates,
	readAllowedExerciseIDsFromContext,
	redactGymPhotoRequestForLogging,
	redactWorkoutPlanRequestForLogging,
	validateWorkoutPlanRequest,
	mapProviderStructuredToWorkoutPlanResponse,
	filterUnknownExerciseIDs,
	sanitizeCoachAssistantText,
	parseMealRefinementFromContext,
	collectUserTextBlocksForTests,
};
