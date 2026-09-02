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

    func getConversations() async throws -> [PlanConversation] {
        if let cache { return cache }
        let conversations = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([PlanConversation].self, from: $0) } ?? []
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
