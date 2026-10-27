import SwiftUI

/// Vista full-screen de un post único — foto grande + caption + hora
/// + venue si lo etiquetó. En el propio perfil ofrece "Borrar"; en
/// ajeno ofrece "Reportar" / "Bloquear" (viene en 1.2).
struct PostDetailView: View {
    let post: UserPost
    let isOwner: Bool
    var onDeleted: (UserPost) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var venueStore: VenueStore

    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private let repository: UserPostRepository = RepositoryDependencies.userPost

    /// Catálogo venue (si está) para mostrar el NOMBRE en vez de "en un
    /// venue" genérico — owner 2026-10-27 pidió identidad real en los
    /// posts, no texto chatarra.
    private var taggedVenue: BarPassVenue? {
        guard let vid = post.venueId else { return nil }
        return venueStore.venues.first(where: { $0.id == vid })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        authorRow
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                        imageHero
                        VStack(alignment: .leading, spacing: 10) {
                            if let v = taggedVenue {
                                HStack(spacing: 6) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(Color.bpAmber)
                                    Text(v.name)
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                    if !v.neighborhood.isEmpty {
                                        Text("· \(v.neighborhood)")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            if !post.caption.isEmpty {
                                Text(post.caption)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(post.createdAt.formatted(.relative(presentation: .named)))
                                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.bpDanger)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                        }
                        Spacer(minLength: 60)
                    }
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

    /// Header tipo IG: avatar/initial + "yo" o nombre. Aún sin nombre del
    /// autor desde el server (viene con el perfil join), muestra "Tú" para
    /// el dueño y una pastilla neutra para posts ajenos.
    private var authorRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.bpAmber.opacity(0.2))
                    .frame(width: 34, height: 34)
                Text(isOwner ? "T" : "·")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(isOwner ? "Tú" : "Usuario")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                if let v = taggedVenue {
                    Text(v.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    /// Imagen en aspect-ratio fijo 4:5 (vertical, estándar IG post) —
    /// owner 2026-10-27: "las fotos entren en una sola versión, en un
    /// solo size... no debería [ser pantalla entera], debería ser la
    /// foto". Content mode `.fill` + clip asegura que una foto landscape
    /// o cuadrada se centre y crop en lugar de dejar barras negras.
    private var imageHero: some View {
        let url = post.publicImageURL(baseURL: SupabaseRESTClient.baseURL)
        return GeometryReader { geo in
            CachedImage(
                url: url,
                targetSize: CGSize(width: 1200, height: 1500),
                content: { img in
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.width * 5.0/4.0)
                        .clipped()
                },
                placeholder: { Color.white.opacity(0.05) }
            )
        }
        .aspectRatio(4.0/5.0, contentMode: .fit)
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
