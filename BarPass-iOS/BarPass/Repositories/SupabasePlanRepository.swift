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
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

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
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/\(path)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try session().accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = body }
        return req
    }

    // MARK: - PlanRepository

    func getPlans() async throws -> [NightPlan] {
        let req = try request("GET", path: "night_plans?select=id,user_id,title,plan&order=created_at.desc")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let rows = try Self.decoder.decode([Row].self, from: data)
        return rows.map(\.plan)
    }

    /// Upsert by id (matches the overwrite-or-insert semantics
    /// `LocalPlanRepository` had) — one POST with `resolution=merge-
    /// duplicates` instead of a separate exists-check + PATCH/POST branch.
    func savePlan(_ plan: NightPlan) async throws {
        let userId = try session().user.id
        let row = Row(id: plan.id, userId: userId, title: plan.title, plan: plan)
        let body = try Self.encoder.encode(row)
        var req = try request("POST", path: "night_plans", body: body)
        req.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "save failed"])
        }
    }

    func deletePlan(_ plan: NightPlan) async throws {
        let req = try request("DELETE", path: "night_plans?id=eq.\(plan.id)")
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}
