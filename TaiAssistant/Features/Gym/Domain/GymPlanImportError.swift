import CryptoKit
import Foundation

enum GymPlanImportFailureStage: String, Sendable {
    case requestConstruction
    case transport
    case authentication
    case proxyResponse
    case jsonDecoding
    case responseMapping
    case reviewPresentation
}

enum GymPlanImportError: Error, Sendable {
    case invalidSource
    case invalidConfiguration
    case unauthorized
    case transport(underlying: Error)
    case server(statusCode: Int)
    case invalidContentType
    case invalidResponse
    case decoding(underlying: Error?)
    case mapping

    var stage: GymPlanImportFailureStage {
        switch self {
        case .invalidSource, .invalidConfiguration:
            return .requestConstruction
        case .transport:
            return .transport
        case .unauthorized:
            return .authentication
        case .server, .invalidContentType, .invalidResponse:
            return .proxyResponse
        case .decoding:
            return .jsonDecoding
        case .mapping:
            return .responseMapping
        }
    }

    var userFacingMessage: String {
        switch self {
        case .invalidSource:
            return "Add your trainer program text before analysing."
        case .invalidConfiguration:
            return "Your app configuration isn’t set up for plan analysis."
        case .unauthorized:
            return "Your app configuration isn’t authorised for plan analysis."
        case .transport:
            return "Tai couldn’t reach the analysis service. Try again."
        case .server:
            return "Tai couldn’t reach the analysis service. Try again."
        case .invalidContentType, .invalidResponse, .decoding, .mapping:
            return "Tai received an unexpected response. Try again."
        }
    }

    var allowsRetry: Bool {
        switch self {
        case .invalidSource, .invalidConfiguration:
            return false
        default:
            return true
        }
    }
}

struct GymPlanImportDiagnostics: Sendable {
    let stage: GymPlanImportFailureStage
    let requestURL: String?
    let httpMethod: String
    let sourceType: String
    let schemaVersion: Int
    let sourceTextCharacterCount: Int
    let knownExerciseCount: Int
    let httpStatus: Int?
    let contentType: String?
    let responseByteCount: Int?
    let tokenPresent: Bool
    let tokenLength: Int
    let tokenFingerprint: String?
    let underlyingDomain: String?
    let underlyingCode: Int?
    let decodingPath: String?
    let errorReflection: String

    #if DEBUG
    let responseBodyPreview: String?

    var debugSummary: String {
        """
        stage=\(stage.rawValue)
        requestURL=\(requestURL ?? "nil")
        httpMethod=\(httpMethod)
        sourceType=\(sourceType)
        schemaVersion=\(schemaVersion)
        sourceTextCharacterCount=\(sourceTextCharacterCount)
        knownExerciseCount=\(knownExerciseCount)
        httpStatus=\(httpStatus.map(String.init) ?? "nil")
        contentType=\(contentType ?? "nil")
        responseByteCount=\(responseByteCount.map(String.init) ?? "nil")
        tokenPresent=\(tokenPresent)
        tokenLength=\(tokenLength)
        tokenFingerprint=\(tokenFingerprint ?? "nil")
        underlyingDomain=\(underlyingDomain ?? "nil")
        underlyingCode=\(underlyingCode.map(String.init) ?? "nil")
        decodingPath=\(decodingPath ?? "nil")
        errorReflection=\(errorReflection)
        responseBodyPreview=\(responseBodyPreview ?? "nil")
        """
    }
    #endif

    static func tokenFingerprint(for token: String?) -> String? {
        guard let token, !token.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func log(_ diagnostics: GymPlanImportDiagnostics) {
        #if DEBUG
        print("[GymPlanImport] \(diagnostics.debugSummary)")
        #endif
    }
}

enum GymPlanImportErrorMapper {
    static func map(_ error: Error) -> GymPlanImportError {
        if let importError = error as? GymPlanImportError {
            return importError
        }
        if let serviceError = error as? AIServiceError {
            return mapServiceError(serviceError)
        }
        if error is DecodingError {
            return .decoding(underlying: error)
        }
        return .transport(underlying: error)
    }

    static func mapServiceError(_ error: AIServiceError) -> GymPlanImportError {
        switch error {
        case .invalidURL, .invalidRequestPayload:
            return .invalidConfiguration
        case .transport:
            return .transport(underlying: error)
        case .unexpectedStatusCode(let statusCode, _):
            if statusCode == 401 || statusCode == 403 {
                return .unauthorized
            }
            return .server(statusCode: statusCode)
        case .malformedResponse:
            return .decoding(underlying: error)
        }
    }

    static func diagnostics(
        for error: GymPlanImportError,
        context: GymPlanImportRequestContext,
        serviceDiagnostics: AIProxyCallDiagnostics?
    ) -> GymPlanImportDiagnostics {
        let decodingPath: String?
        if case .decoding(let underlying) = error,
           let decodingError = underlying as? DecodingError {
            decodingPath = Self.decodingPathDescription(decodingError)
        } else {
            decodingPath = nil
        }

        let nsError = (serviceDiagnostics?.underlyingError ?? error as NSError?) as NSError?
        #if DEBUG
        return GymPlanImportDiagnostics(
            stage: error.stage,
            requestURL: serviceDiagnostics?.requestURL ?? context.requestURL,
            httpMethod: "POST",
            sourceType: context.sourceType.rawValue,
            schemaVersion: context.schemaVersion,
            sourceTextCharacterCount: context.sourceTextCharacterCount,
            knownExerciseCount: context.knownExerciseCount,
            httpStatus: serviceDiagnostics?.httpStatus,
            contentType: serviceDiagnostics?.contentType,
            responseByteCount: serviceDiagnostics?.responseByteCount,
            tokenPresent: context.tokenPresent,
            tokenLength: context.tokenLength,
            tokenFingerprint: context.tokenFingerprint,
            underlyingDomain: nsError?.domain,
            underlyingCode: nsError?.code,
            decodingPath: decodingPath,
            errorReflection: String(reflecting: error),
            responseBodyPreview: serviceDiagnostics?.responseBodyPreview
        )
        #else
        return GymPlanImportDiagnostics(
            stage: error.stage,
            requestURL: serviceDiagnostics?.requestURL ?? context.requestURL,
            httpMethod: "POST",
            sourceType: context.sourceType.rawValue,
            schemaVersion: context.schemaVersion,
            sourceTextCharacterCount: context.sourceTextCharacterCount,
            knownExerciseCount: context.knownExerciseCount,
            httpStatus: serviceDiagnostics?.httpStatus,
            contentType: serviceDiagnostics?.contentType,
            responseByteCount: serviceDiagnostics?.responseByteCount,
            tokenPresent: context.tokenPresent,
            tokenLength: context.tokenLength,
            tokenFingerprint: context.tokenFingerprint,
            underlyingDomain: nsError?.domain,
            underlyingCode: nsError?.code,
            decodingPath: decodingPath,
            errorReflection: String(reflecting: error)
        )
        #endif
    }

    private static func decodingPathDescription(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "keyNotFound(\(key.stringValue)) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "typeMismatch(\(type)) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "valueNotFound(\(type)) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "dataCorrupted at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default:
            return String(reflecting: error)
        }
    }
}

struct GymPlanImportRequestContext: Sendable {
    let requestURL: String?
    let sourceType: GymPlanImportSourceType
    let schemaVersion: Int
    let sourceTextCharacterCount: Int
    let knownExerciseCount: Int
    let tokenPresent: Bool
    let tokenLength: Int
    let tokenFingerprint: String?
}
