import Foundation
import SwiftUI

/// Identidad musical del usuario — derivada on-device de MusicSnapshots.
/// La escucha cruda NUNCA sale del teléfono (ver MUSIC_INTELLIGENCE.md §0).
struct MusicPassport: Codable {
    var topGenres: [GenreWeight]
    var topArtists: [ArtistPlay]
    var hypeScore: Int
    var energy: Int
    var nightPersonality: String
    var newDiscoveries: [String]
    var sources: [MusicSourceKind]
    var updatedAt: Date
}

/// Estado de la capa musical para la UI — estados honestos, sin placeholders.
enum MusicConnectionState: Equatable {
    case notConnected
    case connecting
    case connected
    case denied          // permiso rechazado → link a Ajustes
    case notEntitled     // MusicKit sin habilitar en el dev portal
    case noData          // autorizado pero sin escucha reciente
    case error(String)
}

@MainActor
final class MusicProfileStore: ObservableObject {
    static let shared = MusicProfileStore()

    @Published private(set) var passport: MusicPassport?
    @Published private(set) var state: MusicConnectionState = .notConnected

    private let sources: [MusicSourceKind: MusicSource]

    private static let dir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BarPassMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    private static var passportURL: URL { dir.appendingPathComponent("music_passport.json") }
    private static var snapshotURL: URL { dir.appendingPathComponent("last_snapshot.json") }
    private static var sourcesURL: URL { dir.appendingPathComponent("snapshots_by_source.json") }

    init(sources: [MusicSource] = [AppleMusicSource(), SpotifySource()]) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.kind, $0) })
        passport = (try? Data(contentsOf: Self.passportURL))
            .flatMap { try? JSONDecoder().decode(MusicPassport.self, from: $0) }
        if passport != nil { state = .connected }
    }

    /// Snapshots por proveedor (persistidos) — la base del merge.
    private var snapshotsBySource: [MusicSourceKind: MusicSnapshot] {
        get {
            (try? Data(contentsOf: Self.sourcesURL))
                .flatMap { try? JSONDecoder().decode([MusicSourceKind: MusicSnapshot].self, from: $0) } ?? [:]
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) {
                try? d.write(to: Self.sourcesURL, options: .atomic)
            }
        }
    }

    var connectedSources: [MusicSourceKind] { Array(snapshotsBySource.keys) }

    var hasPassport: Bool { passport != nil }

    /// Permiso + snapshot + HypeEngine + persistencia. Idempotente por proveedor.
    func connect(_ kind: MusicSourceKind = .appleMusic) async {
        guard let source = sources[kind] else { return }
        state = .connecting
        let auth = await source.requestAuthorization()
        switch auth {
        case .denied:
            // Si otro proveedor ya está conectado, no pisamos el passport.
            state = passport != nil ? .connected : .denied
            return
        case .notEntitled:
            state = passport != nil ? .connected : .notEntitled
            return
        case .notDetermined, .authorized: break
        }
        await refresh(kind)
    }

    func refresh(_ kind: MusicSourceKind) async {
        guard let source = sources[kind] else { return }
        do {
            let previous = (try? Data(contentsOf: Self.snapshotURL))
                .flatMap { try? JSONDecoder().decode(MusicSnapshot.self, from: $0) }

            let snapshot = try await source.snapshot(days: 7)
            var bySource = snapshotsBySource
            bySource[kind] = snapshot
            snapshotsBySource = bySource

            guard let merged = HypeEngine.merge(Array(bySource.values)) else { return }
            let summary = HypeEngine.compute(merged, previous: previous)

            let p = MusicPassport(
                topGenres: summary.topGenres,
                topArtists: summary.topArtists,
                hypeScore: summary.hypeScore,
                energy: summary.energy,
                nightPersonality: summary.nightPersonality,
                newDiscoveries: summary.newDiscoveries,
                sources: Array(bySource.keys),
                updatedAt: Date()
            )
            passport = p
            state = .connected
            persist(p, snapshot: merged)
            BPAnalytics.track(.viewScreen("MusicPassportCreated"))
        } catch let e as MusicSourceError {
            let hasPassport = passport != nil
            switch e {
            case .notAuthorized: state = hasPassport ? .connected : .denied
            case .notEntitled:   state = hasPassport ? .connected : .notEntitled
            case .noData:        state = hasPassport ? .connected : .noData
            case .network(let m): state = hasPassport ? .connected : .error(m)
            }
        } catch {
            state = passport != nil ? .connected : .error(String(describing: error))
        }
    }

    private func persist(_ p: MusicPassport, snapshot: MusicSnapshot) {
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: Self.passportURL, options: .atomic) }
        if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: Self.snapshotURL, options: .atomic) }
    }
}
