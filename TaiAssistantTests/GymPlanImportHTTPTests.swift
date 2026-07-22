import XCTest
@testable import TaiAssistant

@MainActor
final class GymPlanImportHTTPTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRequestEncodingMatchesProxyContract() throws {
        let source = GymPlanImportSource.pastedText(GymTrainerProgramFixture.pastedText)
        let request = AIInterpretWorkoutPlanRequest(
            schemaVersion: 1,
            source: AIWorkoutPlanSourcePayload(type: "text", text: source.text, attachment: nil),
            context: AIWorkoutPlanInterpretContext(
                localeIdentifier: "en_AU",
                preferredWeightUnit: "kg",
                knownExercises: GymPlanImportMapper.knownExerciseCatalog()
            )
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        let sourceJSON = try XCTUnwrap(json["source"] as? [String: Any])
        XCTAssertEqual(sourceJSON["type"] as? String, "text")
        XCTAssertFalse((sourceJSON["text"] as? String)?.isEmpty ?? true)
        let contextJSON = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(contextJSON["preferredWeightUnit"] as? String, "kg")
        XCTAssertFalse((contextJSON["knownExercises"] as? [[String: String]])?.isEmpty ?? true)
    }

    func testResolvedWorkoutPlanURLUsesTaiProxyEndpoint() throws {
        let url = try XCTUnwrap(
            URL(
                string: RuntimeAppConfig.default.aiInterpretWorkoutPlanPath,
                relativeTo: RuntimeAppConfig.default.aiProxyBaseURL
            )?.absoluteString
        )
        XCTAssertEqual(url, "https://tai-ai-proxy.taiassistant.workers.dev/ai/interpret-workout-plan")
    }

    func testSuccessfulTrainerPlanResponseDecodesAndMaps() async throws {
        let fixture = MockWorkoutPlanInterpretation.trainerFixtureResponse(
            for: AIInterpretWorkoutPlanRequest(
                schemaVersion: 1,
                source: AIWorkoutPlanSourcePayload(type: "text", text: "x", attachment: nil),
                context: nil
            )
        )
        let service = makeProxyService { request in
            XCTAssertEqual(request.url?.path, "/ai/interpret-workout-plan")
            let body = try XCTUnwrap(MockURLProtocol.httpBody(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["schemaVersion"] as? Int, 1)
            return MockURLProtocol.response(
                status: 200,
                contentType: "application/json",
                body: try JSONEncoder().encode(fixture)
            )
        }

        let draft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: service
        )
        XCTAssertEqual(draft.sections.map(\.name), GymTrainerProgramFixture.expectedSectionNames)
    }

    func testUnauthorizedMapsToGymPlanImportUnauthorized() async {
        let service = makeProxyService { _ in
            MockURLProtocol.response(status: 401, contentType: "application/json", body: Data("{\"error\":\"unauthorized\"}".utf8))
        }
        do {
            _ = try await GymPlanImportService.interpret(
                source: .pastedText(GymTrainerProgramFixture.pastedText),
                aiService: service
            )
            XCTFail("Expected unauthorized")
        } catch let error as GymPlanImportError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingEndpointMapsToServerError() async {
        let service = makeProxyService { _ in
            MockURLProtocol.response(status: 404, contentType: "application/json", body: Data("{\"error\":\"not_found\"}".utf8))
        }
        await assertImportError(.server(statusCode: 404), service: service)
    }

    func testJSONErrorEnvelopeMapsToServerError() async {
        let service = makeProxyService { _ in
            MockURLProtocol.response(
                status: 500,
                contentType: "application/json",
                body: Data("{\"error\":{\"code\":\"provider_error\",\"message\":\"temporarily unavailable\"}}".utf8)
            )
        }
        await assertImportError(.server(statusCode: 500), service: service)
    }

    func testPlainTextUpstreamBodyMapsToDecodingError() async {
        let service = makeProxyService { _ in
            MockURLProtocol.response(status: 520, contentType: "text/plain", body: Data("error code: 520".utf8))
        }
        await assertImportError(.server(statusCode: 520), service: service)
    }

    func testInvalidJSONBodyMapsToDecodingError() async {
        let service = makeProxyService { _ in
            MockURLProtocol.response(status: 200, contentType: "application/json", body: Data("not-json".utf8))
        }
        await assertImportError(.decoding(underlying: nil), service: service)
    }

    func testMissingRequiredResponseFieldMapsToDecodingError() async {
        let service = makeProxyService { _ in
            MockURLProtocol.response(
                status: 200,
                contentType: "application/json",
                body: Data("{\"schemaVersion\":1}".utf8)
            )
        }
        await assertImportError(.decoding(underlying: nil), service: service)
    }

    func testUnresolvedCustomExerciseStillMapsSuccessfully() async throws {
        var fixture = MockWorkoutPlanInterpretation.trainerFixtureResponse(
            for: AIInterpretWorkoutPlanRequest(
                schemaVersion: 1,
                source: AIWorkoutPlanSourcePayload(type: "text", text: "x", attachment: nil),
                context: nil
            )
        )
        fixture.unresolvedItems = [
            AIWorkoutPlanUnresolvedItem(
                sourceText: "Glute Trainer",
                reason: "No confident match",
                suggestedMatches: []
            )
        ]
        let service = makeProxyService { _ in
            MockURLProtocol.response(
                status: 200,
                contentType: "application/json",
                body: try JSONEncoder().encode(fixture)
            )
        }
        let draft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: service
        )
        XCTAssertEqual(draft.unresolvedItems.count, 1)
    }

    private func makeProxyService(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> OpenAIProxyAIService {
        MockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return OpenAIProxyAIService(
            config: OpenAIProxyServiceConfig(
                baseURL: URL(string: "https://tai-ai-proxy.taiassistant.workers.dev")!,
                interpretMealPath: "/ai/interpret-meal",
                interpretGoalPath: "/ai/interpret-goal",
                interpretGymPhotoPath: "/ai/interpret-gym-photo",
                interpretWorkoutPlanPath: "/ai/interpret-workout-plan",
                coachPath: "/ai/coach",
                proxyBearerToken: "test-token"
            ),
            session: URLSession(configuration: config)
        )
    }

    private func assertImportError(_ expected: GymPlanImportError, service: OpenAIProxyAIService) async {
        do {
            _ = try await GymPlanImportService.interpret(
                source: .pastedText(GymTrainerProgramFixture.pastedText),
                aiService: service
            )
            XCTFail("Expected \(expected)")
        } catch let error as GymPlanImportError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

extension GymPlanImportError: Equatable {
    public static func == (lhs: GymPlanImportError, rhs: GymPlanImportError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidSource, .invalidSource),
             (.invalidConfiguration, .invalidConfiguration),
             (.unauthorized, .unauthorized),
             (.invalidContentType, .invalidContentType),
             (.invalidResponse, .invalidResponse),
             (.mapping, .mapping):
            return true
        case (.transport, .transport),
             (.decoding, .decoding):
            return true
        case (.server(let l), .server(let r)):
            return l == r
        default:
            return false
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func response(status: Int, contentType: String, body: Data) -> (HTTPURLResponse, Data) {
        let url = URL(string: "https://tai-ai-proxy.taiassistant.workers.dev/ai/interpret-workout-plan")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (response, body)
    }

    static func httpBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 { return nil }
            if read == 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
