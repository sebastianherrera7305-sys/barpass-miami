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
    static func fetchBalance(session: AuthSession) async -> Double? {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/wallet_balances?user_id=eq.\(session.user.id)&select=balance") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([BalanceRow].self, from: data)
        else { return nil }
        return rows.first?.balance ?? 0
    }

    private struct BalanceRow: Decodable { let balance: Double }
}
