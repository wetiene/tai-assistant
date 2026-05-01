import {
	env,
	createExecutionContext,
	waitOnExecutionContext,
	SELF,
} from "cloudflare:test";
import { describe, it, expect } from "vitest";
import worker, { __test, type TaiInterpretMealRequest } from "../src/index";

// For now, you'll need to do something like this to get a correctly-typed
// `Request` to pass to `worker.fetch()`.
const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

describe("worker routing", () => {
	it("returns not_found for unknown paths (unit style)", async () => {
		const request = new IncomingRequest("http://example.com/");
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(404);
		expect(await response.json()).toEqual({ error: "not_found" });
	});

	it("returns not_found for unknown paths (integration style)", async () => {
		const response = await SELF.fetch("https://example.com/");
		expect(response.status).toBe(404);
		expect(await response.json()).toEqual({ error: "not_found" });
	});
});

describe("interpretation schema + mapping", () => {
	it("parses alternatives and core meal fields from structured output", () => {
		const providerPayload = {
			output: [
				{
					content: [
						{
							type: "output_text",
							text: JSON.stringify({
								interpretedMeals: [
									{
										label: "Composite dish with unresolved base component",
										timing: "dinner",
										eatenAtGuessISO8601: "",
										items: [
											{
												name: "Primary component in sauce",
												amount: 1,
												unit: "serving",
												calories: 620,
												proteinGrams: 35,
												carbsGrams: 42,
												fatGrams: 30,
												fiberGrams: 4,
											},
										],
										calories: 620,
										proteinGrams: 35,
										carbsGrams: 42,
										fatGrams: 30,
										confidence: 0.46,
										alternatives: ["Alternative label A", "Alternative label B", "Alternative label C"],
									},
								],
								uiNotes: "",
								confidence: 0.46,
							}),
						},
					],
				},
			],
		};

		const mapped = __test.mapProviderStructuredToAppResponse(providerPayload);
		expect(mapped).not.toBeNull();
		expect(mapped?.interpretedMeals[0].label).toEqual("Composite dish with unresolved base component");
		expect(mapped?.interpretedMeals[0].alternatives).toEqual([
			"Alternative label A",
			"Alternative label B",
			"Alternative label C",
		]);
	});

	it("parses core fields safely when optional arrays are absent", () => {
		const providerPayload = {
			output: [
				{
					content: [
						{
							type: "output_text",
							text: JSON.stringify({
								interpretedMeals: [
									{
										label: "Single ambiguous meal bucket",
										timing: "dinner",
										eatenAtGuessISO8601: "",
										items: [
											{
												name: "Line item aggregate",
												amount: 1,
												unit: "serving",
												calories: 550,
												proteinGrams: 28,
												carbsGrams: 30,
												fatGrams: 29,
												fiberGrams: 3,
											},
										],
										calories: 550,
										proteinGrams: 28,
										carbsGrams: 30,
										fatGrams: 29,
										confidence: 0.38,
										alternatives: ["Alternate interpretation"],
									},
								],
								uiNotes: "",
								confidence: 0.38,
							}),
						},
					],
				},
			],
		};

		const mapped = __test.mapProviderStructuredToAppResponse(providerPayload);
		expect(mapped).not.toBeNull();
		expect(mapped?.interpretedMeals[0].label).toEqual("Single ambiguous meal bucket");
		expect(mapped?.interpretedMeals[0].alternatives).toEqual(["Alternate interpretation"]);
	});

	it("schema keeps strict required list aligned with remaining fields", () => {
		const schema = __test.TAI_MEAL_RESPONSE_JSON_SCHEMA as {
			properties: {
				interpretedMeals: { items: { required: string[] } };
			};
		};
		const required = schema.properties.interpretedMeals.items.required;
		expect(required).toContain("label");
		expect(required).toContain("timing");
		expect(required).toContain("alternatives");
		expect(required).not.toContain("visibleIngredients");
		expect(required).not.toContain("uncertainIngredients");
		expect(required).not.toContain("possibleStarches");
	});

	it("prompt encodes user-led priority, portion scaling, and concise tone", () => {
		const prompt = __test.buildSystemPrompt();
		expect(prompt).toContain("Tone:");
		expect(prompt).toContain("Instruction priority");
		expect(prompt).toContain("Latest user message");
		expect(prompt).toContain("mealRefinement");
		expect(prompt).toContain("When user text conflicts with the image");
		expect(prompt).toContain("Portion / quantity");
		expect(prompt).toContain("uiNotes");
		expect(prompt).toContain("obedience to instructions is not the same as visual certainty");
	});

	it("parses mealRefinement from iOS-style context", () => {
		const payload = __test.parseMealRefinementFromContext({
			mealRefinement: {
				meals: [
					{
						label: "Prior estimate label",
						timing: "lunch",
						calories: 500,
						proteinGrams: 20,
						carbsGrams: 60,
						fatGrams: 18,
						confidence: 0.7,
						isUserConfirmedLabel: true,
						items: [
							{
								name: "Line item A",
								amount: 150,
								unit: "g",
								calories: 200,
								proteinGrams: 4,
								carbsGrams: 44,
								fatGrams: 0.5,
								fiberGrams: 1,
							},
						],
					},
				],
				priorUserTextLines: ["Prior user thread line"],
				hasPhotoAttachment: true,
			},
		});
		expect(payload).not.toBeNull();
		expect(payload?.meals[0].label).toBe("Prior estimate label");
		expect(payload?.meals[0].isUserConfirmedLabel).toBe(true);
		expect(payload?.priorUserTextLines).toEqual(["Prior user thread line"]);
		expect(payload?.hasPhotoAttachment).toBe(true);
	});

	it("user prompt blocks surface latest text and structured prior (no schema break)", () => {
		const body: TaiInterpretMealRequest = {
			text: "Apply a portion multiplier and remove one ingredient.",
			context: {
				mealRefinement: {
					meals: [
						{
							label: "Prior estimate label",
							timing: "dinner",
							calories: 400,
							proteinGrams: 30,
							carbsGrams: 20,
							fatGrams: 15,
							confidence: 0.65,
							isUserConfirmedLabel: false,
							items: [
								{
									name: "Line item aggregate",
									amount: 1,
									unit: "serving",
									calories: 400,
									proteinGrams: 30,
									carbsGrams: 20,
									fatGrams: 15,
									fiberGrams: 2,
								},
							],
						},
					],
					priorUserTextLines: [],
					hasPhotoAttachment: true,
				},
			},
		};
		const texts = __test.collectUserTextBlocksForTests(body, undefined, "image/jpeg", false);
		const joined = texts.join("\n");
		expect(joined).toContain("highest authority");
		expect(joined).toContain("portion multiplier");
		expect(joined).toContain("Structured prior meal state");
		expect(joined).toContain("Prior estimate label");
	});
});
