import SwiftUI
import PhotosUI

/// Sheet para crear un post nuevo: 1 foto + caption opcional + venue
/// opcional (etiquetado). Flujo:
///   1. PhotosPicker → user elige foto (HEIC/JPEG/PNG).
///   2. Preview de la foto arriba del composer.
///   3. Caption opcional (hasta 500 chars).
///   4. Venue etiquetado opcional (chip "Tagar venue" → sheet con picker).
///   5. "Publicar" → PostImageProcessor.stripAndEncode (EXIF/GPS out) →
///      SupabasePostRepository.create → notifica al grid del perfil.
///
/// Owner approved (10-16):
///   · 1 sola foto por post en 1.1 (multi-foto puede venir después).
///   · Venue opcional, no bloquea publicar.
///   · Caption vacío válido.
///   · "Tomar foto" via cámara NO en 1.1 (requiere NSCameraUsageDescription
///     ya honesto pero sin UI de captura todavía — queda para 1.2).
struct PostComposerView: View {
    /// Se dispara cuando el post se publicó OK para que el grid del
    /// perfil lo prepend sin tener que re-fetchear la lista entera.
    var onPublished: (UserPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImageData: Data?
    @State private var previewImage: UIImage?
    @State private var caption: String = ""
    @State private var selectedVenue: BarPassVenue?
    @State private var showVenuePicker = false
    @State private var isPublishing = false
    @State private var errorMessage: String?

    private let repository: UserPostRepository = RepositoryDependencies.userPost

    var body: some View {
        NavigationStack {
            ZStack {
                // Owner Build 141, 2026-10-28: "las dos pantallas necesitan
                // una esencia de nosotros". Antes era un fondo negro plano
                // sin brand presence. BrandFlashBackground pinta bloques
                // zine/flash (amber + coral + violet + bronze) con blur
                // suave — da identidad sin usar el eye (que ya se usa en
                // Tonight/Explore/etc.).
                BrandFlashBackground(seed: 7, intensity: 0.55)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Hero display: "Nuevo / post." con remate serif
                        // italic — el mismo lenguaje que el header de
                        // Tonight / Profile ("Your / trips", "My / night").
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(l10n.t("post.compose.eyebrowKicker"))
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text(l10n.t("post.compose.eyebrowTail"))
                                .font(.system(size: 24, design: .serif).italic())
                                .foregroundStyle(Color.bpAmberBright)
                            Spacer()
                        }
                        .padding(.top, 6)

                        imagePreview
                        captionField
                        venueChip
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.bpDanger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("tripCreate.cancel")) { dismiss() }
                        .foregroundStyle(Color.white.opacity(0.7))
                        .disabled(isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isPublishing ? "Publicando…" : "Publicar") { publish() }
                        .fontWeight(.heavy)
                        .foregroundStyle(canPublish ? Color.bpAmber : Color.white.opacity(0.3))
                        .disabled(!canPublish || isPublishing)
                }
            }
            // Bug (TestFlight 2026-10-27, "cuando voy a agregar una foto no
            // me deja agregarla"): the previous Binding read `showsPicker`
            // but its setter never wrote the dismiss (`false`) back —
            // only cleared `pickerItem`. After the first open the flag
            // stayed `true` forever, so a second tap on "Elegí una foto"
            // was a no-op (SwiftUI thought the picker was still presented).
            // Pass `$showsPicker` directly so SwiftUI drives both edges.
            .photosPicker(
                isPresented: $showsPicker,
                selection: $pickerItem,
                matching: .images
            )
            .sheet(isPresented: $showVenuePicker) {
                PostVenuePickerView(selected: $selectedVenue)
            }
            .onChange(of: pickerItem) { _, item in
                loadPicked(item: item)
            }
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }

    private var canPublish: Bool { pickedImageData != nil && !isPublishing }

    @State private var showsPicker = false

    // MARK: - Sub-views

    /// 1:1 square preview area that matches an IG-style post. On empty
    /// state the whole square is tappable (not just the center icon) so
    /// the picker opens from anywhere; the dashed amber border reads as
    /// a dropzone, not a disabled state. On loaded state the "replace"
    /// control sits top-right over the photo with a glass circle so it
    /// stays visible on bright or dark images.
    private var imagePreview: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                if let img = previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    VStack {
                        HStack {
                            Spacer()
                            Button { showsPicker = true } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                        }
                        Spacer()
                    }
                } else {
                    Button { showsPicker = true } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.bpAmber.opacity(0.12), Color.bpAmber.opacity(0.03)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.bpAmber.opacity(0.55),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                            VStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.bpAmber.opacity(0.18))
                                        .frame(width: 68, height: 68)
                                    Image(systemName: "photo.badge.plus.fill")
                                        .font(.system(size: 32, weight: .semibold))
                                        .foregroundStyle(Color.bpAmber)
                                }
                                VStack(spacing: 4) {
                                    Text(l10n.t("post.compose.pickPhoto"))
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text(l10n.t("post.compose.photoHint"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.white.opacity(0.55))
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l10n.t("post.compose.captionLabel"))
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                // Only show the counter when the user is getting close
                // to the cap — the mid-counter was noise at 0/500.
                if caption.count >= 400 {
                    Text("\(caption.count) / 500")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(caption.count >= 500 ? Color.bpDanger : Color.white.opacity(0.5))
                }
            }
            TextField(
                "",
                text: $caption,
                prompt: Text(l10n.t("post.compose.captionPrompt")).foregroundStyle(Color.white.opacity(0.4)),
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(.system(size: 15, design: .rounded))
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14)))
            .onChange(of: caption) { _, new in
                if new.count > 500 { caption = String(new.prefix(500)) }
            }
        }
    }

    private var venueChip: some View {
        Button {
            showVenuePicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedVenue == nil ? "mappin.circle" : "mappin.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedVenue?.name ?? "Tagar venue · opcional")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if let v = selectedVenue, !v.neighborhood.isEmpty {
                        Text(v.neighborhood)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                Spacer()
                if selectedVenue != nil {
                    Button {
                        selectedVenue = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .padding(6)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func loadPicked(item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    self.pickedImageData = data
                    self.previewImage = UIImage(data: data)
                }
            }
        }
    }

    private func publish() {
        guard let raw = pickedImageData else { return }
        isPublishing = true
        errorMessage = nil
        Task {
            // 1. Strip EXIF/GPS forensic-grade. CGImageDestination con
            //    properties = {} — cero metadata del original.
            guard let clean = PostImageProcessor.stripAndEncode(raw, maxDimension: 1600, quality: 0.82) else {
                await MainActor.run {
                    errorMessage = UserPostError.imageProcessingFailed.errorDescription
                    isPublishing = false
                }
                return
            }
            do {
                let post = try await repository.create(
                    imageJPEG: clean,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    venueId: selectedVenue?.id
                )
                await MainActor.run {
                    BPHaptics.success()
                    onPublished(post)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isPublishing = false
                    BPHaptics.error()
                }
            }
        }
    }
}

/// Picker reducido para elegir el venue a etiquetar — muestra la
/// lista de VenueStore filtrada por la ciudad actual, con search bar.
private struct PostVenuePickerView: View {
    @Binding var selected: BarPassVenue?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var venueStore: VenueStore
    @ObservedObject private var l10n = L10n.shared
    @State private var query: String = ""

    private var filtered: [BarPassVenue] {
        let base = venueStore.venues
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return base.prefix(80).map { $0 } }
        let q = query.lowercased()
        return base.filter { $0.name.lowercased().contains(q) || $0.neighborhood.lowercased().contains(q) }
            .prefix(80).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { v in
                    Button {
                        selected = v
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(v.neighborhood)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            if selected?.id == v.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.bpAmber)
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(l10n.t("post.compose.tagVenue"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Buscar venue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("common.cancel")) { dismiss() }
                        .foregroundStyle(Color.bpAmber)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(l10n.t("post.compose.noVenue")) {
                        selected = nil
                        dismiss()
                    }
                    .foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }
}
