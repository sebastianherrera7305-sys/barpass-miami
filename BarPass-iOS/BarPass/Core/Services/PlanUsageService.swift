import Foundation

/// Free-tier usage states (04_FREE_PLAN_SPEC.md, Phase 3 —
/// 08_DEVELOPER_TASKS.md). `nearLimit`/`limitReached` carry the numbers a
/// UI needs to word its own copy; this type makes no assumption about how
/// it's displayed.
enum PlanUsageState: Equatable {
    case available(remaining: Int, limit: Int)
    case nearLimit(remaining: Int, limit: Int)
    case limitReached(limit: Int)
}

/// Phase 3 (08_DEVELOPER_TASKS.md "Usage") — server-side-configurable Free
/// quota plus a soft usage-limit experience. "Soft" per
/// 02_UX_ARCHITECTURE.md: never abruptly stop the conversation, only show
/// remaining usage when it's actually useful (near/at the limit), and
/// explain what Premium unlocks rather than just blocking.
///
/// The daily limit itself lives in Supabase (`public.app_config`, key
/// `plan_free_daily_limit`) — 04_FREE_PLAN_SPEC.md: "The exact quota
/// should be configurable from the backend. Do not hardcode the number
/// into the UI." Changing that row's value changes the limit for every
/// user on their next app-session, no build required.
///
/// Usage counts live in `public.plan_usage` for signed-in users (RLS-scoped
/// to `auth.uid()`, resets automatically when the stored date rolls over —
/// see the `increment_plan_usage`/`get_plan_usage` RPCs in schema.sql) and
/// in UserDefaults for guests, keyed by the same UTC calendar day — there's
/// no reliable server-side identity to scope a guest's Supabase row to, so
/// their count is device-local and resets on reinstall, same trade-off
/// `LocalConversationRepository`/`LocalPlanRepository` already accept.
actor PlanUsageService {
    static let shared = PlanUsageService()

    private static let defaultLimit = 10
    private static let nearLimitThreshold = 3
    private static let guestUsageKey = "bp_plan_guest_usage"

    private var cachedLimit: Int?

    private struct GuestUsage: Codable {
        var date: String
        var count: Int
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func today() -> String {
        Self.dayFormatter.string(from: Date())
    }

    /// Cached for the process lifetime once fetched successfully — a
    /// transient network failure falls back to `defaultLimit` without
    /// caching that fallback, so the next check can retry the real value.
    private func configuredLimit() async -> Int {
        if let cachedLimit { return cachedLimit }
        struct ConfigRow: Decodable { let value: Int }
        do {
            let req = try SupabaseRESTClient.request(
                "GET", path: "app_config",
                queryItems: [
                    URLQueryItem(name: "select", value: "value"),
                    URLQueryItem(name: "key", value: "eq.plan_free_daily_limit"),
                ]
            )
            let data = try await SupabaseRESTClient.send(req)
            guard let row = try JSONDecoder().decode([ConfigRow].self, from: data).first else {
                return Self.defaultLimit
            }
            cachedLimit = row.value
            return row.value
        } catch {
            return Self.defaultLimit
        }
    }

    private func guestUsageCount() -> Int {
        guard let data = UserDefaults.standard.data(forKey: Self.guestUsageKey),
              let usage = try? JSONDecoder().decode(GuestUsage.self, from: data),
              usage.date == today()
        else { return 0 }
        return usage.count
    }

    private func incrementGuestUsage() {
        let usage = GuestUsage(date: today(), count: guestUsageCount() + 1)
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: Self.guestUsageKey)
        }
    }

    private func remoteUsageCount() async -> Int {
        do {
            let session = try await SupabaseRESTClient.freshSession()
            let req = try SupabaseRESTClient.request("POST", path: "rpc/get_plan_usage", accessToken: session.accessToken)
            let data = try await SupabaseRESTClient.send(req)
            return (try? JSONDecoder().decode(Int.self, from: data)) ?? 0
        } catch {
            return 0
        }
    }

    private func incrementRemoteUsage() async {
        do {
            let session = try await SupabaseRESTClient.freshSession()
            let req = try SupabaseRESTClient.request("POST", path: "rpc/increment_plan_usage", accessToken: session.accessToken)
            _ = try await SupabaseRESTClient.send(req)
        } catch {
            // Best-effort — a failed increment just undercounts this one
            // turn. Never blocks the user over a usage-tracking hiccup.
        }
    }

    /// Reads the current state without recording a turn — call once before
    /// deciding whether to let a send through. `nil` means "no gate" (the
    /// caller is Premium/entitled — `PlanEntitlementService`).
    func currentState(isSignedIn: Bool) async -> PlanUsageState {
        let limit = await configuredLimit()
        let used = isSignedIn ? await remoteUsageCount() : guestUsageCount()
        let remaining = max(0, limit - used)
        if remaining <= 0 { return .limitReached(limit: limit) }
        if remaining <= Self.nearLimitThreshold { return .nearLimit(remaining: remaining, limit: limit) }
        return .available(remaining: remaining, limit: limit)
    }

    /// Records one turn's usage — call only after a real plan was actually
    /// generated (not for a greeting/capability reply, which cost nothing).
    func recordUsage(isSignedIn: Bool) async {
        if isSignedIn {
            await incrementRemoteUsage()
        } else {
            incrementGuestUsage()
        }
    }
}
