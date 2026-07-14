import Foundation

/// 21+ age verification, required by Apple for apps centered on alcohol
/// access (App Review Guideline 1.3). Verified once per install, persisted
/// locally — never sent anywhere, never asked again once passed.
enum AgeGateService {
    private static let dobKey = "bp_date_of_birth"
    private static let verifiedKey = "bp_age_verified_21"

    static var isVerified: Bool {
        UserDefaults.standard.bool(forKey: verifiedKey)
    }

    static func isOver21(_ dateOfBirth: Date) -> Bool {
        let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
        return age >= 21
    }

    /// Returns whether the given date of birth clears the 21+ bar. Only
    /// persists (marks verified) when it does — a rejected attempt leaves
    /// the gate showing again next launch rather than silently letting them in.
    @discardableResult
    static func verify(dateOfBirth: Date) -> Bool {
        guard isOver21(dateOfBirth) else { return false }
        UserDefaults.standard.set(dateOfBirth.timeIntervalSince1970, forKey: dobKey)
        UserDefaults.standard.set(true, forKey: verifiedKey)
        return true
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: dobKey)
        UserDefaults.standard.removeObject(forKey: verifiedKey)
    }
}
