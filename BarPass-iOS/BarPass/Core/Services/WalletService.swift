import Foundation

/// Reads the BarPass Wallet balance directly from Supabase (RLS restricts
/// each user to their own row). Writes never happen here — top-ups and
/// spends always go through the server (see APIClient.topUpWallet/spendWallet)
/// so the balance can never be forged from the client.
enum WalletService {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    /// `nil` means "couldn't confirm the real balance" (network error, bad
    /// response, decode failure) — distinct from a genuine $0 row. Collapsing
    /// both to 0 used to make a real non-zero balance vanish from the UI on
    /// any transient blip (a momentarily expired token, a dropped request),
    /// indistinguishable from having actually spent it all. A row-not-found
    /// (a brand-new account with no wallet_balances row yet) is the one case
    /// that legitimately means $0, and is handled separately below.
    ///
    /// The token passed in by the caller was frequently already stale (the JWT
    /// lives ~59 minutes and this screen may have been open far longer), which
    /// PostgREST answers with a 401 — and a `nil` here makes every purchase
    /// screen hide the wallet option and tell the user to top up money they
    /// already have. So: refresh first via `SupabaseRESTClient.freshSession()`,
    /// and if a 401 still comes back, force one more refresh and retry once
    /// before giving up.
    static func fetchBalance(session: AuthSession) async -> Double? {
        let token = (try? await SupabaseRESTClient.freshSession())?.accessToken ?? session.accessToken
        if let balance = await attempt(userId: session.user.id, token: token) { return balance }

        // One retry on a token the server rejected anyway — refreshIfNeeded()
        // is a no-op for a token that merely *looks* valid, so ask the server.
        guard await AuthService.shared.refreshIfNeeded(),
              let retryToken = AuthService.shared.restoreSession()?.accessToken,
              retryToken != token else { return nil }
        return await attempt(userId: session.user.id, token: retryToken)
    }

    private static func attempt(userId: String, token: String) async -> Double? {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/wallet_balances?user_id=eq.\(userId)&select=balance") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([BalanceRow].self, from: data)
        else { return nil }
        return rows.first?.balance ?? 0
    }

    private struct BalanceRow: Decodable { let balance: Double }
}
