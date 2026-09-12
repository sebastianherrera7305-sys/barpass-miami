import Foundation

/// Thin client for the BarPass backend — barpass-v2's Next.js API routes,
/// deployed on Vercel. (The old barpass-miami.vercel.app Express/Firestore
/// backend was never deployed and is superseded by this one.)
enum APIClient {

    static let baseURL = URL(string: "https://barpass-v2.vercel.app/api")!

    /// Not `URLSession.shared`: its default 60s request timeout meant a tap on
    /// Pay inside a venue on bad LTE sat on a spinner for a full minute before
    /// saying anything. 20s is past the p99 of these routes and still short
    /// enough to fail while the user is watching. The concierge stream builds
    /// its own request with an explicit 150s timeout and deliberately does NOT
    /// use this session — that one is a long-lived stream by design.
    private static let httpSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

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
    ///
    /// `idempotencyKey`: pass the SAME key for every retry of one checkout
    /// (see `generateIdempotencyKey`). POST /transactions returns the
    /// existing order for a key it has already charged, so a request whose
    /// response was lost on bad LTE can be re-sent without charging the card
    /// twice. Omitted → a fresh key per call, i.e. no replay protection.
    static func createCardTransaction(
        idToken: String,
        vendorId: String,
        customerId: String?,
        items: [CartItem],
        stripePaymentMethodId: String,
        idempotencyKey: String? = nil
    ) async throws -> [String: Any] {
        try await createTransaction(
            idToken: idToken, vendorId: vendorId, customerId: customerId,
            items: items, paymentMethod: "card", stripePaymentMethodId: stripePaymentMethodId,
            idempotencyKey: idempotencyKey
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
        stripePaymentMethodId: String,
        idempotencyKey: String? = nil
    ) async throws -> [String: Any] {
        try await createTransaction(
            idToken: idToken, vendorId: vendorId, customerId: customerId,
            items: items, paymentMethod: "apple_pay", stripePaymentMethodId: stripePaymentMethodId,
            idempotencyKey: idempotencyKey
        )
    }

    /// The staff id every self-service checkout is recorded under — also
    /// what `generateIdempotencyKey` needs from callers that mint a
    /// per-checkout key up front.
    static let selfCheckoutStaffId = "self_checkout"

    private static func createTransaction(
        idToken: String,
        vendorId: String,
        customerId: String?,
        items: [CartItem],
        paymentMethod: String,
        stripePaymentMethodId: String,
        idempotencyKey: String?
    ) async throws -> [String: Any] {
        let staffId = selfCheckoutStaffId
        let token = try await freshToken(idToken)

        var request = URLRequest(url: baseURL.appendingPathComponent("transactions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey ?? generateIdempotencyKey(vendorId: vendorId, staffId: staffId),
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
            (data, response) = try await httpSession.data(for: request)
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
    /// Codable so a registration can wait on disk in `PassRegistrationOutbox`.
    enum PassPaymentSource: Codable, Equatable, Sendable {
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

        /// What a user can quote to support when a paid pass could not be
        /// issued: the order id or wallet transaction id the money is under.
        var reference: String {
            switch self {
            case .order(let orderId):          return orderId
            case .wallet(let transactionId):   return transactionId
            }
        }
    }

    /// Everything POST /passes needs to mint one pass. Built the moment a
    /// payment succeeds and kept — on disk if necessary — until the server
    /// has confirmed it; re-sending the identical struct is safe because the
    /// route is idempotent on (paymentSource, user) and on (passCode, user).
    struct PassRegistration: Codable, Equatable, Sendable {
        let passCode:      String
        /// "skip_line" | "event_ticket" | "table"
        let kind:          String
        let venueId:       String
        let venueName:     String
        let quantity:      Int
        let validUntil:    Date
        let paymentSource: PassPaymentSource
    }

    /// Why a pass registration did not succeed. The split matters: a
    /// `.transient` failure means the request may never have reached the
    /// server (or its answer never came back) and MUST be retried — the
    /// user has already paid. A `.rejected` one is the server's considered
    /// answer (below the price floor, payment already used, ...) and
    /// retrying the same bytes can only yield the same answer.
    enum PassRegistrationError: LocalizedError, Equatable {
        /// Offline, DNS, TLS, timeout — nothing definitive happened.
        case transient(String)
        /// 5xx / 429 / 408: the server had a bad moment; try again later.
        case serverUnavailable(status: Int, code: String?)
        /// The session could not be refreshed right now. The registration
        /// stays queued until a valid session exists again.
        case sessionExpired
        /// A definitive 4xx with the server's own short error code.
        case rejected(status: Int, code: String, message: String?)

        var isRetryable: Bool {
            switch self {
            case .transient, .serverUnavailable, .sessionExpired: return true
            case .rejected: return false
            }
        }

        /// The server's short code, when it gave one — keyed on by the UI.
        var code: String? {
            switch self {
            case .transient:                        return nil
            case .serverUnavailable(_, let code):   return code
            case .sessionExpired:                   return "session_expired"
            case .rejected(_, let code, _):         return code
            }
        }

        var errorDescription: String? {
            switch self {
            case .transient(let msg):                    return msg
            case .serverUnavailable(let status, let c):  return "HTTP \(status)\(c.map { " (\($0))" } ?? "")"
            case .sessionExpired:                        return L10n.tSync("api.error.sessionExpired")
            case .rejected(let status, let code, let m): return m ?? "\(code) (HTTP \(status))"
            }
        }
    }

    /// The server's record of a registered pass, as far as the app needs it.
    struct RegisteredPass: Equatable, Sendable {
        let serverId: String?
        let passCode: String
    }

    /// Registers a Skip the Line / event ticket / table pass server-side so
    /// its QR code has a real record door staff can check against (see
    /// POST /passes/redeem, used by the web validation page). `amount` is
    /// derived server-side from `paymentSource` — never trusted from here.
    ///
    /// This is NOT best-effort any more. Until 2026-09-12 it ignored the
    /// HTTP status and swallowed every error, so a paid pass could silently
    /// never exist server-side (charged, no QR, turned away at the door).
    /// It now throws a `PassRegistrationError` on anything but a 2xx, and
    /// callers go through `PassRegistrationOutbox`, which persists and
    /// retries the retryable ones. Uses `httpSession` (20s timeout), so a
    /// dead LTE link fails fast instead of holding the screen for a minute.
    static func registerPass(_ registration: PassRegistration, idToken: String) async throws -> RegisteredPass {
        let token: String
        do {
            token = try await freshToken(idToken)
        } catch APIClientError.sessionExpired {
            throw PassRegistrationError.sessionExpired
        } catch {
            throw PassRegistrationError.transient(error.localizedDescription)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("passes"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "passCode":      registration.passCode,
            "kind":          registration.kind,
            "venueId":       registration.venueId,
            "venueName":     registration.venueName,
            "quantity":      registration.quantity,
            "validUntil":    ISO8601DateFormatter().string(from: registration.validUntil),
            "paymentSource": registration.paymentSource.jsonValue
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await httpSession.data(for: request)
        } catch {
            throw PassRegistrationError.transient(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PassRegistrationError.transient("invalid response")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = json["error"] as? String

        switch http.statusCode {
        case 200..<300:
            let pass = json["pass"] as? [String: Any]
            return RegisteredPass(
                serverId: pass?["id"] as? String,
                passCode: (pass?["pass_code"] as? String) ?? registration.passCode
            )
        case 401:
            // The token was refreshed just above; a 401 now means the
            // session itself is gone. Keep the registration; it will go
            // through once the user is signed in again.
            throw PassRegistrationError.sessionExpired
        case 408, 429, 500..<600:
            throw PassRegistrationError.serverUnavailable(status: http.statusCode, code: code)
        default:
            // Never echo json["message"] to the user here — see
            // friendlyServerMessage — but keep it for the outbox log.
            throw PassRegistrationError.rejected(
                status: http.statusCode,
                code: code ?? "http_\(http.statusCode)",
                message: nil
            )
        }
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
            (data, response) = try await httpSession.data(for: request)
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
            (data, response) = try await httpSession.data(for: request)
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
    /// What the app already knows about the user that Remy should too:
    /// where they're checked in (so "what's next" is sequenced from there
    /// and never suggests the place they're standing in), and what they've
    /// favorited (taste). Nothing here triggers a new permission prompt.
    struct ConciergeContext {
        var currentVenueId: String? = nil
        var favoriteVenueIds: [String] = []
        var userLocation: (lat: Double, lng: Double)? = nil

        var isEmpty: Bool { currentVenueId == nil && favoriteVenueIds.isEmpty && userLocation == nil }

        var json: [String: Any] {
            var out: [String: Any] = [:]
            if let currentVenueId { out["currentVenueId"] = currentVenueId }
            if !favoriteVenueIds.isEmpty { out["favoriteVenueIds"] = Array(favoriteVenueIds.prefix(30)) }
            if let userLocation { out["userLocation"] = ["lat": userLocation.lat, "lng": userLocation.lng] }
            return out
        }
    }

    static func streamConciergeChat(messages: [ConciergeChatTurn], city: String?, context: ConciergeContext = ConciergeContext()) -> AsyncThrowingStream<ConciergeStreamEvent, Error> {
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
                    if !context.isEmpty { body["context"] = context.json }
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
            (data, response) = try await httpSession.data(for: request)
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
            (data, response) = try await httpSession.data(for: request)
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
            (data, response) = try await httpSession.data(from: components.url!)
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
