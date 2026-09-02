import Foundation

protocol PlanRepository: Sendable {
    func getPlans() async throws -> [NightPlan]
    func savePlan(_ plan: NightPlan) async throws
    func deletePlan(_ plan: NightPlan) async throws
}

/// Disk-backed plan storage (same pattern as LocalTripRepository).
actor LocalPlanRepository: PlanRepository {
    private let fileURL: URL
    private var cache: [NightPlan]?

    init() {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let base = baseDir.appendingPathComponent("BarPassPlans", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("plans.json")
    }

    /// Decodes entries individually (2026-09-02 bug fix): a whole-array
    /// decode is atomic, so one plan cached under the pre-2026-09-01 schema
    /// used to silently wipe every other cached plan the first time this
    /// ran post-update (`?? []` swallowed the failure with zero signal, and
    /// the next `savePlan`/`deletePlan` would have persisted that empty
    /// list, permanently losing the rest). Decoding one entry at a time
    /// drops only the entries that actually fail to parse.
    func getPlans() async throws -> [NightPlan] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            cache = []
            return []
        }
        let plans = objects.compactMap { obj -> NightPlan? in
            guard let objData = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return try? JSONDecoder().decode(NightPlan.self, from: objData)
        }
        cache = plans
        return plans
    }

    func savePlan(_ plan: NightPlan) async throws {
        var plans = try await getPlans()
        plans.removeAll { $0.id == plan.id }
        plans.insert(plan, at: 0)
        try write(plans)
    }

    func deletePlan(_ plan: NightPlan) async throws {
        var plans = try await getPlans()
        plans.removeAll { $0.id == plan.id }
        try write(plans)
    }

    private func write(_ plans: [NightPlan]) throws {
        cache = plans
        try JSONEncoder().encode(plans).write(to: fileURL, options: .atomic)
    }
}

/// Routes to Supabase when signed in, local disk otherwise (2026-09-02 bug
/// fix) — `RepositoryDependencies.plan` used to be hardcoded straight to
/// `SupabasePlanRepository`, so a guest session got a `NoSessionError` on
/// every call and no persistence at all, despite doc comments elsewhere
/// claiming a local fallback existed.
actor CompositePlanRepository: PlanRepository {
    private let remote: PlanRepository = SupabasePlanRepository()
    private let local: PlanRepository = LocalPlanRepository()

    private var isSignedIn: Bool { AuthService.shared.restoreSession() != nil }

    func getPlans() async throws -> [NightPlan] {
        isSignedIn ? try await remote.getPlans() : try await local.getPlans()
    }

    func savePlan(_ plan: NightPlan) async throws {
        if isSignedIn { try await remote.savePlan(plan) } else { try await local.savePlan(plan) }
    }

    func deletePlan(_ plan: NightPlan) async throws {
        if isSignedIn { try await remote.deletePlan(plan) } else { try await local.deletePlan(plan) }
    }
}
