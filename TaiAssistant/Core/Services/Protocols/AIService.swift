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

struct AIInterpretMealContext: Codable {
    var ownerID: String?
    var localeIdentifier: String?
    var timeZoneIdentifier: String?
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
            let body = String(data: responsePayload, encoding: .utf8) ?? "<non-utf8>"
            throw AIServiceError.unexpectedStatusCode(httpResponse.statusCode, body: body)
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
