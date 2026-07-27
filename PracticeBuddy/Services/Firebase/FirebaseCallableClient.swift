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
        do {
            let result = try await functions.httpsCallable(name).call(data)
            guard let response = result.data as? [String: Any] else {
                throw FirebaseCallableError.invalidResponse
            }
            return response
        } catch {
            throw FirebaseCallableError.normalized(error)
        }
    }
}

enum FirebaseCallableError: LocalizedError {
    case invalidResponse
    case rateLimited(retryAfterSeconds: Int?)

    static func normalized(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              nsError.code == FunctionsErrorCode.resourceExhausted.rawValue else {
            return error
        }
        let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        let retrySeconds = (details?["retryAfterSeconds"] as? NSNumber)?.intValue
        return FirebaseCallableError.rateLimited(retryAfterSeconds: retrySeconds)
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The service returned an invalid response. Please try again."
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds, retryAfterSeconds > 0 {
                let minutes = max(1, Int(ceil(Double(retryAfterSeconds) / 60)))
                return "You’ve reached a temporary limit. Try again in about \(minutes) minute\(minutes == 1 ? "" : "s")."
            }
            return "You’ve reached a temporary limit. Wait a moment and try again."
        }
    }
}
