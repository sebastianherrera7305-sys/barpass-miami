import Foundation
import CryptoKit

/// Helpers for Sign in with Apple's replay-protection nonce, per Apple's docs:
/// https://developer.apple.com/documentation/sign_in_with_apple/generate_and_verify_tokens
enum AppleSignInHelpers {
    /// Generates a cryptographically random string to use as the raw nonce.
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    /// SHA256-hashes the raw nonce — this hashed value is sent to Apple in the request;
    /// the *raw* nonce is what gets forwarded to Firebase alongside the identity token.
    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
