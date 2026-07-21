import Foundation

/// Thin client for the BarPass backend — barpass-v2's Next.js API routes,
/// deployed on Vercel. (The old barpass-miami.vercel.app Express/Firestore
/// backend was never deployed and is superseded by this one.)
enum APIClient {

    static let baseURL = URL(string: "https://barpass-v2.vercel.app/api")!

    enum APIClientError: LocalizedError {
        case notAuthenticated
        case server(String)
        case network(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Debes iniciar sesión para pagar con tarjeta."
            case .server(let msg):  return msg
            case .network(let msg): return msg
            case .invalidResponse:  return "Respuesta inválida del servidor."
            }
        }
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

        var request = URLRequest(url: baseURL.appendingPathComponent("transactions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
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
        var request = URLRequest(url: baseURL.appendingPathComponent("passes"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

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

    /// POSTs JSON, expects `{ success: true, balance: <number>, transactionId?: <string> }`.
    private static func postJSON(
        path: String, idToken: String, body: [String: Any]
    ) async throws -> (balance: Double, transactionId: String?) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
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
}
