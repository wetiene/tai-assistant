import Foundation

protocol AIService {
    func send(message: String, context: [String: String]) async throws -> String
    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse
    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse
    func coach(request: AICoachRequest) async throws -> AICoachResponse
}

// MARK: - Live Tai coaching (`POST /ai/coach`) — no ownerID; no meal photos

struct AICoachRequest: Codable, Sendable {
    var message: String
    var context: AICoachRequestContext?
}

struct AICoachRequestContext: Codable, Sendable {
    var localeIdentifier: String?
    var timeZoneIdentifier: String?
    var dayNutrition: AICoachDayNutritionContext?
    var mealsToday: [AICoachMealContext]
    var goal: AICoachGoalContext?
    var recentTurns: [AICoachTurnContext]
    var limitations: [String]
    var capabilityFlags: AICoachCapabilityFlags?

    init(
        localeIdentifier: String? = nil,
        timeZoneIdentifier: String? = nil,
        dayNutrition: AICoachDayNutritionContext? = nil,
        mealsToday: [AICoachMealContext] = [],
        goal: AICoachGoalContext? = nil,
        recentTurns: [AICoachTurnContext] = [],
        limitations: [String] = [],
        capabilityFlags: AICoachCapabilityFlags? = nil
    ) {
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dayNutrition = dayNutrition
        self.mealsToday = mealsToday
        self.goal = goal
        self.recentTurns = recentTurns
        self.limitations = limitations
        self.capabilityFlags = capabilityFlags
    }
}

struct AICoachDayNutritionContext: Codable, Sendable {
    var mealCount: Int
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var calorieTarget: Int?
    var proteinTarget: Double?
    var carbsTarget: Double?
    var fatTarget: Double?
}

struct AICoachMealContext: Codable, Sendable {
    var label: String
    var eatenAtISO8601: String?
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
}

struct AICoachGoalContext: Codable, Sendable {
    var title: String
    var calorieTarget: Int?
    var proteinTarget: Double?
    var carbsTarget: Double?
    var fatTarget: Double?
}

struct AICoachTurnContext: Codable, Sendable {
    var role: String
    var text: String
}

struct AICoachCapabilityFlags: Codable, Sendable {
    var hasHealthKit: Bool
    var hasWorkouts: Bool
    var hasLocation: Bool
    var hasMealMemory: Bool
}

struct AICoachResponse: Codable, Sendable {
    var assistantText: String
    var recommendation: AICoachRecommendation?
    var evidence: [AICoachEvidenceItem]
    var confidence: String
    var limitations: [String]
    var quickActions: [AICoachQuickAction]
    var requiresUserDecision: Bool
    var safety: AICoachSafety

    enum CodingKeys: String, CodingKey {
        case assistantText, recommendation, evidence, confidence, limitations
        case quickActions, requiresUserDecision, safety
    }

    init(
        assistantText: String,
        recommendation: AICoachRecommendation? = nil,
        evidence: [AICoachEvidenceItem] = [],
        confidence: String = "medium",
        limitations: [String] = [],
        quickActions: [AICoachQuickAction] = [],
        requiresUserDecision: Bool = false,
        safety: AICoachSafety = AICoachSafety(state: "ok", reason: nil)
    ) {
        self.assistantText = assistantText
        self.recommendation = recommendation
        self.evidence = evidence
        self.confidence = confidence
        self.limitations = limitations
        self.quickActions = quickActions
        self.requiresUserDecision = requiresUserDecision
        self.safety = safety
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assistantText = try container.decode(String.self, forKey: .assistantText)
        recommendation = try container.decodeIfPresent(AICoachRecommendation.self, forKey: .recommendation)
        evidence = try container.decodeIfPresent([AICoachEvidenceItem].self, forKey: .evidence) ?? []
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence) ?? "medium"
        limitations = try container.decodeIfPresent([String].self, forKey: .limitations) ?? []
        quickActions = try container.decodeIfPresent([AICoachQuickAction].self, forKey: .quickActions) ?? []
        requiresUserDecision = try container.decodeIfPresent(Bool.self, forKey: .requiresUserDecision) ?? false
        safety = try container.decodeIfPresent(AICoachSafety.self, forKey: .safety)
            ?? AICoachSafety(state: "ok", reason: nil)
    }
}

struct AICoachRecommendation: Codable, Sendable {
    var title: String
    var detail: String?
}

struct AICoachEvidenceItem: Codable, Sendable {
    var kind: String
    var label: String
    var detail: String?
}

struct AICoachQuickAction: Codable, Sendable {
    var id: String
    var title: String
}

struct AICoachSafety: Codable, Sendable {
    /// `ok` | `refuse` | `redirect`
    var state: String
    var reason: String?
}

// MARK: - Goal interpretation (`POST /ai/interpret-goal`)

struct AIInterpretGoalRequest: Codable, Sendable {
    var prompt: String
    var context: AIInterpretGoalContext?
}

struct AIInterpretGoalContext: Codable, Sendable {
    var ownerID: String?
    var localeIdentifier: String?
    var timeZoneIdentifier: String?
}

/// Mirrors the tai-ai-proxy strict JSON schema for goal interpretation.
struct AIInterpretGoalResponse: Codable, Sendable {
    var originalPrompt: String
    var goalType: String
    var title: String
    var calorieTarget: Int
    var proteinTarget: Double
    var carbsTarget: Double
    var fatTarget: Double
    var fiberTarget: Int
    var waterTarget: Int
    var activityIntent: String
    var uiNotes: String
    var confidence: Double
}

struct AIInterpretMealRequest: Codable {
    var text: String?
    var image: AIInterpretMealImageInput?
    var context: AIInterpretMealContext?
}

struct AIInterpretMealImageInput: Codable {
    var base64Data: String?
    var mimeType: String?
    var uploadReference: String?
}

/// Structured prior state for refinement rounds; consumed by `tai-ai-proxy` (`context.mealRefinement`).
struct AIProxyMealRefinementPayload: Codable, Sendable {
    struct LineItem: Codable, Sendable {
        var name: String
        var amount: Double
        var unit: String
        var calories: Int
        var proteinGrams: Double
        var carbsGrams: Double
        var fatGrams: Double
        var fiberGrams: Double
    }

    struct Meal: Codable, Sendable {
        var label: String
        var timing: String
        var calories: Int
        var proteinGrams: Double
        var carbsGrams: Double
        var fatGrams: Double
        var confidence: Double
        /// When true, treat `label` as user-authoritative unless the latest user message clearly renames the dish.
        var isUserConfirmedLabel: Bool
        var items: [LineItem]
    }

    var meals: [Meal]
    /// Older user-authored lines from the thread (excludes the message sent in `text` for this request).
    var priorUserTextLines: [String]
    var hasPhotoAttachment: Bool
}

struct AIInterpretMealContext: Codable {
    var ownerID: String?
    var localeIdentifier: String?
    var timeZoneIdentifier: String?
    var mealRefinement: AIProxyMealRefinementPayload?
}

struct AIInterpretMealResponse: Codable {
    var interpretedMeals: [AIInterpretedMeal]
    var uiNotes: String?
}

struct AIInterpretedMeal: Codable {
    var label: String
    var timing: String
    var eatenAtGuessISO8601: String?
    var items: [AIInterpretedMealItem]
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var confidence: Double
    /// Alternative meal labels when the image is ambiguous; empty when confident.
    var alternatives: [String]

    enum CodingKeys: String, CodingKey {
        case label, timing, eatenAtGuessISO8601, items, calories, proteinGrams, carbsGrams, fatGrams, confidence, alternatives
    }

    init(
        label: String,
        timing: String,
        eatenAtGuessISO8601: String?,
        items: [AIInterpretedMealItem],
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        confidence: Double,
        alternatives: [String] = []
    ) {
        self.label = label
        self.timing = timing
        self.eatenAtGuessISO8601 = eatenAtGuessISO8601
        self.items = items
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.confidence = confidence
        self.alternatives = alternatives
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        timing = try container.decode(String.self, forKey: .timing)
        eatenAtGuessISO8601 = try container.decodeIfPresent(String.self, forKey: .eatenAtGuessISO8601)
        items = try container.decode([AIInterpretedMealItem].self, forKey: .items)
        calories = try container.decode(Int.self, forKey: .calories)
        proteinGrams = try container.decode(Double.self, forKey: .proteinGrams)
        carbsGrams = try container.decode(Double.self, forKey: .carbsGrams)
        fatGrams = try container.decode(Double.self, forKey: .fatGrams)
        confidence = try container.decode(Double.self, forKey: .confidence)
        alternatives = try container.decodeIfPresent([String].self, forKey: .alternatives) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(timing, forKey: .timing)
        try container.encodeIfPresent(eatenAtGuessISO8601, forKey: .eatenAtGuessISO8601)
        try container.encode(items, forKey: .items)
        try container.encode(calories, forKey: .calories)
        try container.encode(proteinGrams, forKey: .proteinGrams)
        try container.encode(carbsGrams, forKey: .carbsGrams)
        try container.encode(fatGrams, forKey: .fatGrams)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(alternatives, forKey: .alternatives)
    }
}

struct AIInterpretedMealItem: Codable {
    var name: String
    var amount: Double
    var unit: String
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
}

enum AIServiceError: LocalizedError {
    case invalidURL(String)
    case invalidRequestPayload
    case transport(underlying: Error)
    case unexpectedStatusCode(Int, body: String)
    /// `bodyPreview` is populated in debug builds when the proxy returns non-JSON or a schema mismatch; always `nil` in release.
    case malformedResponse(bodyPreview: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let rawValue):
            return "Invalid AI proxy URL: \(rawValue)"
        case .invalidRequestPayload:
            return "Could not encode AI request payload."
        case .transport(let underlying):
            return "AI service network error: \(underlying.localizedDescription)"
        case .unexpectedStatusCode(let statusCode, _):
            return "AI service returned status code \(statusCode)."
        case .malformedResponse:
            return "AI service returned malformed structured data."
        }
    }
}

struct OpenAIProxyServiceConfig {
    var baseURL: URL
    var interpretMealPath: String
    var interpretGoalPath: String
    var coachPath: String
    /// Optional proxy credential. This is for the app -> backend proxy hop only.
    var proxyBearerToken: String?

    static let `default` = OpenAIProxyServiceConfig(
        baseURL: URL(string: "http://localhost:8080")!,
        interpretMealPath: "/ai/interpret-meal",
        interpretGoalPath: "/ai/interpret-goal",
        coachPath: "/ai/coach",
        proxyBearerToken: nil
    )
}

struct OpenAIProxyAIService: AIService {
    private let config: OpenAIProxyServiceConfig
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(
        config: OpenAIProxyServiceConfig,
        session: URLSession = .shared
    ) {
        self.config = config
        self.session = session
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    func send(message: String, context: [String: String]) async throws -> String {
        let request = AIInterpretMealRequest(
            text: message,
            image: nil,
            context: AIInterpretMealContext(
                ownerID: context["ownerID"],
                localeIdentifier: context["localeIdentifier"],
                timeZoneIdentifier: context["timeZoneIdentifier"]
            )
        )
        let response = try await interpretMeal(request: request)
        return response.uiNotes ?? "Interpreted \(response.interpretedMeals.count) meal(s)."
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await postJSON(path: config.interpretMealPath, body: request, decode: AIInterpretMealResponse.self)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await postJSON(path: config.interpretGoalPath, body: request, decode: AIInterpretGoalResponse.self)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        try await postJSON(path: config.coachPath, body: request, decode: AICoachResponse.self)
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        decode responseType: Response.Type
    ) async throws -> Response {
        let endpoint = try Self.resolvedURL(path: path, baseURL: config.baseURL)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        #if DEBUG
        if config.proxyBearerToken?.isEmpty != false {
            print("AI proxy token missing from local config")
        }
        #endif
        if let token = config.proxyBearerToken, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            urlRequest.httpBody = try jsonEncoder.encode(body)
        } catch {
            throw AIServiceError.invalidRequestPayload
        }

        let responsePayload: Data
        let response: URLResponse
        do {
            (responsePayload, response) = try await session.data(for: urlRequest)
        } catch {
            throw AIServiceError.transport(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.malformedResponse(bodyPreview: nil)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            if httpResponse.statusCode == 401, config.proxyBearerToken?.isEmpty != false {
                print("AI proxy token missing from local config")
            }
            #endif
            let errorBody: String
            #if DEBUG
            errorBody = Self.responseBodySnippet(from: responsePayload)
            #else
            errorBody = "<redacted>"
            #endif
            throw AIServiceError.unexpectedStatusCode(httpResponse.statusCode, body: errorBody)
        }

        do {
            return try jsonDecoder.decode(Response.self, from: responsePayload)
        } catch {
            #if DEBUG
            throw AIServiceError.malformedResponse(bodyPreview: Self.responseBodySnippet(from: responsePayload))
            #else
            throw AIServiceError.malformedResponse(bodyPreview: nil)
            #endif
        }
    }

    private static func resolvedURL(path: String, baseURL: URL) throws -> URL {
        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            return absoluteURL
        }
        guard let combined = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw AIServiceError.invalidURL(path)
        }
        return combined
    }

    /// UTF-8 decode with truncation for debug-only error surfaces (never shown in release UI).
    private static func responseBodySnippet(from data: Data, maxCharacters: Int = 8192) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "(binary body, \(data.count) bytes)"
        guard raw.count > maxCharacters else { return raw }
        let end = raw.index(raw.startIndex, offsetBy: maxCharacters)
        return String(raw[..<end]) + "…"
    }
}
