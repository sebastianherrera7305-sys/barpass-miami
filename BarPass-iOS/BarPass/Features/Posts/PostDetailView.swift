import SwiftUI

/// Vista full-screen de un post único — foto grande + caption + hora
/// + venue si lo etiquetó. En el propio perfil ofrece "Borrar"; en
/// ajeno ofrece "Reportar" / "Bloquear" (viene en 1.2).
struct PostDetailView: View {
    let post: UserPost
    let isOwner: Bool
    var onDeleted: (UserPost) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private let repository: UserPostRepository = RepositoryDependencies.userPost

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        imageHero
                        if !post.caption.isEmpty {
                            Text(post.caption)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                        }
                        metaRow
                            .padding(.horizontal, 20)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.bpDanger)
                                .padding(.horizontal, 20)
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.bpAmber)
                    }
                }
                if isOwner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Borrar post", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .alert(L10n.shared.t("post.detail.deleteConfirm"), isPresented: $showDeleteConfirm) {
                Button(L10n.shared.t("common.cancel"), role: .cancel) { }
                Button(L10n.shared.t("common.delete"), role: .destructive) { performDelete() }
            } message: {
                Text("La foto se elimina del servidor y nadie más la verá.")
            }
            .disabled(isDeleting)
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }

    private var imageHero: some View {
        let url = post.publicImageURL(baseURL: SupabaseRESTClient.baseURL)
        return CachedImage(
            url: url,
            targetSize: CGSize(width: 1200, height: 1200),
            content: { img in img.resizable().scaledToFit() },
            placeholder: { Color.white.opacity(0.05).aspectRatio(1, contentMode: .fit) }
        )
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            // HORA, nunca "aquí ahora" (per owner, 10-16).
            Text(post.createdAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.55))
            if let _ = post.venueId {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bpAmber)
                Text("en un venue")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }

    private func performDelete() {
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                try await repository.delete(post)
                await MainActor.run {
                    BPHaptics.success()
                    onDeleted(post)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    BPHaptics.error()
                }
            }
        }
    }
}
