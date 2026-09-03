import SwiftUI

/// Member roster — only reachable once the viewer has marked this chapter
/// as their own (see FraternityListView), same "you're in" gate as chat and
/// events. Server-side (list_chapter_members) re-checks that independently
/// rather than trusting this screen was reached correctly.
struct ChapterMembersView: View {
    let chapter: GreekChapter

    @ObservedObject private var l10n = L10n.shared
    @State private var members: [ChapterMember] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            BPBackgroundView()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
            } else if members.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(format: l10n.t("greek.members.count"), members.count))
                            .font(.bpCaption())
                            .foregroundStyle(Color.bpTextSecondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, BPSpacing.lg)
                            .padding(.top, BPSpacing.sm)

                        ForEach(members) { member in
                            memberRow(member)
                        }
                        .padding(.horizontal, BPSpacing.lg)
                    }
                    .padding(.bottom, BPSpacing.lg)
                }
            }
        }
        .navigationTitle(l10n.t("greek.members.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func memberRow(_ member: ChapterMember) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.bpAmber.opacity(0.15)).frame(width: 40, height: 40)
                Text(String(member.displayName.prefix(1)).uppercased())
                    .font(.bpScaled(15, weight: .bold))
                    .foregroundStyle(Color.bpAmber)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                Text(String(format: l10n.t("greek.members.joined"), formattedDate(member.joinedAt)))
                    .font(.bpScaled(11))
                    .foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()
            Text(String(format: l10n.t("profile.bpxValue"), member.bpxPoints))
                .font(.bpScaled(11, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.bpScaled(34))
                .foregroundStyle(Color.bpTextTertiary)
            Text(l10n.t("greek.members.empty"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: l10n.language.rawValue)
        f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }

    private func load() async {
        errorMessage = nil
        do {
            members = try await RepositoryDependencies.chapterMembers.members()
        } catch {
            errorMessage = l10n.t("greek.members.loadError")
        }
        isLoading = false
    }
}
