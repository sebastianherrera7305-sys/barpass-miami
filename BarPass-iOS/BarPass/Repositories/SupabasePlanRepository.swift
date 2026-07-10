import Foundation

/// Placeholder until Supabase Auth + a `night_plans` schema with RLS are
/// live. Registered in the project so the swap in `RepositoryDependencies`
/// is one line; throws loudly instead of failing silently.
actor SupabasePlanRepository: PlanRepository {
    struct NotWiredError: LocalizedError {
        var errorDescription: String? { "SupabasePlanRepository: tabla night_plans/Auth aún no configuradas." }
    }

    func getPlans() async throws -> [NightPlan] { throw NotWiredError() }
    func savePlan(_ plan: NightPlan) async throws { throw NotWiredError() }
    func deletePlan(_ plan: NightPlan) async throws { throw NotWiredError() }
}
