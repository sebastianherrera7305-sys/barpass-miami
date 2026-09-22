import Foundation

/// El buzón por donde los dos teléfonos de UNA búsqueda se pasan el token de
/// NearbyInteraction (supabase/safety_groups.sql §5). Implementa el mismo
/// `ProximityTokenChannel` que ya usa el radar del beacon, así que
/// `ProximityRadar` no cambia.
///
/// El token es un blob opaco: NO lleva ubicación, y fuera de la `NISession`
/// que lo generó no significa nada. Ninguna coordenada, ninguna distancia y
/// ninguna dirección pasan por el servidor — la medición vive y muere en los
/// dos teléfonos.
///
/// POLLEA, y sólo durante los segundos en que los tokens cruzan: una vez
/// entregado, NearbyInteraction es teléfono a teléfono y este canal deja de
/// importar. Es un `actor`, no toca UIKit ni estado del main actor.
final actor SafetySeekTokenChannel: ProximityTokenChannel {

    private let seekId: String
    private let repository: SafetyGroupRepository

    private var pump: Task<Void, Never>?
    private var continuation: AsyncStream<ProximityPeerEvent>.Continuation?
    private var lastDeliveredToken: String?
    private var announcedPeerCannotRange = false
    private var consecutiveFailures = 0
    private var myAnnouncement: ProximityAnnouncement?
    private var isClosed = false

    /// Rápido mientras las dos personas se buscan: es la única ventana donde
    /// se nota la latencia.
    private static let pollInterval: Duration = .seconds(3)
    /// Re-publicamos el nuestro cada tanto para que `token_updated_at` del
    /// otro lado siga significando algo.
    private static let heartbeat: Duration = .seconds(45)
    /// Varias fallas seguidas, no una: una request perdida en un sótano no es
    /// un canal muerto.
    private static let failuresBeforeChannelFailed = 4

    init(seekId: String, repository: SafetyGroupRepository = SupabaseSafetyGroupRepository()) {
        self.seekId = seekId
        self.repository = repository
    }

    // MARK: - ProximityTokenChannel

    func publish(_ announcement: ProximityAnnouncement) async throws {
        myAnnouncement = announcement
        try await send(announcement)
    }

    func events() -> AsyncStream<ProximityPeerEvent> {
        AsyncStream { continuation in
            Task { self.attach(continuation) }
        }
    }

    func close() async {
        isClosed = true
        pump?.cancel()
        pump = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Internals

    private func send(_ announcement: ProximityAnnouncement) async throws {
        switch announcement {
        case .token(let data):
            try await repository.publishSeekToken(seekId: seekId,
                                                  token: data.base64EncodedString(),
                                                  canRange: true)
        case .cannotRange:
            // Se publica como un HECHO, no como silencio: el otro lado tiene
            // que dejar de esperar un token que no va a llegar nunca.
            try await repository.publishSeekToken(seekId: seekId, token: nil, canRange: false)
        }
    }

    private func attach(_ continuation: AsyncStream<ProximityPeerEvent>.Continuation) {
        guard !isClosed else { continuation.finish(); return }
        self.continuation = continuation
        guard pump == nil else { return }
        pump = Task { [weak self] in
            var sinceHeartbeat: Duration = .zero
            while !Task.isCancelled {
                await self?.poll()
                sinceHeartbeat += Self.pollInterval
                if sinceHeartbeat >= Self.heartbeat {
                    sinceHeartbeat = .zero
                    await self?.reannounce()
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func reannounce() async {
        guard let myAnnouncement else { return }
        try? await send(myAnnouncement)
    }

    private func poll() async {
        do {
            let peers = try await repository.seekTokens(seekId: seekId)
            consecutiveFailures = 0
            guard let peer = peers.first else { return }

            if !peer.canRange, !announcedPeerCannotRange {
                announcedPeerCannotRange = true
                continuation?.yield(.peerCannotRange)
                return
            }
            // Un token DISTINTO es una reconexión, no un duplicado: el otro
            // reinició su NISession y el token viejo ya no sirve.
            guard let raw = peer.discoveryToken, raw != lastDeliveredToken,
                  let data = Data(base64Encoded: raw) else { return }
            lastDeliveredToken = raw
            announcedPeerCannotRange = false
            continuation?.yield(.token(data))

        } catch SafetyGroupError.seekNotFound {
            // La búsqueda terminó, venció, o el liderazgo cambió de persona:
            // un HECHO de que esto se acabó, que es justo por lo que el RPC
            // levanta un error en vez de devolver cero filas.
            continuation?.yield(.peerLeft)
            await close()

        } catch {
            // NO es `.peerLeft`: dejamos de aprender cosas NUEVAS del otro,
            // que no es lo mismo que que se haya ido — NearbyInteraction
            // sigue midiendo sin red.
            consecutiveFailures += 1
            if consecutiveFailures == Self.failuresBeforeChannelFailed {
                continuation?.yield(.channelFailed(error))
            }
        }
    }
}
