import Foundation

/// 21+ age verification, required by Apple for apps centered on alcohol
/// access (App Review Guideline 1.3). Verified once per install, persisted
/// locally — never sent anywhere, never asked again once passed.
enum AgeGateService {
    private static let dobKey = "bp_date_of_birth"
    private static let verifiedKey = "bp_age_verified_21"
    private static let syncedKey = "bp_date_of_birth_synced"

    static var isVerified: Bool {
        UserDefaults.standard.bool(forKey: verifiedKey)
    }

    static var storedDateOfBirth: Date? {
        let t = UserDefaults.standard.double(forKey: dobKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// True only once `RepositoryDependencies.birthdate.setBirthdate` has
    /// actually confirmed success against the server — the write in
    /// AgeGateView is fire-and-forget (by design, so a signed-out/offline
    /// moment never traps the user on the age gate), so this flag is what
    /// lets a later retry (see RootView) know whether that write ever
    /// really landed. Every profile in the DB showing a null `birthdate`
    /// after the fact — which silently blocks check-in — is exactly the
    /// failure mode this exists to catch and retry.
    static var isSyncedToServer: Bool {
        get { UserDefaults.standard.bool(forKey: syncedKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncedKey) }
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
