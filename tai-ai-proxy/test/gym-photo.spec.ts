import {
	env,
	createExecutionContext,
	waitOnExecutionContext,
} from "cloudflare:test";
import { describe, it, expect, vi, afterEach } from "vitest";
import worker, { __test } from "../src/index";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

function gymProviderPayload(overrides: Record<string, unknown> = {}) {
	return {
		output: [
			{
				content: [
					{
						type: "output_text",
						text: JSON.stringify({
							schemaVersion: 1,
							exerciseCandidates: [
								{
									exerciseID: "legPress",
									confidence: 0.88,
									reason: "Selector matches leg press stack",
								},
							],
							detectedWeight: {
								value: 80,
								unit: "kg",
								confidence: 0.74,
								reason: "Pin aligned with 80 kg plate",
							},
							limitations: ["Confirm before saving"],
							requiresConfirmation: true,
							contentType: "gymEquipment",
							classificationConfidence: 0.9,
							classificationReason: "Leg press machine visible.",
							containsFood: false,
							containsGymEquipment: true,
							...overrides,
						}),
					},
				],
			},
		],
	};
}

function gymRequestBody(overrides: Record<string, unknown> = {}) {
	return {
		image: { base64Data: "aGVsbG8=", mimeType: "image/jpeg" },
		context: {
			expectedExerciseID: "legPress",
			allowedExerciseCandidates: [
				{ exerciseID: "legPress", displayName: "Leg Press", isOptional: false },
				{ exerciseID: "legExtension", displayName: "Leg Extension", isOptional: false },
			],
		},
		...overrides,
	};
}

describe("interpret-gym-photo mapping", () => {
	it("parses valid structured response", () => {
		const mapped = __test.mapProviderStructuredToGymPhotoResponse(gymProviderPayload());
		expect(mapped).not.toBeNull();
		expect(mapped?.schemaVersion).toBe(1);
		expect(mapped?.exerciseCandidates[0].exerciseID).toBe("legPress");
		expect(mapped?.detectedWeight?.value).toBe(80);
		expect(mapped?.requiresConfirmation).toBe(true);
	});

	it("filters unknown exercise IDs from allowed template candidates", () => {
		const payload = __test.mapProviderStructuredToGymPhotoResponse(
			gymProviderPayload({
				exerciseCandidates: [
					{ exerciseID: "legPress", confidence: 0.7, reason: "ok" },
					{ exerciseID: "unknownMachine", confidence: 0.95, reason: "bad" },
				],
			})
		)!;
		const allowed = __test.readAllowedExerciseIDsFromContext({
			allowedExerciseCandidates: [{ exerciseID: "legPress" }],
		});
		const filtered = __test.filterGymExerciseCandidates(payload, allowed);
		expect(filtered.exerciseCandidates.map((c) => c.exerciseID)).toEqual(["legPress"]);
		expect(filtered.requiresConfirmation).toBe(true);
	});

	it("preserves ambiguous candidates when all are allowed", () => {
		const payload = __test.mapProviderStructuredToGymPhotoResponse(
			gymProviderPayload({
				exerciseCandidates: [
					{ exerciseID: "legPress", confidence: 0.52, reason: "Could be leg press" },
					{ exerciseID: "legExtension", confidence: 0.48, reason: "Could be extension" },
				],
			})
		)!;
		const allowed = __test.readAllowedExerciseIDsFromContext(gymRequestBody().context as Record<string, unknown>);
		const filtered = __test.filterGymExerciseCandidates(payload, allowed);
		expect(filtered.exerciseCandidates).toHaveLength(2);
	});

	it("accepts unreadable weight as null", () => {
		const mapped = __test.mapProviderStructuredToGymPhotoResponse(
			gymProviderPayload({ detectedWeight: null, limitations: ["Weight label obscured"] })
		);
		expect(mapped?.detectedWeight).toBeNull();
		expect(mapped?.limitations).toContain("Weight label obscured");
	});

	it("preserves low-confidence weight in proxy payload for client-side filtering", () => {
		const mapped = __test.mapProviderStructuredToGymPhotoResponse(
			gymProviderPayload({
				detectedWeight: {
					value: 80,
					unit: "kg",
					confidence: 0.2,
					reason: "Pin position unclear",
				},
			})
		);
		expect(mapped?.detectedWeight?.value).toBe(80);
		expect(mapped?.detectedWeight?.confidence).toBe(0.2);
	});

	it("returns null for malformed provider response", () => {
		expect(__test.mapProviderStructuredToGymPhotoResponse({ output: [] })).toBeNull();
		expect(
			__test.mapProviderStructuredToGymPhotoResponse(
				gymProviderPayload({ exerciseCandidates: "not-an-array" })
			)
		).toBeNull();
	});

	it("reads custom response schema version", () => {
		const mapped = __test.mapProviderStructuredToGymPhotoResponse(gymProviderPayload({ schemaVersion: 1 }));
		expect(mapped?.schemaVersion).toBe(1);
	});

	it("gym response JSON schema requires schemaVersion and candidates", () => {
		const schema = __test.TAI_GYM_PHOTO_RESPONSE_JSON_SCHEMA as {
			required: string[];
		};
		expect(schema.required).toContain("schemaVersion");
		expect(schema.required).toContain("exerciseCandidates");
		expect(schema.required).toContain("detectedWeight");
	});

	it("redacts image payload from logging metadata", () => {
		const redacted = __test.redactGymPhotoRequestForLogging(gymRequestBody());
		expect(redacted.hasImage).toBe(true);
		expect(JSON.stringify(redacted)).not.toContain("aGVsbG8=");
		expect(JSON.stringify(redacted)).not.toContain("base64Data");
	});
});

describe("POST /ai/interpret-gym-photo", () => {
	afterEach(() => {
		vi.restoreAllMocks();
	});

	it("returns method_not_allowed for GET", async () => {
		const request = new IncomingRequest("http://example.com/ai/interpret-gym-photo", { method: "GET" });
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(405);
		expect(await response.json()).toEqual({ error: "method_not_allowed" });
	});

	it("returns unauthorized without bearer token", async () => {
		const request = new IncomingRequest("http://example.com/ai/interpret-gym-photo", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(gymRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(401);
		expect(await response.json()).toEqual({ error: "unauthorized" });
	});

	it("returns image_required when base64 missing", async () => {
		const request = new IncomingRequest("http://example.com/ai/interpret-gym-photo", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify({ context: gymRequestBody().context }),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(400);
		expect(await response.json()).toEqual({ error: "image_required" });
	});

	it("returns structured interpretation on provider success", async () => {
		vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
			new Response(JSON.stringify(gymProviderPayload()), { status: 200 })
		);

		const request = new IncomingRequest("http://example.com/ai/interpret-gym-photo", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(gymRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		const body = (await response.json()) as {
			schemaVersion: number;
			exerciseCandidates: Array<{ exerciseID: string }>;
			requiresConfirmation: boolean;
		};
		expect(body.schemaVersion).toBe(1);
		expect(body.exerciseCandidates[0].exerciseID).toBe("legPress");
		expect(body.requiresConfirmation).toBe(true);
	});

	it("filters unknown exercise IDs in HTTP response", async () => {
		vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
			new Response(
				JSON.stringify(
					gymProviderPayload({
						exerciseCandidates: [
							{ exerciseID: "legPress", confidence: 0.6, reason: "maybe" },
							{ exerciseID: "mysteryMachine", confidence: 0.99, reason: "reject" },
						],
					})
				),
				{ status: 200 }
			)
		);

		const request = new IncomingRequest("http://example.com/ai/interpret-gym-photo", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(gymRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);

		const body = (await response.json()) as { exerciseCandidates: Array<{ exerciseID: string }> };
		expect(body.exerciseCandidates.map((c) => c.exerciseID)).toEqual(["legPress"]);
	});

	it("returns malformed_ai_response when provider JSON cannot be mapped", async () => {
		vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
			new Response(JSON.stringify({ output: [] }), { status: 200 })
		);

		const request = new IncomingRequest("http://example.com/ai/interpret-gym-photo", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(gymRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(502);
		expect(await response.json()).toEqual({ error: "malformed_ai_response" });
	});

	it("returns ai_provider_error when OpenAI HTTP fails", async () => {
		vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
			new Response("rate limited", { status: 429 })
		);

		const request = new IncomingRequest("http://example.com/ai/interpret-gym-photo", {
			method: "POST",
			headers: {
				Authorization: `Bearer ${env.TAI_PROXY_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify(gymRequestBody()),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(502);
		const body = (await response.json()) as { error: string; status: number };
		expect(body.error).toBe("ai_provider_error");
		expect(body.status).toBe(429);
	});
});
