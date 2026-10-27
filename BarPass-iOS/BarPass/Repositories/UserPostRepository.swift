import Foundation

/// Social posts contract — upload foto, listar grid, borrar.
///
/// Toda la visibilidad vive en Supabase RLS (ver user_posts_schema.sql):
/// este cliente nunca filtra posts por amistad/privacidad propio; manda
/// la query y el server devuelve solo lo que la RLS admite. Un cliente
/// comprometido que intente leer posts privados ajenos recibe []
/// vacío, no un error, igual que `profiles`.
protocol UserPostRepository: Sendable {
    /// Lista los posts de un usuario — propio o ajeno. RLS gatea:
    /// propio → siempre; ajeno → amigo-mutuo OR autor-no-privado.
    func posts(forUser userId: String, limit: Int) async throws -> [UserPost]

    /// Social timeline feed: latest N posts across every author the viewer
    /// can see. RLS does the visibility filter — a comprometed client that
    /// asks for everything still only gets back the posts whose author is
    /// (not private) OR (mutual friend) and no block between them. Used by
    /// SocialV2View home to surface posts (owner report 2026-10-27 "los
    /// posts no se postean" — they posted fine, they were just buried in
    /// profile with no social surface).
    func timeline(limit: Int) async throws -> [UserPost]

    /// Conteo del grid del perfil. Usa el helper RPC posts_count_for
    /// que respeta las mismas políticas de visibilidad.
    func count(forUser userId: String) async throws -> Int

    /// Sube la foto (metadata ya debe estar stripped — ver
    /// PostImageProcessor.stripAndEncode antes) + crea la fila.
    /// Devuelve el post persistido.
    func create(
        imageJPEG: Data,
        caption: String,
        venueId: String?
    ) async throws -> UserPost

    /// Borra el post del DB PRIMERO, después el archivo del bucket.
    /// Owner approved orden 2026-10-16: si falla el archivo queda
    /// huérfano pero nadie lo ve (la row ya se fue). Mejor que el
    /// inverso (row vive, foto gone, grid muestra placeholder).
    func delete(_ post: UserPost) async throws
}

/// Errores dominio-específicos para que la UI pueda discriminar entre
/// "foto no se procesó" vs "upload cayó" vs "insert RLS-rejected".
enum UserPostError: LocalizedError {
    case imageProcessingFailed
    case uploadFailed(String)
    case insertFailed(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed: "No pudimos procesar la foto. Probá con otra."
        case .uploadFailed(let m):   "No se pudo subir la foto. \(m)"
        case .insertFailed(let m):   "No se pudo publicar el post. \(m)"
        case .notAuthenticated:      "Iniciá sesión para publicar."
        }
    }
}

final actor SupabaseUserPostRepository: UserPostRepository {

    private static let bucket = "user-posts"
    private static let chunkSize = 6 * 1024 * 1024
    private static let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    // MARK: - Reads

    func posts(forUser userId: String, limit: Int = 60) async throws -> [UserPost] {
        let session = try await SupabaseRESTClient.freshSession()
        let req = try SupabaseRESTClient.request(
            "GET", path: "posts",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,image_path,caption,venue_id,created_at"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "order",   value: "created_at.desc"),
                URLQueryItem(name: "limit",   value: String(limit)),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(req)
        return try SupabaseRESTClient.decoder.decode([UserPost].self, from: data)
    }

    func timeline(limit: Int = 30) async throws -> [UserPost] {
        let session = try await SupabaseRESTClient.freshSession()
        // No user_id filter — RLS trims to the viewer-visible subset
        // (SELECT policy in user_posts_schema.sql line 160+): own posts
        // always, others only when author is public or mutual friend and
        // no block exists. One round trip, one query, all gated server-
        // side; nothing to filter client-side.
        let req = try SupabaseRESTClient.request(
            "GET", path: "posts",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,image_path,caption,venue_id,created_at"),
                URLQueryItem(name: "order",   value: "created_at.desc"),
                URLQueryItem(name: "limit",   value: String(limit)),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(req)
        return try SupabaseRESTClient.decoder.decode([UserPost].self, from: data)
    }

    func count(forUser userId: String) async throws -> Int {
        let session = try await SupabaseRESTClient.freshSession()
        let body = try JSONSerialization.data(withJSONObject: ["p_user": userId])
        let req = try SupabaseRESTClient.request(
            "POST", path: "rpc/posts_count_for",
            body: body, accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(req)
        if let n = try? SupabaseRESTClient.decoder.decode(Int.self, from: data) { return n }
        if let s = String(data: data, encoding: .utf8), let n = Int(s) { return n }
        return 0
    }

    // MARK: - Create (upload file → insert row)

    func create(imageJPEG: Data, caption: String, venueId: String?) async throws -> UserPost {
        let session = try await SupabaseRESTClient.freshSession()
        let postId = UUID().uuidString
        let imagePath = "\(session.user.id)/\(postId).jpg"

        // 1. Upload a Storage (bucket user-posts). TUS resumable igual
        //    que VenueMediaRepository, pero bucket distinto y path con
        //    el postId para que el CHECK posts_path_belongs_to_user se
        //    cumpla antes de que exista la row.
        try await uploadToBucket(imageJPEG: imageJPEG, path: imagePath, accessToken: session.accessToken)

        // 2. Insert la row. Si la RLS rechaza (p.ej. venue_id apunta a
        //    un venue excluido), el storage ya tiene el archivo; el
        //    cliente lo trata como fallo y los huérfanos se limpian
        //    por cron. Documentar el riesgo pero no complicar el
        //    flujo con un rollback: la ventana es microsegundos.
        struct NewRow: Encodable {
            let id: String
            let userId: String
            let imagePath: String
            let caption: String
            let venueId: String?
        }
        let row = NewRow(
            id: postId,
            userId: session.user.id,
            imagePath: imagePath,
            caption: caption,
            venueId: venueId
        )
        let body = try SupabaseRESTClient.encoder.encode(row)

        let req = try SupabaseRESTClient.request(
            "POST", path: "posts",
            queryItems: [URLQueryItem(name: "select", value: "id,user_id,image_path,caption,venue_id,created_at")],
            body: body,
            accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=representation"]
        )
        do {
            let data = try await SupabaseRESTClient.send(req)
            let posts = try SupabaseRESTClient.decoder.decode([UserPost].self, from: data)
            guard let post = posts.first else {
                throw UserPostError.insertFailed("respuesta vacía")
            }
            return post
        } catch {
            // Si el insert falla, intentar limpiar el archivo subido.
            // Best-effort — si también falla, queda huérfano.
            try? await deleteObject(path: imagePath, accessToken: session.accessToken)
            throw error
        }
    }

    // MARK: - Delete (row first, then file)

    func delete(_ post: UserPost) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        // 1. Row primero. Si acá falla, el archivo sigue y el grid lo
        //    sigue mostrando — comportamiento esperado.
        let req = try SupabaseRESTClient.request(
            "DELETE", path: "posts",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(post.id)")],
            accessToken: session.accessToken
        )
        _ = try await SupabaseRESTClient.send(req)

        // 2. Archivo después. Best-effort — si falla queda huérfano
        //    pero nadie lo descubre (row ya no existe, URL es un UUID
        //    random).
        try? await deleteObject(path: post.imagePath, accessToken: session.accessToken)
    }

    // MARK: - Storage internals

    private func uploadToBucket(imageJPEG: Data, path: String, accessToken: String) async throws {
        let total = imageJPEG.count
        guard total > 0 else { throw UserPostError.imageProcessingFailed }

        func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }
        let authHeaders = [
            "apikey": SupabaseRESTClient.anonKey,
            "Authorization": "Bearer \(accessToken)",
            "Tus-Resumable": "1.0.0",
        ]

        // Create resumable upload
        guard let createURL = URL(string: "\(SupabaseRESTClient.baseURL)/storage/v1/upload/resumable") else {
            throw URLError(.badURL)
        }
        var create = URLRequest(url: createURL)
        create.httpMethod = "POST"
        authHeaders.forEach { create.setValue($1, forHTTPHeaderField: $0) }
        create.setValue(String(total), forHTTPHeaderField: "Upload-Length")
        create.setValue(
            "bucketName \(b64(Self.bucket)),objectName \(b64(path)),contentType \(b64("image/jpeg"))",
            forHTTPHeaderField: "Upload-Metadata"
        )
        create.setValue("true", forHTTPHeaderField: "x-upsert")
        let (createData, createResp) = try await Self.urlSession.data(for: create)
        guard let createHTTP = createResp as? HTTPURLResponse, 200..<300 ~= createHTTP.statusCode,
              let location = createHTTP.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location, relativeTo: createURL) else {
            throw UserPostError.uploadFailed(String(data: createData, encoding: .utf8) ?? "create failed")
        }

        // Chunked PATCH
        var offset = 0
        while offset < total {
            let end = min(offset + Self.chunkSize, total)
            let chunk = imageJPEG.subdata(in: offset..<end)
            var patch = URLRequest(url: uploadURL)
            patch.httpMethod = "PATCH"
            authHeaders.forEach { patch.setValue($1, forHTTPHeaderField: $0) }
            patch.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
            patch.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            let (patchData, patchResp) = try await Self.urlSession.upload(for: patch, from: chunk)
            guard let patchHTTP = patchResp as? HTTPURLResponse, 200..<300 ~= patchHTTP.statusCode else {
                throw UserPostError.uploadFailed(String(data: patchData, encoding: .utf8) ?? "chunk failed")
            }
            offset = Int(patchHTTP.value(forHTTPHeaderField: "Upload-Offset") ?? "") ?? end
        }
    }

    private func deleteObject(path: String, accessToken: String) async throws {
        guard let url = URL(string: "\(SupabaseRESTClient.baseURL)/storage/v1/object/\(Self.bucket)/\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(SupabaseRESTClient.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, resp) = try await Self.urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}
