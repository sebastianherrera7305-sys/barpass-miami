import SwiftUI

/// Grid 3-columnas tipo Instagram para los posts de un usuario.
/// Reusa `CachedImage` del Design System para que cada thumbnail no
/// vuelva a descargarse al scroll.
///
/// Vacío-state (0 posts): placeholder discreto "Aún no hay posts" en
/// vez de ocultar la sección — en el perfil propio el placeholder
/// recuerda que falta publicar; en el ajeno, dice que todavía no hay
/// nada. "Próximamente" ni similar, por pedido del owner (10-16).
struct PostGridSection: View {
    let userId: String
    let posts: [UserPost]
    let isOwner: Bool
    var onTapPost: (UserPost) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 3
    )

    var body: some View {
        if posts.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(posts) { post in
                    Button {
                        BPHaptics.light()
                        onTapPost(post)
                    } label: {
                        gridCell(post)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func gridCell(_ post: UserPost) -> some View {
        let url = post.publicImageURL(baseURL: SupabaseRESTClient.baseURL)
        return Color.white.opacity(0.03)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                CachedImage(
                    url: url,
                    targetSize: CGSize(width: 300, height: 300),
                    content: { img in img.resizable().scaledToFill() },
                    placeholder: { Color.white.opacity(0.04) }
                )
            )
            .clipped()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.white.opacity(0.25))
            Text(isOwner ? "Aún no hay posts" : "Sin posts todavía")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            if isOwner {
                Text(L10n.shared.t("post.grid.empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 24)
    }
}
