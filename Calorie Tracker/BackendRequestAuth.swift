import Foundation
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

enum BackendRequestAuthError: LocalizedError {
    case appCheckUnavailable
    case appCheckTokenMissing

    var errorDescription: String? {
        switch self {
        case .appCheckUnavailable:
            return "Firebase App Check SDK is not configured in this build."
        case .appCheckTokenMissing:
            return "Could not fetch an App Check token."
        }
    }
}

enum BackendRequestAuth {
    private static let userDefaultsKey = "backend_client_instance_id_v1"
    private static let clientInstanceIdHeaderName = "X-Client-Instance-Id"
    private static let appCheckHeaderName = "X-Firebase-AppCheck"

    static func applyHeaders(to request: inout URLRequest, forcingRefresh: Bool = false) async throws {
        request.setValue(clientInstanceId(), forHTTPHeaderField: clientInstanceIdHeaderName)
        request.setValue(try await appCheckToken(forcingRefresh: forcingRefresh), forHTTPHeaderField: appCheckHeaderName)
    }

    private static func clientInstanceId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: userDefaultsKey),
           isValidClientInstanceId(existing) {
            return existing
        }

        let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        defaults.set(generated, forKey: userDefaultsKey)
        return generated
    }

    private static func isValidClientInstanceId(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9_-]{16,128}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func appCheckToken(forcingRefresh: Bool) async throws -> String {
#if canImport(FirebaseAppCheck)
        let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            AppCheck.appCheck().token(forcingRefresh: forcingRefresh) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tokenValue = token?.token, !tokenValue.isEmpty else {
                    continuation.resume(throwing: BackendRequestAuthError.appCheckTokenMissing)
                    return
                }
                continuation.resume(returning: tokenValue)
            }
        }
        return token
#else
        throw BackendRequestAuthError.appCheckUnavailable
#endif
    }
}
