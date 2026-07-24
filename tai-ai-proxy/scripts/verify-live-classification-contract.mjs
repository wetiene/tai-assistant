#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const proxyBase = "https://tai-ai-proxy.taiassistant.workers.dev";
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const secretsPath = path.resolve(scriptDir, "../../TaiAssistant/Config/Secrets.xcconfig");

// Tiny embedded JPEG (red 2x2) — no external assets.
const TINY_JPEG_BASE64 =
	"/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAACAAIDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAB//2Q==";

function readToken() {
	const envToken = process.env.TAI_AI_PROXY_BEARER_TOKEN?.trim();
	if (envToken) return envToken;
	if (!fs.existsSync(secretsPath)) return null;
	const line = fs
		.readFileSync(secretsPath, "utf8")
		.split("\n")
		.find((row) => row.startsWith("AI_PROXY_BEARER_TOKEN"));
	if (!line) return null;
	const value = line.split("=").slice(1).join("=").trim();
	return value && value !== "your_proxy_token_here" ? value : null;
}

async function post(pathname, body, token) {
	const response = await fetch(`${proxyBase}${pathname}`, {
		method: "POST",
		headers: {
			Authorization: `Bearer ${token}`,
			"Content-Type": "application/json",
		},
		body: JSON.stringify(body),
	});
	const text = await response.text();
	let json = null;
	try {
		json = JSON.parse(text);
	} catch {
		json = { parseError: true, preview: text.slice(0, 200) };
	}
	return { status: response.status, json };
}

function sanitizeMeal(json) {
	return {
		contentType: json?.contentType ?? null,
		classificationConfidence: json?.classificationConfidence ?? null,
		containsFood: json?.containsFood ?? null,
		containsGymEquipment: json?.containsGymEquipment ?? null,
		mealCount: Array.isArray(json?.interpretedMeals) ? json.interpretedMeals.length : 0,
		firstMealLabel: json?.interpretedMeals?.[0]?.label ?? null,
	};
}

function sanitizeGym(json) {
	return {
		contentType: json?.contentType ?? null,
		classificationConfidence: json?.classificationConfidence ?? null,
		containsFood: json?.containsFood ?? null,
		containsGymEquipment: json?.containsGymEquipment ?? null,
		exerciseCandidates: (json?.exerciseCandidates ?? []).map((c) => c.exerciseID),
		detectedWeight: json?.detectedWeight?.value ?? null,
		limitations: json?.limitations ?? [],
	};
}

const token = readToken();
if (!token) {
	console.log(JSON.stringify({ blocked: true, reason: "missing_proxy_token" }, null, 2));
	process.exit(2);
}

const gymContext = {
	localeIdentifier: "en_AU",
	weightUnitPreference: "kg",
	plannedWorkout: {
		templateID: "starter.lowerBody",
		title: "Lower Body",
		exercises: [
			{ exerciseID: "legPress", displayName: "Leg Press", isOptional: false },
			{ exerciseID: "legExtension", displayName: "Leg Extension", isOptional: false },
		],
	},
	expectedExerciseID: "legPress",
	allowedExerciseCandidates: [
		{ exerciseID: "legPress", displayName: "Leg Press", isOptional: false },
		{ exerciseID: "legExtension", displayName: "Leg Extension", isOptional: false },
	],
};

const mealContext = {
	ownerID: "live.contract.verify",
	localeIdentifier: "en_AU",
	timeZoneIdentifier: "Australia/Sydney",
};

const imageInput = { base64Data: TINY_JPEG_BASE64, mimeType: "image/jpeg" };

const scenarios = [
	{
		name: "meal_via_gym_photo",
		path: "/ai/interpret-gym-photo",
		body: { image: imageInput, context: gymContext },
		sanitize: sanitizeGym,
	},
	{
		name: "gym_via_meal_photo",
		path: "/ai/interpret-meal",
		body: { image: imageInput, context: mealContext },
		sanitize: sanitizeMeal,
	},
	{
		name: "gym_unreadable_weight",
		path: "/ai/interpret-gym-photo",
		body: { image: imageInput, context: gymContext },
		sanitize: sanitizeGym,
	},
	{
		name: "ambiguous_image",
		path: "/ai/interpret-gym-photo",
		body: { image: imageInput, context: gymContext },
		sanitize: sanitizeGym,
	},
	{
		name: "unsupported_image",
		path: "/ai/interpret-gym-photo",
		body: { image: imageInput, context: gymContext },
		sanitize: sanitizeGym,
	},
];

const results = [];
for (const scenario of scenarios) {
	const result = await post(scenario.path, scenario.body, token);
	results.push({
		scenario: scenario.name,
		status: result.status,
		fields: scenario.sanitize(result.json),
	});
}

console.log(JSON.stringify({ blocked: false, proxyBase, results }, null, 2));
