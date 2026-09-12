import SwiftUI
import CoreLocation

@MainActor
final class CheckInStore: ObservableObject {
    /// Shared across the app — RootView's "go home" button needs to know
    /// whether the user is checked in anywhere, regardless of which venue's
    /// CheckInButton last touched this state. Previously each
    /// VenueDetailView owned its own private instance, so navigating
    /// between two venues' detail screens showed stale/inconsistent state
    /// until each independently reloaded.
    static let shared = CheckInStore()

    @Published private(set) var activeCheckin: ActiveCheckin?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Set only when location is permanently denied — CheckInButton reads
    /// this to show a "Abrir Ajustes" affordance instead of implying a
    /// retry would help, which it won't (see LocationService's
    /// isPermissionPermanentlyDenied).
    @Published private(set) var needsSettings = false

    private let repository: any VenueCheckinRepository
    let locationService = LocationService()

    /// A real GPS check at the moment of tap — not "Always" background
    /// location, so it doesn't carry the App Store review scrutiny a
    /// geofencing feature would. Explicit product requirement: without
    /// this, anyone could check in from anywhere, which defeats the whole
    /// point of the Grid (real presence, not self-reported).
    ///
    /// 150m, not 50m: venues aren't points. Factory Town (2026-09-06) is a
    /// seven-acre compound (~170m across) and its pin sits at one edge, so
    /// someone genuinely inside failed the 50m check as "too far". 150m is
    /// still ~one block — you can't check in from the club across the
    /// street, which is the actual abuse this guards against.
    static let maxCheckInDistanceMeters: Double = 150

    /// How much of the GPS's own reported uncertainty we forgive before
    /// comparing to maxCheckInDistanceMeters. Capped — an accuracy reading
    /// of 500m (can happen right after cold-starting the radio) must not
    /// let someone check in from across town, so this stays well inside
    /// what's plausible for someone genuinely standing at the venue.
    static let maxAccuracyForgivenessMeters: Double = 100

    init(repository: any VenueCheckinRepository = RepositoryDependencies.venueCheckin) {
        self.repository = repository
    }

    func load() async {
        activeCheckin = try? await repository.getActiveCheckin()
    }

    func isCheckedIn(at venueId: String) -> Bool {
        activeCheckin?.venueId == venueId || isCheckInPending(at: venueId)
    }

    /// The user checked in, the app accepted it, and the row hasn't reached
    /// Supabase yet. Distinct from `isCheckedIn` on purpose: the button says
    /// "you're in" (true — they are standing there) but shows "subiendo…"
    /// and refuses to check out, because check-out needs the server's own
    /// checkin id, which doesn't exist yet.
    func isCheckInPending(at venueId: String) -> Bool {
        activeCheckin?.venueId != venueId && OfflineQueue.shared.hasPending(.checkIn, venueId: venueId)
    }

    func checkIn(venueId: String, tripId: String?, venueLat: Double, venueLng: Double) async {
        isLoading = true
        errorMessage = nil
        needsSettings = false

        // `.checkIn` policy: accept ≤100m immediately, take ≤200m at the 8s
        // deadline, reject anything wider — a 500m-wide fix says nothing
        // about a 150m radius (see LocationPolicy.checkIn for the arithmetic).
        // Every failure is typed so the message below is the true reason,
        // never a generic "activá tu ubicación" for a GPS that is merely slow.
        let fix: LocationFix
        do {
            fix = try await locationService.requestFix(.checkIn)
        } catch {
            switch error as? LocationError {
            case .permissionDenied?:
                needsSettings = true
                errorMessage = L10n.shared.t("checkin.error.locationDenied")
            case .preciseLocationOff?:
                needsSettings = true
                errorMessage = L10n.shared.t("checkin.error.preciseOff")
            case .timedOut?, .unavailable?:
                errorMessage = L10n.shared.t("checkin.error.locationImprecise")
            case .permissionNotDetermined?, nil:
                needsSettings = locationService.isPermissionPermanentlyDenied
                errorMessage = L10n.shared.t("checkin.error.locationRequired")
            }
            BPHaptics.error()
            isLoading = false
            return
        }
        let userLocation = fix.coordinate
        let venueLocation = CLLocation(latitude: venueLat, longitude: venueLng)
        let distance = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            .distance(from: venueLocation)
        // Forgive up to the GPS's own reported uncertainty (capped) before
        // judging distance — see maxAccuracyForgivenessMeters. Without this,
        // "estoy literalmente al lado del club" failed because an indoor/
        // urban-canyon fix can be 60-150m off even when resolved, and a raw
        // distance check has no way to tell that apart from actually being
        // 150m away.
        let accuracyForgiveness = min(fix.horizontalAccuracy, Self.maxAccuracyForgivenessMeters)
        let effectiveDistance = max(0, distance - accuracyForgiveness)
        guard effectiveDistance <= Self.maxCheckInDistanceMeters else {
            errorMessage = String(format: L10n.shared.t("checkin.error.tooFar"), Int(effectiveDistance))
            BPHaptics.error()
            isLoading = false
            return
        }

        // Inside a packed venue the LTE round trip can take a minute or
        // never finish, and the old code made the user watch a spinner for
        // all of it and then lost the check-in. Four seconds is the whole
        // budget: past that the check-in is queued and the UI moves on. The
        // check_in_venue RPC is idempotent, and the in-flight call is
        // cancelled at the deadline, so nothing lands twice.
        let repo = repository
        let result = await OfflineQueue.attempt(
            seconds: 4,
            classify: { error in
                // Only these two are worth telling the user about — no
                // retry will ever make them succeed.
                guard let error = error as? VenueCheckinError else { return nil }
                switch error {
                case .birthdateRequired: return L10n.tSync("checkin.error.birthdate")
                case .underage: return L10n.tSync("checkin.error.underage")
                case .network: return nil
                }
            },
            operation: { _ = try await repo.checkIn(venueId: venueId, tripId: tripId) }
        )

        switch result {
        case .succeeded:
            await load()
            BPHaptics.success()
            justCheckedIn = true
        case .queue:
            OfflineQueue.shared.enqueue(.checkIn, tripId.map { ["venueId": venueId, "tripId": $0] } ?? ["venueId": venueId])
            // Not an error: the person IS at the venue, the app kept the
            // check-in, and the badge in the button says it's still on its
            // way. Showing a red failure here is what made the app feel
            // broken inside a club.
            BPHaptics.success()
            justCheckedIn = true
        case .permanentFailure(let message):
            errorMessage = message
            BPHaptics.error()
        }
        isLoading = false
    }

    /// True right after a successful check-in — CheckInButton presents
    /// CheckInMomentSheet (post a photo/video from right here, right now).
    @Published var justCheckedIn = false

    /// True right after a successful check-out — the view watches this to
    /// present AgeReportSheet at the one moment we actually know someone
    /// was at the venue and is now leaving.
    @Published var justCheckedOut = false

    func checkOut() async {
        guard let checkinId = activeCheckin?.checkinId else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await repository.checkOut(checkinId: checkinId)
            activeCheckin = nil
            BPHaptics.medium()
            justCheckedOut = true
        } catch {
            errorMessage = L10n.shared.t("checkin.error.generic")
        }
        isLoading = false
    }

}

/// Manual check-in — see the_grid.sql: age is computed server-side from
/// profiles.birthdate, this button never sends a client-supplied age.
struct CheckInButton: View {
    let venueId: String
    let venueName: String
    let venueLat: Double
    let venueLng: Double
    var tripId: String? = nil

    @ObservedObject private var store = CheckInStore.shared
    @ObservedObject private var l10n = L10n.shared
    /// Observed so the badge below disappears by itself the moment the
    /// queued check-in lands.
    @ObservedObject private var queue = OfflineQueue.shared

    private var checkedIn: Bool { store.isCheckedIn(at: venueId) }
    private var checkInPending: Bool { store.isCheckInPending(at: venueId) }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                BPHaptics.light()
                Task {
                    // While the check-in is still queued there is no server
                    // checkin id to close, so check-out genuinely can't run
                    // yet — the button is disabled below rather than
                    // silently doing nothing.
                    if checkedIn { await store.checkOut() }
                    else { await store.checkIn(venueId: venueId, tripId: tripId, venueLat: venueLat, venueLng: venueLng) }
                }
            } label: {
                HStack(spacing: 8) {
                    if store.isLoading {
                        ProgressView().tint(checkedIn ? Color.bpInk : .black).controlSize(.mini)
                    } else {
                        Image(systemName: checkedIn ? "person.fill.checkmark" : "person.fill.badge.plus")
                            .font(.bpScaled(14, weight: .semibold))
                        Text(checkedIn ? l10n.t("checkin.leave") : l10n.t("checkin.here"))
                            .font(.bpScaled(14, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    checkedIn ? Color.bpCardBackground : Color.bpAmber,
                    in: RoundedRectangle(cornerRadius: BPRadius.md)
                )
                .foregroundStyle(checkedIn ? Color.bpInk : .black)
                .overlay(
                    RoundedRectangle(cornerRadius: BPRadius.md)
                        .strokeBorder(checkedIn ? Color.bpBorder : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading || checkInPending)
            .bpAccessibility(label: checkedIn ? l10n.t("checkin.leave") : l10n.t("checkin.here"), isButton: true)

            if checkInPending {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle")
                        .font(.bpScaled(10, weight: .semibold))
                    Text(OfflineQueueStrings.uploading(l10n.language))
                        .font(.bpScaled(11, weight: .semibold))
                }
                .foregroundStyle(Color.bpAmber)
                .bpAccessibility(label: OfflineQueueStrings.willSend(l10n.language))
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.bpScaled(11))
                    .foregroundStyle(Color.bpDanger)
                    .multilineTextAlignment(.center)

                if store.needsSettings {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text(l10n.t("checkin.openSettings"))
                            .font(.bpScaled(11, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $store.justCheckedIn) {
            CheckInMomentSheet(venueId: venueId, venueName: venueName) {
                store.justCheckedIn = false
            }
        }
        .sheet(isPresented: $store.justCheckedOut) {
            AgeReportSheet(venueId: venueId, venueName: venueName) {
                store.justCheckedOut = false
            }
        }
    }
}
