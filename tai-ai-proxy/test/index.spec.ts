import {
	env,
	createExecutionContext,
	waitOnExecutionContext,
	SELF,
} from "cloudflare:test";
import { describe, it, expect } from "vitest";
import worker, { __test } from "../src/index";

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
										label: "tomato-based beef dish with unknown starch",
										timing: "dinner",
										eatenAtGuessISO8601: "",
										items: [
											{
												name: "beef mince and sausage in sauce",
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
										alternatives: ["beef pasta", "beef stew", "meat sauce with rice"],
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
		expect(mapped?.interpretedMeals[0].label).toEqual("tomato-based beef dish with unknown starch");
		expect(mapped?.interpretedMeals[0].alternatives).toEqual(["beef pasta", "beef stew", "meat sauce with rice"]);
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
										label: "mixed meat and sauce dish",
										timing: "dinner",
										eatenAtGuessISO8601: "",
										items: [
											{
												name: "mixed meat dish",
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
										alternatives: ["meat sauce with rice"],
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
		expect(mapped?.interpretedMeals[0].label).toEqual("mixed meat and sauce dish");
		expect(mapped?.interpretedMeals[0].alternatives).toEqual(["meat sauce with rice"]);
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

	it("prompt enforces cautious, observation-first behavior for uncertainty", () => {
		const prompt = __test.buildSystemPrompt();
		expect(prompt).toContain("Follow this order");
		expect(prompt).toContain("Do not guess a specific dish");
		expect(prompt).toContain("diverse alternatives");
		expect(prompt).toContain("Confidence must reflect uncertainty honestly");
	});
});
