import Foundation

struct AIProxyCallDiagnostics: Sendable {
    var requestURL: String?
    var httpStatus: Int?
    var contentType: String?
    var responseByteCount: Int?
    var responseBodyPreview: String?
    var underlyingError: Error?
}

protocol AIProxyDiagnosticsReporting: AnyObject {
    var lastCallDiagnostics: AIProxyCallDiagnostics? { get }
}
