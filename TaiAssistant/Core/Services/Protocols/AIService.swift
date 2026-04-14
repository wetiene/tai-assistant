import Foundation

protocol AIService {
    func send(message: String, context: [String: String]) async throws -> String
}
