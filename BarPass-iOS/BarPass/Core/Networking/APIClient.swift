import Foundation

/// Thin client for the BarPass backend (api/server.js on Vercel).
/// Mirrors the base URL the web app already uses in production (see
/// barpass-miami.html → `https://barpass-miami.vercel.app`).
enum APIClient {

    static let baseURL = URL(string: "https://barpass-miami.vercel.app/api")!

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

    /// Charges a card (or Apple Pay) order through POST /transactions.
    /// `stripePaymentMethodId` must come from a client-side Stripe tokenization call —
    /// raw card data is never sent to this backend.
    static func createCardTransaction(
        idToken: String,
        vendorId: String,
        customerId: String?,
        items: [CartItem],
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
            "paymentMethod":          "card",
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
}
