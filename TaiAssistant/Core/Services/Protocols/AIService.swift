import Foundation

protocol AIService {
    func send(message: String, context: [String: String]) async throws -> String
    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse
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
    case malformedResponse

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
    /// Optional proxy credential. This is for the app -> backend proxy hop only.
    var proxyBearerToken: String?

    static let `default` = OpenAIProxyServiceConfig(
        baseURL: URL(string: "http://localhost:8080")!,
        interpretMealPath: "/ai/interpret-meal",
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
        let endpoint = try resolvedInterpretMealURL()
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
            urlRequest.httpBody = try jsonEncoder.encode(request)
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
            throw AIServiceError.malformedResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            if httpResponse.statusCode == 401, config.proxyBearerToken?.isEmpty != false {
                print("AI proxy token missing from local config")
            }
            #endif
            throw AIServiceError.unexpectedStatusCode(httpResponse.statusCode, body: "<redacted>")
        }

        do {
            return try jsonDecoder.decode(AIInterpretMealResponse.self, from: responsePayload)
        } catch {
            throw AIServiceError.malformedResponse
        }
    }

    private func resolvedInterpretMealURL() throws -> URL {
        if let absoluteURL = URL(string: config.interpretMealPath), absoluteURL.scheme != nil {
            return absoluteURL
        }
        guard let combined = URL(string: config.interpretMealPath, relativeTo: config.baseURL)?.absoluteURL else {
            throw AIServiceError.invalidURL(config.interpretMealPath)
        }
        return combined
    }
}
