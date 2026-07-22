export type TaiInterpretWorkoutPlanRequest = {
	schemaVersion: number;
	source: {
		type: "text" | "image" | "pdf";
		text?: string | null;
		attachment?: { base64Data?: string | null; mimeType?: string | null } | null;
	};
	context?: {
		localeIdentifier?: string | null;
		preferredWeightUnit?: string | null;
		knownExercises?: Array<{ id: string; name: string }>;
	};
};

export type TaiInterpretWorkoutPlanResponse = {
	schemaVersion: number;
	suggestedPlan: {
		name: string;
		sections: Array<{
			name: string;
			orderIndex: number;
			exercises: Array<{
				sourceName: string;
				matchedExerciseID: string | null;
				displayName: string;
				orderIndex: number;
				targetSets: number | null;
				minimumRepetitions: number | null;
				maximumRepetitions: number | null;
				isOptional: boolean;
				notes: string | null;
				matchConfidence: number;
			}>;
		}>;
		generalInstructions: string[];
		suggestedDurationWeeks: number | null;
	};
	unresolvedItems: Array<{
		sourceText: string;
		reason: string;
		suggestedMatches: Array<{ exerciseID: string; confidence: number }>;
	}>;
	warnings: string[];
	confidence: string;
	requiresUserConfirmation: boolean;
};

const SUPPORTED_SOURCE_TYPES = new Set(["text", "image", "pdf"]);
const SUPPORTED_IMAGE_MIMES = new Set(["image/jpeg", "image/png", "image/webp"]);
const SUPPORTED_FILE_MIMES = new Set(["application/pdf", ...SUPPORTED_IMAGE_MIMES]);
const MAX_TEXT_CHARS = 32_000;

function asRecord(value: unknown): Record<string, unknown> | null {
	return value !== null && typeof value === "object" && !Array.isArray(value)
		? (value as Record<string, unknown>)
		: null;
}

function readString(value: unknown): string | undefined {
	return typeof value === "string" ? value : undefined;
}

function readInt(value: unknown, fallback: number): number {
	return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
}

export function redactWorkoutPlanRequestForLogging(body: TaiInterpretWorkoutPlanRequest) {
	const attachment = body.source.attachment;
	return {
		schemaVersion: body.schemaVersion,
		sourceType: body.source.type,
		hasText: Boolean(body.source.text?.trim()),
		textLength: body.source.text?.length ?? 0,
		hasAttachment: Boolean(attachment?.base64Data),
		mimeType: attachment?.mimeType ?? null,
		attachmentByteSize: attachment?.base64Data?.length ?? 0,
		knownExerciseCount: body.context?.knownExercises?.length ?? 0,
	};
}

export function validateWorkoutPlanRequest(body: TaiInterpretWorkoutPlanRequest): string | null {
	if (body.schemaVersion !== 1) return "unsupported_schema_version";
	if (!SUPPORTED_SOURCE_TYPES.has(body.source.type)) return "unsupported_source_type";
	if (body.source.type === "text") {
		const text = body.source.text?.trim() ?? "";
		if (!text) return "text_required";
		if (text.length > MAX_TEXT_CHARS) return "payload_too_large";
		return null;
	}
	const attachment = body.source.attachment;
	const b64 = attachment?.base64Data?.trim();
	if (!b64) return "attachment_required";
	const mime = attachment?.mimeType?.trim() ?? "";
	if (!mime || !SUPPORTED_FILE_MIMES.has(mime)) return "unsupported_mime_type";
	return null;
}

export function mapProviderStructuredToWorkoutPlanResponse(
	providerJson: unknown
): TaiInterpretWorkoutPlanResponse | null {
	const root = asRecord(providerJson);
	if (!root) return null;
	const suggested = asRecord(root.suggestedPlan);
	if (!suggested) return null;
	const sectionsRaw = suggested.sections;
	if (!Array.isArray(sectionsRaw)) return null;
	const sections = [];
	for (const sectionValue of sectionsRaw) {
		const section = asRecord(sectionValue);
		if (!section) return null;
		const name = readString(section.name);
		if (name === undefined) return null;
		const exercisesRaw = section.exercises;
		if (!Array.isArray(exercisesRaw)) return null;
		const exercises = [];
		for (const exerciseValue of exercisesRaw) {
			const exercise = asRecord(exerciseValue);
			if (!exercise) return null;
			const sourceName = readString(exercise.sourceName);
			const displayName = readString(exercise.displayName);
			if (sourceName === undefined || displayName === undefined) return null;
			exercises.push({
				sourceName,
				matchedExerciseID: readString(exercise.matchedExerciseID) ?? null,
				displayName,
				orderIndex: readInt(exercise.orderIndex, exercises.length),
				targetSets: typeof exercise.targetSets === "number" ? readInt(exercise.targetSets, 3) : null,
				minimumRepetitions:
					typeof exercise.minimumRepetitions === "number"
						? readInt(exercise.minimumRepetitions, 8)
						: null,
				maximumRepetitions:
					typeof exercise.maximumRepetitions === "number"
						? readInt(exercise.maximumRepetitions, 12)
						: null,
				isOptional: exercise.isOptional === true,
				notes: readString(exercise.notes) ?? null,
				matchConfidence: typeof exercise.matchConfidence === "number" ? exercise.matchConfidence : 0,
			});
		}
		sections.push({
			name,
			orderIndex: readInt(section.orderIndex, sections.length),
			exercises,
		});
	}
	const unresolvedRaw = root.unresolvedItems;
	const unresolvedItems = Array.isArray(unresolvedRaw)
		? unresolvedRaw.flatMap((item) => {
				const record = asRecord(item);
				if (!record) return [];
				const sourceText = readString(record.sourceText);
				const reason = readString(record.reason);
				if (sourceText === undefined || reason === undefined) return [];
				const suggestedMatches = Array.isArray(record.suggestedMatches)
					? record.suggestedMatches.flatMap((match) => {
							const m = asRecord(match);
							const exerciseID = m ? readString(m.exerciseID) : undefined;
							if (!exerciseID) return [];
							return [
								{
									exerciseID,
									confidence: typeof m?.confidence === "number" ? m.confidence : 0,
								},
							];
						})
					: [];
				return [{ sourceText, reason, suggestedMatches }];
			})
		: [];

	return {
		schemaVersion: readInt(root.schemaVersion, 1),
		suggestedPlan: {
			name: readString(suggested.name) ?? "Imported Workout Plan",
			sections,
			generalInstructions: Array.isArray(suggested.generalInstructions)
				? suggested.generalInstructions.filter((v): v is string => typeof v === "string")
				: [],
			suggestedDurationWeeks:
				typeof suggested.suggestedDurationWeeks === "number"
					? readInt(suggested.suggestedDurationWeeks, 4)
					: null,
		},
		unresolvedItems,
		warnings: Array.isArray(root.warnings)
			? root.warnings.filter((v): v is string => typeof v === "string")
			: [],
		confidence: readString(root.confidence) ?? "medium",
		requiresUserConfirmation: root.requiresUserConfirmation !== false,
	};
}

export function filterUnknownExerciseIDs(
	payload: TaiInterpretWorkoutPlanResponse,
	knownExerciseIDs: Set<string>
): TaiInterpretWorkoutPlanResponse {
	const sections = payload.suggestedPlan.sections.map((section) => ({
		...section,
		exercises: section.exercises.map((exercise) => {
			if (!exercise.matchedExerciseID) return exercise;
			if (knownExerciseIDs.has(exercise.matchedExerciseID)) return exercise;
			return {
				...exercise,
				matchedExerciseID: null,
				matchConfidence: Math.min(exercise.matchConfidence, 0.5),
			};
		}),
	}));
	return {
		...payload,
		suggestedPlan: { ...payload.suggestedPlan, sections },
	};
}

export function buildWorkoutPlanSystemPrompt(): string {
	return [
		"You interpret trainer workout program documents into structured JSON.",
		"Preserve trainer exercise wording in sourceName.",
		"Match exercises to known catalog IDs when confident.",
		"Represent optional exercises explicitly.",
		"Extract sections/days, sets, rep ranges, and general instructions.",
		"Return schemaVersion 1 JSON only.",
		"Never persist or echo raw attachments.",
	].join(" ");
}

const workoutPlanExerciseSchema = {
	type: "object",
	additionalProperties: false,
	properties: {
		sourceName: { type: "string" },
		matchedExerciseID: { type: ["string", "null"] },
		displayName: { type: "string" },
		orderIndex: { type: "integer" },
		targetSets: { type: ["integer", "null"] },
		minimumRepetitions: { type: ["integer", "null"] },
		maximumRepetitions: { type: ["integer", "null"] },
		isOptional: { type: "boolean" },
		notes: { type: ["string", "null"] },
		matchConfidence: { type: "number" },
	},
	required: [
		"sourceName",
		"matchedExerciseID",
		"displayName",
		"orderIndex",
		"targetSets",
		"minimumRepetitions",
		"maximumRepetitions",
		"isOptional",
		"notes",
		"matchConfidence",
	],
} as const;

const workoutPlanSectionSchema = {
	type: "object",
	additionalProperties: false,
	properties: {
		name: { type: "string" },
		orderIndex: { type: "integer" },
		exercises: {
			type: "array",
			items: workoutPlanExerciseSchema,
		},
	},
	required: ["name", "orderIndex", "exercises"],
} as const;

const workoutPlanMatchSuggestionSchema = {
	type: "object",
	additionalProperties: false,
	properties: {
		exerciseID: { type: "string" },
		confidence: { type: "number" },
	},
	required: ["exerciseID", "confidence"],
} as const;

const workoutPlanUnresolvedItemSchema = {
	type: "object",
	additionalProperties: false,
	properties: {
		sourceText: { type: "string" },
		reason: { type: "string" },
		suggestedMatches: {
			type: "array",
			items: workoutPlanMatchSuggestionSchema,
		},
	},
	required: ["sourceText", "reason", "suggestedMatches"],
} as const;

/** JSON Schema for Responses API structured outputs (`strict: true`). Matches app contract camelCase keys. */
export const TAI_WORKOUT_PLAN_RESPONSE_JSON_SCHEMA = {
	type: "object",
	additionalProperties: false,
	properties: {
		schemaVersion: { type: "integer" },
		suggestedPlan: {
			type: "object",
			additionalProperties: false,
			properties: {
				name: { type: "string" },
				sections: {
					type: "array",
					items: workoutPlanSectionSchema,
				},
				generalInstructions: {
					type: "array",
					items: { type: "string" },
				},
				suggestedDurationWeeks: { type: ["integer", "null"] },
			},
			required: ["name", "sections", "generalInstructions", "suggestedDurationWeeks"],
		},
		unresolvedItems: {
			type: "array",
			items: workoutPlanUnresolvedItemSchema,
		},
		warnings: {
			type: "array",
			items: { type: "string" },
		},
		confidence: { type: "string" },
		requiresUserConfirmation: { type: "boolean" },
	},
	required: [
		"schemaVersion",
		"suggestedPlan",
		"unresolvedItems",
		"warnings",
		"confidence",
		"requiresUserConfirmation",
	],
} as const;
