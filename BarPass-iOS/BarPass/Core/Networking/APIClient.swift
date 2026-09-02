import Foundation

/// Thin client for the BarPass backend — barpass-v2's Next.js API routes,
/// deployed on Vercel. (The old barpass-miami.vercel.app Express/Firestore
/// backend was never deployed and is superseded by this one.)
enum APIClient {

    static let baseURL = URL(string: "https://barpass-v2.vercel.app/api")!

    enum APIClientError: LocalizedError {
        case notAuthenticated
        case sessionExpired
        case server(String)
        case network(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return L10n.tSync("api.error.notAuthenticated")
            case .sessionExpired:   return L10n.tSync("api.error.sessionExpired")
            case .server(let msg):  return msg
            case .network(let msg): return msg
            case .invalidResponse:  return L10n.tSync("api.error.invalidResponse")
            }
        }
    }

    /// Guarantees the access token used for an authenticated request is still
    /// valid (ADR-012). Callers read `session.accessToken` before awaiting, so
    /// by the time a request is built that token may already have expired — the
    /// JWT lives ~59 minutes and nothing else in the app refreshes it outside
    /// the login screen. `refreshIfNeeded()` is a no-op when the token is still
    /// good, so this adds no latency in the common case.
    ///
    /// The `provided` token is kept as a fallback for the (unexpected) case
    /// where no session can be read back after a successful refresh, so the
    /// public API signatures stay unchanged.
    private static func freshToken(_ provided: String) async throws -> String {
        guard await AuthService.shared.refreshIfNeeded() else {
            throw APIClientError.sessionExpired
        }
        return AuthService.shared.restoreSession()?.accessToken ?? provided
    }

    /// Generates a key matching the backend's required format:
    /// `bp_{vendorId}_{staffId}_{timestamp}_{RANDOM}` — see api/middleware/idempotency.js
    static func generateIdempotencyKey(vendorId: String, staffId: String) -> String {
        let safeVendor = vendorId.isEmpty ? "unknown" : vendorId.replacingOccurrences(of: "_", with: "-")
        let safeStaff  = staffId.replacingOccurrences(of: "_", with: "-")
        let timestamp  = Int(Date().timeIntervalSince1970 * 1000)
        let random     = String((0..<8).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        return "bp_\(safeVendor)_\(safeStaff)_\(timestamp)_\(random)"
    }

    /// Charges a card order through POST /transactions. `stripePaymentMethodId`
    /// must come from a client-side Stripe tokenization call — raw card data
    /// is never sent to this backend.
    static func createCardTransaction(
        idToken: String,
        vendorId: String,
        customerId: String?,
        items: [CartItem],
        stripePaymentMethodId: String
    ) async throws -> [String: Any] {
        try await createTransaction(
            idToken: idToken, vendorId: vendorId, customerId: customerId,
            items: items, paymentMethod: "card", stripePaymentMethodId: stripePaymentMethodId
        )
    }

    /// Charges an Apple Pay order through the same POST /transactions route.
    /// `stripePaymentMethodId` must come from `STPAPIClient.createPaymentMethod(with: PKPayment)` —
    /// the raw PassKit token is never sent to this backend, only the Stripe
    /// payment method it was exchanged for.
    static func createApplePayTransaction(
        idToken: String,
        vendorId: String,
        customerId: String?,
        items: [CartItem],
        stripePaymentMethodId: String
    ) async throws -> [String: Any] {
        try await createTransaction(
            idToken: idToken, vendorId: vendorId, customerId: customerId,
            items: items, paymentMethod: "apple_pay", stripePaymentMethodId: stripePaymentMethodId
        )
    }

    private static func createTransaction(
        idToken: String,
        vendorId: String,
        customerId: String?,
        items: [CartItem],
        paymentMethod: String,
        stripePaymentMethodId: String
    ) async throws -> [String: Any] {
        let staffId = "self_checkout"
        let token = try await freshToken(idToken)

        var request = URLRequest(url: baseURL.appendingPathComponent("transactions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(generateIdempotencyKey(vendorId: vendorId, staffId: staffId),
                          forHTTPHeaderField: "idempotency-key")

        let itemPayload = items.map { item -> [String: Any] in
            [
                "productId": item.id.uuidString,
                "name":      item.name,
                "qty":       item.qty,
                "unitPrice": item.price
            ]
        }

        let body: [String: Any] = [
            "vendorId":               vendorId,
            "staffId":                staffId,
            "customerId":             customerId ?? "",
            "items":                  itemPayload,
            "paymentMethod":          paymentMethod,
            "stripePaymentMethodId":  stripePaymentMethodId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard (200..<300).contains(http.statusCode) else {
            let message = (json["message"] as? String) ?? (json["error"] as? String)
                ?? "No se pudo procesar el pago (\(http.statusCode))."
            throw APIClientError.server(message)
        }

        return json
    }

    /// Which verified payment backs a pass being registered — POST /passes
    /// requires one of these; a pass can no longer be created from a raw
    /// client-supplied amount (see barpass-v2/supabase/pass_payment_verification.sql).
    enum PassPaymentSource {
        /// A real Stripe-backed order, from POST /transactions' response.
        case order(orderId: String)
        /// A real BarPass Wallet debit, from POST /wallet/spend's response.
        case wallet(transactionId: String)

        fileprivate var jsonValue: [String: Any] {
            switch self {
            case .order(let orderId):
                return ["type": "order", "orderId": orderId]
            case .wallet(let transactionId):
                return ["type": "wallet", "walletTransactionId": transactionId]
            }
        }
    }

    /// Registers a Skip the Line / event ticket / table pass server-side so
    /// its QR code has a real record door staff can check against (see
    /// POST /passes/redeem, used by the web validation page). `amount` is
    /// derived server-side from `paymentSource` — never trusted from here.
    /// Best-effort: the local pass still shows and works offline if this
    /// fails — it just won't be checkable at the door until connectivity
    /// returns.
    static func registerPass(
        idToken: String,
        passCode: String,
        kind: String,
        venueId: String,
        venueName: String,
        quantity: Int,
        validUntil: Date,
        paymentSource: PassPaymentSource
    ) async {
        // Best-effort by design (this function can't throw), so a failed
        // refresh falls back to the caller's token rather than aborting.
        let token = (try? await freshToken(idToken)) ?? idToken

        var request = URLRequest(url: baseURL.appendingPathComponent("passes"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "passCode":      passCode,
            "kind":          kind,
            "venueId":       venueId,
            "venueName":     venueName,
            "quantity":      quantity,
            "validUntil":    ISO8601DateFormatter().string(from: validUntil),
            "paymentSource": paymentSource.jsonValue
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Charges a card and credits the amount to BarPass Wallet via
    /// POST /wallet/topup. Returns the new balance from the server —
    /// the source of truth, never computed locally.
    static func topUpWallet(idToken: String, amount: Double, stripePaymentMethodId: String) async throws -> Double {
        try await postJSON(
            path: "wallet/topup",
            idToken: idToken,
            body: ["amount": amount, "stripePaymentMethodId": stripePaymentMethodId]
        ).balance
    }

    /// Debits BarPass Wallet via POST /wallet/spend. Returns the new balance
    /// and the ledger transaction id — the latter is required by
    /// `registerPass(paymentSource: .wallet(transactionId:))` to prove this
    /// specific debit happened. Throws `.server("insufficient_funds")` if
    /// the server-side balance (not the possibly-stale local one) can't
    /// cover the amount.
    static func spendWallet(idToken: String, amount: Double) async throws -> (balance: Double, transactionId: String) {
        let result = try await postJSON(path: "wallet/spend", idToken: idToken, body: ["amount": amount])
        guard let transactionId = result.transactionId else { throw APIClientError.invalidResponse }
        return (result.balance, transactionId)
    }

    /// Permanently deletes the authenticated user's account (Apple Guideline
    /// 5.1.1(v)). The server deletes only the user the token belongs to; the
    /// client never names a user id. Throws on any non-2xx so the caller can
    /// keep the user signed in and surface the error rather than logging them
    /// out of an account that still exists.
    static func deleteAccount(idToken: String) async throws {
        let token = try await freshToken(idToken)
        var request = URLRequest(url: baseURL.appendingPathComponent("account/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIClientError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let message = (json["message"] as? String) ?? (json["error"] as? String)
                ?? "No se pudo eliminar la cuenta (\(http.statusCode))."
            throw APIClientError.server(message)
        }
    }

    /// Returns the authenticated user's own referral code (server-generated,
    /// created on first call). Feeds ShareManager.shareReferral with a real
    /// code instead of a placeholder. GET /api/referral/code.
    static func fetchReferralCode(idToken: String) async throws -> String {
        let token = try await freshToken(idToken)
        var request = URLRequest(url: baseURL.appendingPathComponent("referral/code"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIClientError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode), let code = json["code"] as? String else {
            throw APIClientError.server((json["error"] as? String) ?? "referral_code_unavailable")
        }
        return code
    }

    /// Attributes the authenticated user (the referred one) to the referrer
    /// who owns `code`. Server-side, idempotent, no points granted here.
    /// POST /api/referral/attribute. Throws on hard failure; `invalid_code`
    /// and `self_referral` surface as `.server` errors the caller can ignore.
    static func attributeReferral(idToken: String, code: String) async throws {
        let token = try await freshToken(idToken)
        var request = URLRequest(url: baseURL.appendingPathComponent("referral/attribute"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIClientError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw APIClientError.server((json["error"] as? String) ?? "attribution_failed")
        }
    }

    /// POSTs JSON, expects `{ success: true, balance: <number>, transactionId?: <string> }`.
    private static func postJSON(
        path: String, idToken: String, body: [String: Any]
    ) async throws -> (balance: Double, transactionId: String?) {
        let token = try await freshToken(idToken)
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIClientError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard (200..<300).contains(http.statusCode) else {
            let message = (json["message"] as? String) ?? (json["error"] as? String)
                ?? "No se pudo procesar la operación (\(http.statusCode))."
            throw APIClientError.server(message)
        }
        guard let balance = json["balance"] as? Double else { throw APIClientError.invalidResponse }
        return (balance, json["transactionId"] as? String)
    }

    // MARK: - AI Concierge (Plan)

    enum ConciergeError: LocalizedError {
        case notConfigured
        case rateLimited
        case invalidRequest
        case unavailable
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:  return "concierge_not_configured"
            case .rateLimited:    return "concierge_rate_limited"
            case .invalidRequest: return "concierge_invalid_request"
            case .unavailable:    return "concierge_unavailable"
            case .network(let m): return m
            }
        }
    }

    /// Wire shape for POST /api/concierge, matching
    /// `barpass-v2/src/features/ai/services/plan-schema.ts` exactly —
    /// decoded into a separate DTO (not `NightPlan` directly) because the
    /// response has no `id`/`createdAt`, which `NightPlan` needs for local
    /// persistence and SwiftUI identity.
    private struct ConciergePlanStopDTO: Decodable {
        let time: String
        let venueSlug: String
        let venueName: String
        let note: String
        let estimatedSpend: Double
    }
    private struct ConciergePlanDTO: Decodable {
        let title: String
        let summary: String
        let stops: [ConciergePlanStopDTO]
        let totalEstimate: Double
        let insiderTip: String
    }

    /// POST /api/concierge — guest-accessible by design (no login wall
    /// anywhere else in Plan's flow), rate-limited server-side by IP.
    /// Callers should treat any thrown error as "fall back to
    /// `NightPlan.local`", never surface it raw (02_UX_ARCHITECTURE.md:
    /// never show technical errors to users).
    static func fetchConciergePlan(
        prompt: String,
        budget: Double? = nil,
        groupSize: Int? = nil,
        neighborhood: String? = nil,
        excludeSlugs: [String] = []
    ) async throws -> NightPlan {
        var request = URLRequest(url: baseURL.appendingPathComponent("concierge"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["prompt": prompt]
        if let budget       { body["budget"] = budget }
        if let groupSize    { body["groupSize"] = groupSize }
        if let neighborhood { body["neighborhood"] = neighborhood }
        if !excludeSlugs.isEmpty { body["excludeSlugs"] = excludeSlugs }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ConciergeError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ConciergeError.unavailable }
        switch http.statusCode {
        case 200..<300: break
        case 429:       throw ConciergeError.rateLimited
        case 503:       throw ConciergeError.notConfigured
        case 400:       throw ConciergeError.invalidRequest
        default:        throw ConciergeError.unavailable
        }

        let dto: ConciergePlanDTO
        do {
            dto = try JSONDecoder().decode(ConciergePlanDTO.self, from: data)
        } catch {
            throw ConciergeError.unavailable
        }

        return NightPlan(
            title: dto.title,
            summary: dto.summary,
            stops: dto.stops.map {
                PlanStop(time: $0.time, venueSlug: $0.venueSlug, venueName: $0.venueName, note: $0.note, estimatedSpend: $0.estimatedSpend)
            },
            totalEstimate: dto.totalEstimate,
            insiderTip: dto.insiderTip
        )
    }
}
