import Foundation
import SwiftUI

/// Identidad musical del usuario — derivada on-device de MusicSnapshots.
/// La escucha cruda NUNCA sale del teléfono (ver MUSIC_INTELLIGENCE.md §0).
struct MusicPassport: Codable {
    var topGenres: [GenreWeight]
    var topArtists: [String]
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

    private let source: MusicSource

    private static let dir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BarPassMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    private static var passportURL: URL { dir.appendingPathComponent("music_passport.json") }
    private static var snapshotURL: URL { dir.appendingPathComponent("last_snapshot.json") }

    init(source: MusicSource = AppleMusicSource()) {
        self.source = source
        passport = (try? Data(contentsOf: Self.passportURL))
            .flatMap { try? JSONDecoder().decode(MusicPassport.self, from: $0) }
        if passport != nil { state = .connected }
    }

    var hasPassport: Bool { passport != nil }

    /// Permiso + snapshot + HypeEngine + persistencia. Idempotente.
    func connect() async {
        state = .connecting
        let auth = await source.requestAuthorization()
        switch auth {
        case .denied:       state = .denied; return
        case .notEntitled:  state = .notEntitled; return
        case .notDetermined, .authorized: break
        }
        await refresh()
    }

    func refresh() async {
        do {
            let previous = (try? Data(contentsOf: Self.snapshotURL))
                .flatMap { try? JSONDecoder().decode(MusicSnapshot.self, from: $0) }

            let snapshot = try await source.snapshot(days: 7)
            let summary = HypeEngine.compute(snapshot, previous: previous)

            let p = MusicPassport(
                topGenres: summary.topGenres,
                topArtists: summary.topArtists,
                hypeScore: summary.hypeScore,
                energy: summary.energy,
                nightPersonality: summary.nightPersonality,
                newDiscoveries: summary.newDiscoveries,
                sources: [source.kind],
                updatedAt: Date()
            )
            passport = p
            state = .connected
            persist(p, snapshot: snapshot)
            BPAnalytics.track(.viewScreen("MusicPassportCreated"))
        } catch let e as MusicSourceError {
            switch e {
            case .notAuthorized: state = .denied
            case .notEntitled:   state = .notEntitled
            case .noData:        state = .noData
            case .network(let m): state = .error(m)
            }
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func persist(_ p: MusicPassport, snapshot: MusicSnapshot) {
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: Self.passportURL, options: .atomic) }
        if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: Self.snapshotURL, options: .atomic) }
    }
}
