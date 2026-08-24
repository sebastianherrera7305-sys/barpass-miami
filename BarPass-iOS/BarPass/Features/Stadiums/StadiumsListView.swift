import SwiftUI

/// Entry point into the Interactive Venue Map. Only Hard Rock Stadium is
/// loaded today (see BRIEF-hard-rock-stadium.md) — this list is ready for
/// more without any UI changes once they're researched and loaded.
struct StadiumsListView: View {
    @State private var stadiums: [Stadium] = []
    @State private var isLoading = true
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ZStack {
            BPBackgroundView()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if stadiums.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(stadiums) { stadium in
                            NavigationLink(destination: StadiumDetailView(stadium: stadium)) {
                                stadiumCard(stadium)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(BPSpacing.lg)
                }
            }
        }
        .navigationTitle(l10n.t("stadiums.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func stadiumCard(_ stadium: Stadium) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(
                    LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                Text("🏟️").font(.bpScaled(20))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(stadium.name)
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                Text(stadium.address)
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🏟️").font(.bpScaled(34))
            Text(l10n.t("stadiums.empty"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func load() async {
        stadiums = (try? await RepositoryDependencies.stadium.allStadiums()) ?? []
        isLoading = false
    }
}
