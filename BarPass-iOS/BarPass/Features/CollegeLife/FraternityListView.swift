import SwiftUI

/// Verified fraternity chapters for ONE university, grouped by council
/// (IFC/NPHC/MGC never mixed together — they're different organizations).
/// Every row can answer "where did this come from" via its official source
/// link — that traceability is the whole point of this screen.
struct FraternityListView: View {
    let university: University

    @ObservedObject private var l10n = L10n.shared
    @State private var chapters: [GreekChapter] = []
    @State private var isLoading = true
    @State private var myChapterId: String?
    @State private var savingChapterId: String?
    @State private var showSignInAlert = false

    private var byCouncil: [(council: GreekCouncil, chapters: [GreekChapter])] {
        let grouped = Dictionary(grouping: chapters, by: \.council)
        return GreekCouncil.allCases.compactMap { council in
            guard let list = grouped[council], !list.isEmpty else { return nil }
            return (council, list.sorted { $0.fraternityName < $1.fraternityName })
        }
    }

    var body: some View {
        ZStack {
            BPBackgroundView()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if chapters.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BPSpacing.xl) {
                        ForEach(byCouncil, id: \.council) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.council.label)
                                    .font(.bpCaption())
                                    .foregroundStyle(Color.bpTextSecondary)
                                    .textCase(.uppercase)

                                ForEach(group.chapters) { chapter in
                                    chapterRow(chapter)
                                }
                            }
                        }
                    }
                    .padding(BPSpacing.lg)
                }
            }
        }
        .navigationTitle(l10n.t("greek.fraternityList.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(l10n.t("greek.signIn.title"), isPresented: $showSignInAlert) {
            Button(l10n.t("greek.signIn.ok"), role: .cancel) {}
        } message: {
            Text(l10n.t("greek.signIn.message"))
        }
    }

    private func chapterRow(_ chapter: GreekChapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(chapter.fraternityName)
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                Spacer()
                statusBadge(chapter.status)
            }

            if chapter.needsReview {
                Label(l10n.t("greek.chapter.needsReview"), systemImage: "exclamationmark.triangle.fill")
                    .font(.bpScaled(11))
                    .foregroundStyle(Color.bpDanger)
            }

            HStack {
                if let url = URL(string: chapter.officialSourceURL) {
                    Link(destination: url) {
                        Label(l10n.t("greek.chapter.officialSource"), systemImage: "checkmark.seal.fill")
                            .font(.bpScaled(11, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                    }
                }
                Spacer()
                affiliationButton(chapter)
            }

            if myChapterId == chapter.id {
                HStack(spacing: 16) {
                    NavigationLink(destination: ChapterChatView(chapter: chapter)) {
                        Label(l10n.t("greek.chapter.chat"), systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.bpScaled(12, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                    }
                    NavigationLink(destination: ChapterEventsView(chapter: chapter)) {
                        Label(l10n.t("greek.chapter.events"), systemImage: "calendar")
                            .font(.bpScaled(12, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                    }
                    NavigationLink(destination: ChapterMembersView(chapter: chapter)) {
                        Label(l10n.t("greek.chapter.members"), systemImage: "person.2.fill")
                            .font(.bpScaled(12, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                    }
                }
            }
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
    }

    /// Self-declared, not verified membership — anyone can mark any chapter
    /// as theirs. This just sets `profiles.chapter_id`, same field the
    /// Profile tab's picker writes.
    @ViewBuilder
    private func affiliationButton(_ chapter: GreekChapter) -> some View {
        if myChapterId == chapter.id {
            Label(l10n.t("greek.chapter.yours"), systemImage: "checkmark.circle.fill")
                .font(.bpScaled(11, weight: .semibold))
                .foregroundStyle(Color.bpGreen)
        } else if savingChapterId == chapter.id {
            ProgressView().tint(Color.bpAmber).controlSize(.mini)
        } else {
            Button {
                markAsMine(chapter)
            } label: {
                Text(l10n.t("greek.chapter.markMine"))
                    .font(.bpScaled(11, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
    }

    private func statusBadge(_ status: ChapterStatus) -> some View {
        Text(status.label)
            .font(.bpTiny())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor(status))
    }

    private func badgeColor(_ status: ChapterStatus) -> Color {
        switch status {
        case .active: return Color.bpGreen
        case .suspended, .inactive: return Color.bpDanger
        case .historical, .unknown: return Color.bpTextSecondary
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3")
                .font(.bpScaled(34))
                .foregroundStyle(Color.bpTextTertiary)
            Text(String(format: l10n.t("greek.fraternityList.empty"), university.name))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func load() async {
        async let chaptersTask = RepositoryDependencies.greekLife.chapters(forUniversity: university.id)
        async let affiliationTask = try? RepositoryDependencies.profileAffiliation.getAffiliation()
        chapters = (try? await chaptersTask) ?? []
        myChapterId = (await affiliationTask)?.chapterId
        isLoading = false
    }

    private func markAsMine(_ chapter: GreekChapter) {
        guard AuthService.shared.restoreSession() != nil else {
            showSignInAlert = true
            return
        }
        savingChapterId = chapter.id
        Task {
            do {
                try await RepositoryDependencies.profileAffiliation.setAffiliation(universityId: university.id, chapterId: chapter.id)
                myChapterId = chapter.id
            } catch {
                // Leave myChapterId unchanged — the "Marcar como mío" button
                // just reappears so the user can retry.
            }
            savingChapterId = nil
        }
    }
}
