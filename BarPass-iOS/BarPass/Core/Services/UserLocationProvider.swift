import CoreLocation

/// Single cached location for scoring — fetched once per app session (see
/// `refreshOnce()` caller in `TonightView`), never per card. If the user
/// never grants permission, `coordinate` stays nil forever and every
/// distance-based signal in `ExperienceScorer` is simply absent — never a
/// guessed location.
@MainActor
final class UserLocationProvider: ObservableObject {
    static let shared = UserLocationProvider()

    @Published private(set) var coordinate: CLLocationCoordinate2D?
    private let service = LocationService()
    private var didRequest = false

    private init() {}

    /// Idempotent — safe to call from `.task` on every screen that wants
    /// location-aware scoring without triggering a repeat permission prompt
    /// or a redundant fetch.
    func refreshOnce() {
        guard !didRequest else { return }
        didRequest = true
        Task {
            coordinate = await service.requestOnce()
        }
    }
}
