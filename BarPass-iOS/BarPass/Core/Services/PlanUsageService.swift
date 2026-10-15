import Foundation

/// Free-tier daily quota for Plan chat — the actual gate that makes Premium's
/// "unlimited" real, not just a label. One turn sent to Remy = one unit of
/// usage; Premium never calls into this at all (see `PlanView.sendToRemy`).
///
/// Signed-in users are tracked server-side (`plan_usage` table, atomic RPCs
/// so concurrent taps across devices can't race past the limit). Guests have
/// no server-side identity, so their count lives in UserDefaults instead —
/// less tamper-proof, but a guest can already reinstall to reset local state
/// regardless of where the counter lives, so this isn't a regression.
///
/// The limit itself (`app_config.plan_free_daily_limit`) is configurable
/// from Supabase, not hardcoded — changing it in the dashboard changes the
/// limit for everyone with no app update.
actor PlanUsageService {
    static let shared = PlanUsageService()

    enum PlanUsageState {
        case available
        case limitReached
    }

    private var cachedLimit: Int?
    private static let defaultLimit = 10

    private static let guestCountKey = "bp_plan_guest_usage_count"
    private static let guestDateKey = "bp_plan_guest_usage_date"

    private func dailyLimit() async -> Int {
        if let cachedLimit { return cachedLimit }
        do {
            let req = try SupabaseRESTClient.request(
                "GET", path: "app_config",
                queryItems: [
                    URLQueryItem(name: "select", value: "value"),
                    URLQueryItem(name: "key", value: "eq.plan_free_daily_limit"),
                ]
            )
            let data = try await SupabaseRESTClient.send(req)
            struct Row: Decodable { let value: Int }
            if let row = try? JSONDecoder().decode([Row].self, from: data).first {
                cachedLimit = row.value
                return row.value
            }
        } catch {
            // Fall through to the default — a config-read hiccup must never
            // block the chat entirely.
        }
        cachedLimit = Self.defaultLimit
        return Self.defaultLimit
    }

    /// Today's count for a guest, resetting silently when `usage_date` has
    /// rolled over — no cron, just compared against "today" on read.
    private func guestCount() -> Int {
        let today = Self.todayString()
        guard UserDefaults.standard.string(forKey: Self.guestDateKey) == today else { return 0 }
        return UserDefaults.standard.integer(forKey: Self.guestCountKey)
    }

    private func incrementGuestCount() {
        let today = Self.todayString()
        let current = UserDefaults.standard.string(forKey: Self.guestDateKey) == today
            ? UserDefaults.standard.integer(forKey: Self.guestCountKey)
            : 0
        UserDefaults.standard.set(current + 1, forKey: Self.guestCountKey)
        UserDefaults.standard.set(today, forKey: Self.guestDateKey)
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: .now)
    }

    /// Whether another turn is allowed right now. Never throws — any read
    /// failure (network hiccup, no session) reads as `.available` rather
    /// than blocking the chat over an infrastructure problem.
    func currentState(isSignedIn: Bool) async -> PlanUsageState {
        let limit = await dailyLimit()
        let count: Int
        if isSignedIn {
            count = await readServerCount()
        } else {
            count = guestCount()
        }
        return count >= limit ? .limitReached : .available
    }

    private func readServerCount() async -> Int {
        do {
            let session = try await SupabaseRESTClient.freshSession()
            let req = try SupabaseRESTClient.request("POST", path: "rpc/get_plan_usage", body: Data("{}".utf8), accessToken: session.accessToken)
            let data = try await SupabaseRESTClient.send(req)
            return (try? JSONDecoder().decode(Int.self, from: data)) ?? 0
        } catch {
            return 0
        }
    }

    /// Records one turn of usage — call after a message actually goes to
    /// Remy, not before (a gate check that then fails to send shouldn't
    /// still cost the user their quota).
    func recordUsage(isSignedIn: Bool) async {
        guard isSignedIn else {
            incrementGuestCount()
            return
        }
        do {
            let session = try await SupabaseRESTClient.freshSession()
            let req = try SupabaseRESTClient.request("POST", path: "rpc/increment_plan_usage", body: Data("{}".utf8), accessToken: session.accessToken)
            _ = try await SupabaseRESTClient.send(req)
        } catch {
            // Best-effort — an increment that fails to persist server-side
            // just means the next `currentState` read undercounts by one,
            // never a crash or a blocked chat.
        }
    }
}
