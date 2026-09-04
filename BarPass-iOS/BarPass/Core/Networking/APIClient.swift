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

    /// Turns a server error response into a message safe to show a user.
    /// Deliberately ignores `json["message"]` — several routes (e.g.
    /// POST /transactions on a DB insert failure) echo the raw
    /// Postgres/PostgREST error string there, which can contain table,
    /// column, or constraint names. `json["error"]` is always one of this
    /// app's own short, stable codes, so it's the only field safe to use;
    /// even that is only shown as a last resort after checking for one we
    /// recognize and can phrase properly.
    private static func friendlyServerMessage(_ json: [String: Any], status: Int, fallbackKey: String) -> String {
        if let code = json["error"] as? String {
            switch code {
            case "card_declined":        return L10n.tSync("api.error.cardDeclined")
            case "insufficient_funds":   return L10n.tSync("api.error.insufficientFunds")
            case "rate_limited":         return L10n.tSync("api.error.rateLimited")
            case "invalid_payload":      return L10n.tSync("api.error.invalidPayload")
            case "payments_not_configured": return L10n.tSync("api.error.paymentsNotConfigured")
            case "age_verification_required": return L10n.tSync("api.error.ageVerificationRequired")
            case "ai_not_configured", "ai_unavailable": return L10n.tSync("plan.ai.unavailable")
            default: break
            }
        }
        return L10n.tSync(fallbackKey)
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
            throw APIClientError.server(friendlyServerMessage(json, status: http.statusCode, fallbackKey: "api.error.paymentFailed"))
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
            throw APIClientError.server(friendlyServerMessage(json, status: http.statusCode, fallbackKey: "api.error.deleteAccountFailed"))
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

    /// Real AI itinerary from "Remy" (barpass-v2's /api/concierge — an LLM
    /// call, not a client-side heuristic). Guest-accessible by design (rate
    /// limited by IP server-side, same as the web Concierge), so no idToken.
    /// `excludeSlugs` keeps a session from getting the same plan on "Ask
    /// again". Callers must still have a local fallback for `.network`/
    /// `.server` (ai_not_configured, rate_limited, ai_unavailable) — this
    /// throws on anything that isn't a valid plan, it never returns a
    /// partial/guessed one.
    struct ConciergeStop: Decodable {
        let time: String
        let venueId: String?
        let venueSlug: String
        let venueName: String
        let note: String
        let estimatedSpend: Double
    }
    struct ConciergePlanResponse: Decodable {
        let title: String
        let summary: String
        let stops: [ConciergeStop]
        let totalEstimate: Double
        let insiderTip: String
    }

    /// One chat turn sent to POST /api/concierge — `role` is "user" or "assistant".
    struct ConciergeChatTurn {
        let role: String
        let content: String
    }

    /// A token as it arrives from the streaming concierge chat. The route
    /// injects two 1-byte control markers ahead of the real text: kimi-k3 is
    /// a reasoning model that can spend 20-30s "thinking" before it says
    /// anything user-facing, so `.thinking` fires the instant that reasoning
    /// starts (usually under a second) — the UI can show a live indicator
    /// instead of dead air — and `.delta` carries the actual reply text,
    /// token by token, once it starts.
    enum ConciergeStreamEvent {
        case thinking
        case delta(String)
    }

    /// Streams one turn of the Remy chat. Throws `.network`/`.server` on
    /// failure — callers must have a local fallback (e.g. `NightPlan.sample`)
    /// since this depends on a third-party model that can be slow or, if
    /// misconfigured server-side, unavailable entirely.
    static func streamConciergeChat(messages: [ConciergeChatTurn], city: String?) -> AsyncThrowingStream<ConciergeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("concierge"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    var body: [String: Any] = [
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                    ]
                    if let city { body["city"] = city }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    // A single message can take kimi-k3 well over a minute
                    // end to end (thinking + generation) — this is a chat,
                    // the `.thinking` event is what keeps the UI honest
                    // during that wait, not a short timeout.
                    request.timeoutInterval = 150

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: APIClientError.invalidResponse)
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                        continuation.finish(throwing: APIClientError.server(friendlyServerMessage(json, status: http.statusCode, fallbackKey: "plan.ai.unavailable")))
                        return
                    }

                    var sentThinking = false
                    var pendingUTF8: [UInt8] = []
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if byte == 0x01 {
                            if !sentThinking { sentThinking = true; continuation.yield(.thinking) }
                            continue
                        }
                        if byte == 0x02 { continue }
                        pendingUTF8.append(byte)
                        if let decoded = Self.drainValidUTF8(&pendingUTF8), !decoded.isEmpty {
                            continuation.yield(.delta(decoded))
                        }
                    }
                    if let tail = String(bytes: pendingUTF8, encoding: .utf8), !tail.isEmpty {
                        continuation.yield(.delta(tail))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIClientError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Removes and returns the longest valid-UTF8 prefix of `bytes`, leaving
    /// behind at most 3 trailing bytes that might be an in-progress
    /// multi-byte character (streamed one byte at a time, a Spanish accent
    /// or an emoji can straddle two network chunks).
    private static func drainValidUTF8(_ bytes: inout [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }
        var keep = 0
        while keep < min(3, bytes.count) {
            let cut = bytes.count - keep
            if let s = String(bytes: bytes[0..<cut], encoding: .utf8) {
                bytes.removeFirst(cut)
                return s
            }
            keep += 1
        }
        return nil
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
            throw APIClientError.server(friendlyServerMessage(json, status: http.statusCode, fallbackKey: "api.error.operationFailed"))
        }
        guard let balance = json["balance"] as? Double else { throw APIClientError.invalidResponse }
        return (balance, json["transactionId"] as? String)
    }

    // MARK: - Live events (Ticketmaster, via /api/events/live)

    /// A real, upcoming concert/nightlife event from Ticketmaster Discovery
    /// — separate from a BarPass venue's own `VenueEvent`: not tied to any
    /// venue in our catalog, no BarPass pass/ticket, just discovery + a
    /// link out to buy on Ticketmaster.
    struct LiveEvent: Decodable, Identifiable {
        let id: String
        let name: String
        let date: String?
        let time: String?
        let imageUrl: String?
        let venueName: String?
        let neighborhood: String?
        let url: String
        let priceMin: Double?
        let priceMax: Double?
    }

    static func getLiveEvents(city: String) async throws -> [LiveEvent] {
        var components = URLComponents(url: baseURL.appendingPathComponent("events/live"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "city", value: city)]

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: components.url!)
        } catch {
            throw APIClientError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIClientError.invalidResponse
        }
        struct Envelope: Decodable { let events: [LiveEvent] }
        return try JSONDecoder().decode(Envelope.self, from: data).events
    }
}
