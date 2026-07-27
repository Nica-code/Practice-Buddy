import Foundation
import FirebaseFunctions

protocol FirebaseCallableTransport {
    func call(_ name: String, data: [String: Any]) async throws -> [String: Any]
}

/// Shared transport for client-authorized Cloud Functions. Firebase attaches
/// both the current Auth token and App Check token to callable requests.
final class FirebaseCallableClient: FirebaseCallableTransport {
    private let functions: Functions

    init(functions: Functions = .functions()) {
        self.functions = functions
    }

    func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        let result = try await functions.httpsCallable(name).call(data)
        guard let response = result.data as? [String: Any] else {
            throw FirebaseCallableError.invalidResponse
        }
        return response
    }
}

enum FirebaseCallableError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The service returned an invalid response. Please try again."
        }
    }
}
