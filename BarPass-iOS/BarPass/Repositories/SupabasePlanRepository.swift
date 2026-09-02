import Foundation

/// Real Supabase-backed night plans (`public.night_plans`, see
/// barpass-v2/supabase/schema.sql — already created and live, confirmed
/// against the real DB). Unlike `trips`, this table isn't a field-by-field
/// mirror of the model: `NightPlan` is stored whole as a jsonb blob in the
/// `plan` column, with `id`/`user_id`/`title` as their own columns purely
/// for RLS and future listing/search — `Row` is the wire format, not
/// `NightPlan` itself.
///
/// Requires a real signed-in session — RLS scopes every row to
/// `auth.uid()`, so guest mode (no session) can't read/write plans at all,
/// same restriction `SupabaseTripRepository` has for trips.
actor SupabasePlanRepository: PlanRepository {
    struct NoSessionError: LocalizedError {
        var errorDescription: String? { L10n.tSync("plan.error.noSession") }
    }

    private struct Row: Codable {
        let id: String
        let userId: String
        let title: String
        let plan: NightPlan

        enum CodingKeys: String, CodingKey {
            case id, title, plan
            case userId = "user_id"
        }
    }

    // Row is NOT snake_case-mapped (user_id has an explicit CodingKey; id/
    // title/plan need no conversion) — SupabaseRESTClient's shared coders
    // would be harmless on Row's own keys but wrong for whatever casing
    // NightPlan's own Codable conformance uses inside the jsonb blob, so
    // this keeps its own plain (iso8601-only) coders.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func session() throws -> AuthSession {
        guard let s = AuthService.shared.restoreSession() else { throw NoSessionError() }
        return s
    }

    private func request(_ method: String, path: String, body: Data? = nil) throws -> URLRequest {
        try SupabaseRESTClient.request(method, path: path, body: body, accessToken: try session().accessToken)
    }

    // MARK: - PlanRepository

    /// Decodes row by row instead of the whole array at once (2026-09-02 bug
    /// fix): `NightPlan`'s schema changed 2026-09-01, and `Decodable` array
    /// decoding is atomic — a single pre-migration row (old field names)
    /// used to take down the entire list instead of just that one row.
    func getPlans() async throws -> [NightPlan] {
        let req = try request("GET", path: "night_plans?select=id,user_id,title,plan&order=created_at.desc")
        let data = try await SupabaseRESTClient.send(req)
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return objects.compactMap { obj in
            guard let objData = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return try? Self.decoder.decode(Row.self, from: objData).plan
        }
    }

    /// Upsert by id (matches the overwrite-or-insert semantics
    /// `LocalPlanRepository` had) — one POST with `resolution=merge-
    /// duplicates` instead of a separate exists-check + PATCH/POST branch.
    func savePlan(_ plan: NightPlan) async throws {
        let userId = try session().user.id
        let row = Row(id: plan.id, userId: userId, title: plan.title, plan: plan)
        let body = try Self.encoder.encode(row)
        let req = try SupabaseRESTClient.request(
            "POST", path: "night_plans", body: body, accessToken: try session().accessToken,
            extraHeaders: ["Prefer": "return=minimal,resolution=merge-duplicates"]
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "save failed"])
        }
    }

    func deletePlan(_ plan: NightPlan) async throws {
        let req = try request("DELETE", path: "night_plans?id=eq.\(plan.id)")
        try await SupabaseRESTClient.send(req)
    }
}
