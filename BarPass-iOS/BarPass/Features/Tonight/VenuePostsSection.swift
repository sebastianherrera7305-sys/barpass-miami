import SwiftUI

/// "La gente dice" — social feed of a venue: quick posts with caption,
/// emoji and 1-5 ratings. Local-first (posts never lost) with Supabase
/// sync when logged in. Posting awards review XP (once per venue).
struct VenuePostsSection: View {
    let venue: BarPassVenue

    @State private var posts: [VenuePost] = []
    @State private var isLoading = true
    @State private var showComposer = false

    private let repo: PostRepository = RepositoryDependencies.post

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("La gente dice")
                    .font(.bpTitle2()).foregroundStyle(Color.bpInk)
                Spacer()
                Button {
                    BPHaptics.light()
                    showComposer = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.bubble.fill").font(.system(size: 12))
                        Text("Postear").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: "Postear", hint: "Compartir tu experiencia en este venue", isButton: true)
            }

            if isLoading {
                VStack(spacing: 8) {
                    ShimmerSkeleton(height: 70)
                    ShimmerSkeleton(height: 70)
                }
            } else if posts.isEmpty {
                VStack(spacing: 6) {
                    Text("🥂").font(.system(size: 30))
                    Text("Sé el primero en contar cómo estuvo")
                        .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(Color.bpInk.opacity(0.03), in: RoundedRectangle(cornerRadius: BPRadius.md))
            } else {
                ForEach(posts.prefix(5)) { post in postCard(post) }
            }
        }
        .task(id: venue.id) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .bpPostsChanged)) { note in
            guard (note.object as? String) == venue.id else { return }
            Task { await load() }
        }
        .sheet(isPresented: $showComposer) {
            PostComposer(venue: venue) { post in
                posts.insert(post, at: 0)
                Task {
                    try? await repo.create(post)
                    await load()
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(.black)
        }
    }

    private func load() async {
        posts = (try? await repo.posts(venueId: venue.id)) ?? []
        withAnimation(.easeIn(duration: 0.2)) { isLoading = false }
    }

    private func postCard(_ post: VenuePost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.bpAmber.opacity(0.2)).frame(width: 30, height: 30)
                    .overlay(Text(post.emoji ?? "🎉").font(.system(size: 14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(post.authorHandle)")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.bpInk)
                    Text(post.relativeTime)
                        .font(.system(size: 10)).foregroundStyle(Color.bpTextTertiary)
                }
                Spacer()
                if post.pendingSync {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 11)).foregroundStyle(Color.bpTextTertiary)
                }
            }

            Text(post.caption)
                .font(.bpBody()).foregroundStyle(Color.bpInk.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if let r = post.vibeRating { miniRating("Ambiente", r) }
                if let r = post.drinksRating { miniRating("Tragos", r) }
                if let r = post.musicRating { miniRating("Música", r) }
            }
        }
        .padding(12)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpInk.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "Post de \(post.authorHandle): \(post.caption)", hint: "Publicación de la comunidad")
    }

    private func miniRating(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.bpTextSecondary)
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .font(.system(size: 7))
                        .foregroundStyle(i <= value ? Color.bpAmber : Color.bpTextTertiary)
                }
            }
        }
    }
}

// MARK: - Composer

struct PostComposer: View {
    let venue: BarPassVenue
    let onPost: (VenuePost) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var caption = ""
    @State private var emoji = "🎉"
    @State private var vibe = 0
    @State private var drinks = 0
    @State private var music = 0
    @FocusState private var captionFocused: Bool

    private let emojis = ["🎉", "🔥", "🍸", "💃", "🎵", "😍", "🥂", "🌇"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("¿Cómo estuvo \(venue.name)?")
                            .font(.bpTitle2()).foregroundStyle(Color.bpInk)

                        TextField("Contale a la gente…", text: $caption, axis: .vertical)
                            .lineLimit(3...5)
                            .focused($captionFocused)
                            .font(.bpBody()).foregroundStyle(Color.bpInk)
                            .padding(12)
                            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                            .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                                .strokeBorder(captionFocused ? Color.bpAmber.opacity(0.5) : Color.bpInk.opacity(0.08)))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(emojis, id: \.self) { e in
                                    Button {
                                        BPHaptics.light(); emoji = e
                                    } label: {
                                        Text(e).font(.system(size: 22))
                                            .frame(width: 42, height: 42)
                                            .background(emoji == e ? Color.bpAmber.opacity(0.2) : Color.bpInk.opacity(0.05), in: Circle())
                                            .overlay(Circle().strokeBorder(emoji == e ? Color.bpAmber : .clear))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        ratingRow("Ambiente", $vibe)
                        ratingRow("Tragos", $drinks)
                        ratingRow("Música", $music)

                        Button {
                            publish()
                        } label: {
                            Text("Publicar")
                                .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(canPost ? Color.bpAmber : Color.bpAmber.opacity(0.4), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canPost)
                        .bpAccessibility(label: "Publicar", hint: "Publicar tu post en este venue", isButton: true)

                        if AuthService.shared.restoreSession() == nil {
                            Text("Modo invitado: tu post se guarda en este dispositivo. Iniciá sesión para compartirlo con todos.")
                                .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                        }
                    }
                    .padding(BPSpacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(Color.bpAmber)
                }
            }
        }
    }

    private var canPost: Bool {
        !caption.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func publish() {
        let session = AuthService.shared.restoreSession()
        let handle = session?.user.email?.components(separatedBy: "@").first ?? "invitado"
        let post = VenuePost(
            venueId: venue.id,
            userId: session?.user.id,
            authorHandle: handle,
            caption: caption.trimmingCharacters(in: .whitespaces),
            emoji: emoji,
            vibeRating: vibe > 0 ? vibe : nil,
            drinksRating: drinks > 0 ? drinks : nil,
            musicRating: music > 0 ? music : nil,
            pendingSync: true
        )
        // Posting counts as the venue review for XP (once per venue).
        PointsEngine.shared.leaveReview(venueId: venue.id)
        BPHaptics.medium()
        onPost(post)
        dismiss()
    }

    private func ratingRow(_ label: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color.bpTextSecondary)
                .frame(width: 80, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= value.wrappedValue ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.bpAmber)
                        .onTapGesture { BPHaptics.light(); value.wrappedValue = i }
                }
            }
            Spacer()
        }
    }
}


extension Notification.Name {
    static let bpPostsChanged = Notification.Name("bpPostsChanged")
}
