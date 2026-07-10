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

    func getPlans() async throws -> [NightPlan] {
        if let cache { return cache }
        let plans = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([NightPlan].self, from: $0) } ?? []
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
