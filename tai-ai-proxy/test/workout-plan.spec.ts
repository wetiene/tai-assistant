import {
	env,
	createExecutionContext,
	waitOnExecutionContext,
} from "cloudflare:test";
import { describe, it, expect, vi, afterEach } from "vitest";
import worker, { __test } from "../src/index";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

const TRAINER_FIXTURE_TEXT = `Upper Body:
- Supine Chest Press
- Seated Shoulder Press
- Reverse Grip Lat Pulldown
- Seated Row
- optional Bicep Curl
- optional Tricep Pushdown

Lower Body:
- Leg Press
- Kettlebell Squats
- Stationary Lunges
- Glute Trainer
- optional Leg Extension
- optional Leg Curl

3 sets
8-12 repetitions
Work close to fatigue while maintaining good form.`;

function trainerProviderPayload(overrides: Record<string, unknown> = {}) {
	return {
		output: [
			{
				content: [
					{
						type: "output_text",
						text: JSON.stringify({
							schemaVersion: 1,
							suggestedPlan: {
								name: "Trainer Program – July 2026",
								sections: [
									{
										name: "Upper Body",
										orderIndex: 0,
										exercises: [
											exercise("Supine Chest Press", "supineChestPress", 0),
											exercise("Seated Shoulder Press", "seatedShoulderPress", 1),
											exercise("Reverse Grip Lat Pulldown", "reverseGripLatPulldown", 2),
											exercise("Seated Row", "seatedRow", 3),
											exercise("Bicep Curl", "bicepCurl", 4, true),
											exercise("Tricep Pushdown", "tricepPushdown", 5, true),
										],
									},
									{
										name: "Lower Body",
										orderIndex: 1,
										exercises: [
											exercise("Leg Press", "legPress", 0),
											exercise("Kettlebell Squats", "kettlebellSquats", 1),
											exercise("Stationary Lunges", "stationaryLunges", 2),
											exercise("Glute Trainer", "gluteTrainer", 3),
											exercise("Leg Extension", "legExtension", 4, true),
											exercise("Leg Curl", "legCurl", 5, true),
										],
									},
								],
								generalInstructions: [
									"Complete 3 sets per exercise",
									"Aim for 8–12 repetitions",
									"Work close to fatigue while maintaining good form",
								],
								suggestedDurationWeeks: 4,
							},
							unresolvedItems: [
								{
									sourceText: "Glute Trainer",
									reason: "No exact exercise catalog match",
									suggestedMatches: [{ exerciseID: "gluteDrive", confidence: 0.63 }],
								},
							],
							warnings: [],
							confidence: "high",
							requiresUserConfirmation: true,
							...overrides,
						}),
					},
				],
			},
		],
	};
}

function exercise(
	sourceName: string,
	matchedExerciseID: string,
	orderIndex: number,
	isOptional = false,
	sets = 3,
	minReps = 8,
	maxReps = 12
) {
	return {
		sourceName,
		matchedExerciseID,
		displayName: sourceName,
		orderIndex,
		targetSets: sets,
		minimumRepetitions: minReps,
		maximumRepetitions: maxReps,
		isOptional,
		notes: null,
		matchConfidence: 0.98,
	};
}

function textRequestBody(overrides: Record<string, unknown> = {}) {
	return {
		schemaVersion: 1,
		source: { type: "text", text: TRAINER_FIXTURE_TEXT },
		context: {
			localeIdentifier: "en_AU",
			preferredWeightUnit: "kg",
			knownExercises: [
				{ id: "supineChestPress", name: "Supine Chest Press" },
				{ id: "legPress", name: "Leg Press" },
			],
		},
		...overrides,
	};
}

function mappedFromProvider(overrides: Record<string, unknown> = {}) {
	const payload = trainerProviderPayload(overrides);
	const text = (payload as { output: Array<{ content: Array<{ text: string }> }> }).output[0].content[0].text;
	return __test.mapProviderStructuredToWorkoutPlanResponse(JSON.parse(text))!;
}

describe("interpret-workout-plan mapping", () => {
	it("parses valid trainer fixture with two sections", () => {
		const mapped = mappedFromProvider();
		expect(mapped.schemaVersion).toBe(1);
		expect(mapped.suggestedPlan.sections).toHaveLength(2);
		expect(mapped.suggestedPlan.sections[0].name).toBe("Upper Body");
		expect(mapped.suggestedPlan.sections[1].exercises[3].sourceName).toBe("Glute Trainer");
		expect(mapped.suggestedPlan.generalInstructions.length).toBeGreaterThan(0);
		expect(mapped.requiresUserConfirmation).toBe(true);
	});

	it("preserves optional exercises and global prescription", () => {
		const mapped = mappedFromProvider();
		const upper = mapped.suggestedPlan.sections[0];
		expect(upper.exercises[4].isOptional).toBe(true);
		expect(upper.exercises[0].targetSets).toBe(3);
		expect(upper.exercises[0].minimumRepetitions).toBe(8);
		expect(upper.exercises[0].maximumRepetitions).toBe(12);
	});

	it("applies per-exercise prescription overrides", () => {
		const mapped = mappedFromProvider();
		mapped.suggestedPlan.sections[0].exercises[0].targetSets = 4;
		mapped.suggestedPlan.sections[0].exercises[0].minimumRepetitions = 5;
		mapped.suggestedPlan.sections[0].exercises[0].maximumRepetitions = 7;
		expect(mapped.suggestedPlan.sections[0].exercises[0].targetSets).toBe(4);
	});

	it("filters unknown AI exercise IDs from known catalog", () => {
		const mapped = mappedFromProvider();
		const known = new Set(["supineChestPress", "legPress"]);
		const filtered = __test.filterUnknownExerciseIDs(mapped, known);
		expect(filtered.suggestedPlan.sections[0].exercises[0].matchedExerciseID).toBe("supineChestPress");
		expect(filtered.suggestedPlan.sections[0].exercises[1].matchedExerciseID).toBeNull();
	});

	it("returns null for malformed provider JSON", () => {
		expect(__test.mapProviderStructuredToWorkoutPlanResponse({ output: [] })).toBeNull();
		expect(__test.mapProviderStructuredToWorkoutPlanResponse({ suggestedPlan: "bad" })).toBeNull();
	});

	it("redacts source text and attachment from logging metadata", () => {
		const redacted = __test.redactWorkoutPlanRequestForLogging(textRequestBody() as never);
		expect(redacted.sourceType).toBe("text");
		expect(redacted.hasText).toBe(true);
		expect(JSON.stringify(redacted)).not.toContain("Supine Chest Press");
		expect(JSON.stringify(redacted)).not.toContain("base64Data");
	});

	it("redacts image attachment payload from logging metadata", () => {
		const redacted = __test.redactWorkoutPlanRequestForLogging({
			schemaVersion: 1,
			source: {
				type: "image",
				attachment: { base64Data: "aGVsbG8=", mimeType: "image/jpeg" },
			},
			context: { knownExercises: [] },
		});
		expect(redacted.hasAttachment).toBe(true);
		expect(JSON.stringify(redacted)).not.toContain("aGVsbG8=");
	});
});

describe("validateWorkoutPlanRequest", () => {
	it("rejects unsupported schema version", () => {
		expect(__test.validateWorkoutPlanRequest({ ...textRequestBody(), schemaVersion: 2 } as never)).toBe(
			"unsupported_schema_version"
		);
	});

	it("rejects oversized text", () => {
		expect(
			__test.validateWorkoutPlanRequest({
				schemaVersion: 1,
				source: { type: "text", text: "x".repeat(33_000) },
			} as never)
		).toBe("payload_too_large");
	});

	it("rejects unsupported mime type", () => {
		expect(
			__test.validateWorkoutPlanRequest({
				schemaVersion: 1,
				source: {
					type: "image",
					attachment: { base64Data: "aGVsbG8=", mimeType: "image/gif" },
				},
			} as never)
		).toBe("unsupported_mime_type");
	});

	it("accepts valid pasted text", () => {
		expect(__test.validateWorkoutPlanRequest(textRequestBody() as never)).toBeNull();
	});
});

describe("POST /ai/interpret-workout-plan", () => {
	afterEach(() => {
		vi.restoreAllMocks();
	});

	it("returns method_not_allowed for GET", async () => {
		const request = new IncomingRequest("http://example.com/ai/interpret-workout-plan", { method: "GET" });
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(405);
	});

	it("returns unauthorized without bearer token", async () => {
		const request = new IncomingRequest("http://example.com/ai/interpret-workout-plan", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(textRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(401);
	});

	it("returns text_required when text missing", async () => {
		const request = new IncomingRequest("http://example.com/ai/interpret-workout-plan", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify({ schemaVersion: 1, source: { type: "text", text: "  " } }),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(400);
		expect(await response.json()).toEqual({ error: "text_required" });
	});

	it("returns structured interpretation on provider success", async () => {
		vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
			new Response(JSON.stringify(trainerProviderPayload()), { status: 200 })
		);

		const request = new IncomingRequest("http://example.com/ai/interpret-workout-plan", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(textRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		const body = (await response.json()) as {
			suggestedPlan: { sections: Array<{ name: string }> };
			requiresUserConfirmation: boolean;
		};
		expect(body.suggestedPlan.sections).toHaveLength(2);
		expect(body.requiresUserConfirmation).toBe(true);
	});

	it("returns ai_provider_error on provider failure", async () => {
		vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
			new Response("upstream failed", { status: 503 })
		);

		const request = new IncomingRequest("http://example.com/ai/interpret-workout-plan", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(textRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(502);
		const body = (await response.json()) as { error: { code: string } };
		expect(body.error.code).toBe("provider_error");
	});

	it("returns malformed_ai_response when provider JSON is invalid", async () => {
		vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
			new Response(JSON.stringify({ output: [{ content: [{ type: "output_text", text: "not json" }] }] }), {
				status: 200,
			})
		);

		const request = new IncomingRequest("http://example.com/ai/interpret-workout-plan", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(textRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(502);
		const body = (await response.json()) as { error: { code: string } };
		expect(body.error.code).toBe("malformed_ai_response");
	});

	it("does not persist anything in the worker response", async () => {
		vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
			new Response(JSON.stringify(trainerProviderPayload()), { status: 200 })
		);
		const request = new IncomingRequest("http://example.com/ai/interpret-workout-plan", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(textRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.headers.get("Set-Cookie")).toBeNull();
		expect(response.headers.get("x-persisted-plan-id")).toBeNull();
	});
});
