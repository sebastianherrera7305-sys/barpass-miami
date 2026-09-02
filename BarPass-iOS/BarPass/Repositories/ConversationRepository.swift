import Foundation

protocol ConversationRepository: Sendable {
    func getConversations() async throws -> [PlanConversation]
    func saveConversation(_ conversation: PlanConversation) async throws
    func deleteConversation(_ conversation: PlanConversation) async throws
}

/// Disk-backed conversation storage (same pattern as `LocalPlanRepository`)
/// — the fallback for guests, who can't write to Supabase (RLS scopes
/// `plan_conversations` to `auth.uid()`, same as `night_plans`/`trips`).
/// The in-progress conversation itself still works fully for guests; it
/// just doesn't sync across devices or survive a reinstall.
actor LocalConversationRepository: ConversationRepository {
    private let fileURL: URL
    private var cache: [PlanConversation]?

    init() {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let base = baseDir.appendingPathComponent("BarPassPlanConversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("conversations.json")
    }

    /// Decodes entries individually (2026-09-02 bug fix, same reasoning as
    /// `LocalPlanRepository.getPlans`) — a whole-array decode is atomic, so
    /// one legacy-shape cached conversation would otherwise silently wipe
    /// every other locally-cached one.
    func getConversations() async throws -> [PlanConversation] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            cache = []
            return []
        }
        let conversations = objects.compactMap { obj -> PlanConversation? in
            guard let objData = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return try? JSONDecoder().decode(PlanConversation.self, from: objData)
        }
        cache = conversations
        return conversations
    }

    func saveConversation(_ conversation: PlanConversation) async throws {
        var conversations = try await getConversations()
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
        try write(conversations)
    }

    func deleteConversation(_ conversation: PlanConversation) async throws {
        var conversations = try await getConversations()
        conversations.removeAll { $0.id == conversation.id }
        try write(conversations)
    }

    private func write(_ conversations: [PlanConversation]) throws {
        cache = conversations
        try JSONEncoder().encode(conversations).write(to: fileURL, options: .atomic)
    }
}

/// Routes to Supabase when signed in, local disk otherwise — see
/// `CompositePlanRepository` (PlanRepository.swift) for the same fix and
/// its rationale.
actor CompositeConversationRepository: ConversationRepository {
    private let remote: ConversationRepository = SupabaseConversationRepository()
    private let local: ConversationRepository = LocalConversationRepository()

    private var isSignedIn: Bool { AuthService.shared.restoreSession() != nil }

    func getConversations() async throws -> [PlanConversation] {
        isSignedIn ? try await remote.getConversations() : try await local.getConversations()
    }

    func saveConversation(_ conversation: PlanConversation) async throws {
        if isSignedIn { try await remote.saveConversation(conversation) } else { try await local.saveConversation(conversation) }
    }

    func deleteConversation(_ conversation: PlanConversation) async throws {
        if isSignedIn { try await remote.deleteConversation(conversation) } else { try await local.deleteConversation(conversation) }
    }
}
