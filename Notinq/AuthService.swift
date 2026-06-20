import Foundation
import Security
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

final class AuthService {
    static let shared = AuthService()

    private enum KeychainKeys {
        static let service = "com.notinq.auth"
        static let account = "google_access_token"
    }

    private enum DefaultsKeys {
        static let userEmail = "google_user_email"
    }

    private init() {}

    var isLoggedIn: Bool {
        guard let token = accessToken else { return false }
        return !token.isEmpty
    }

    var userEmail: String? {
        UserDefaults.standard.string(forKey: DefaultsKeys.userEmail)
    }

    var accessToken: String? {
        readTokenFromKeychain()
    }

    func signIn(completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(GoogleSignIn)
        guard let window = NSApp.keyWindow,
              let contentVC = window.contentViewController else {
            completion(.failure(AuthError.presentationContextUnavailable))
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: contentVC) { result, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let user = result?.user,
                  let token = user.accessToken.tokenString as String? else {
                completion(.failure(AuthError.missingToken))
                return
            }

            do {
                try self.saveTokenToKeychain(token)
                UserDefaults.standard.set(user.profile?.email, forKey: DefaultsKeys.userEmail)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        #else
        completion(.failure(AuthError.googleSignInUnavailable))
        #endif
    }

    func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        deleteTokenFromKeychain()
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.userEmail)
    }

    private func saveTokenToKeychain(_ token: String) throws {
        deleteTokenFromKeychain()

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: KeychainKeys.account,
            kSecValueData as String: Data(token.utf8)
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.keychainWriteFailed(status)
        }
    }

    private func readTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: KeychainKeys.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: KeychainKeys.account
        ]

        SecItemDelete(query as CFDictionary)
    }
}

enum AuthError: LocalizedError {
    case googleSignInUnavailable
    case presentationContextUnavailable
    case missingToken
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .googleSignInUnavailable:
            return "Google Sign-In SDK is not configured in this build."
        case .presentationContextUnavailable:
            return "Unable to start sign-in because no active window was found."
        case .missingToken:
            return "Google Sign-In completed without an access token."
        case .keychainWriteFailed:
            return "Could not securely store your sign-in token."
        }
    }
}
