import Foundation

/// Reads the BarPass Wallet balance directly from Supabase (RLS restricts
/// each user to their own row). Writes never happen here — top-ups and
/// spends always go through the server (see APIClient.topUpWallet/spendWallet)
/// so the balance can never be forged from the client.
enum WalletService {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    static func fetchBalance(session: AuthSession) async -> Double {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/wallet_balances?user_id=eq.\(session.user.id)&select=balance") else {
            return 0
        }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let rows = try? JSONDecoder().decode([BalanceRow].self, from: data),
              let balance = rows.first?.balance
        else { return 0 }
        return balance
    }

    private struct BalanceRow: Decodable { let balance: Double }
}
