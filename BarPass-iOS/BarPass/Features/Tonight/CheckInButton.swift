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
    static let maxCheckInDistanceMeters: Double = 50

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
        activeCheckin?.venueId == venueId
    }

    func checkIn(venueId: String, tripId: String?, venueLat: Double, venueLng: Double) async {
        isLoading = true
        errorMessage = nil
        needsSettings = false

        guard let userLocation = await locationService.requestOnce() else {
            needsSettings = locationService.isPermissionPermanentlyDenied
            errorMessage = needsSettings
                ? L10n.shared.t("checkin.error.locationDenied")
                : L10n.shared.t("checkin.error.locationRequired")
            BPHaptics.error()
            isLoading = false
            return
        }
        let venueLocation = CLLocation(latitude: venueLat, longitude: venueLng)
        let distance = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            .distance(from: venueLocation)
        // Forgive up to the GPS's own reported uncertainty (capped) before
        // judging distance — see maxAccuracyForgivenessMeters. Without this,
        // "estoy literalmente al lado del club" failed because an indoor/
        // urban-canyon fix can be 60-150m off even when resolved, and a raw
        // distance check has no way to tell that apart from actually being
        // 150m away.
        let accuracyForgiveness = min(locationService.lastHorizontalAccuracy ?? 0, Self.maxAccuracyForgivenessMeters)
        let effectiveDistance = max(0, distance - accuracyForgiveness)
        guard effectiveDistance <= Self.maxCheckInDistanceMeters else {
            errorMessage = String(format: L10n.shared.t("checkin.error.tooFar"), Int(effectiveDistance))
            BPHaptics.error()
            isLoading = false
            return
        }

        do {
            _ = try await repository.checkIn(venueId: venueId, tripId: tripId)
            await load()
            BPHaptics.success()
        } catch let error as VenueCheckinError {
            errorMessage = Self.message(for: error)
            BPHaptics.error()
        } catch {
            errorMessage = L10n.shared.t("checkin.error.generic")
            BPHaptics.error()
        }
        isLoading = false
    }

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

    private static func message(for error: VenueCheckinError) -> String {
        switch error {
        case .birthdateRequired: return L10n.shared.t("checkin.error.birthdate")
        case .underage: return L10n.shared.t("checkin.error.underage")
        case .network: return L10n.shared.t("checkin.error.generic")
        }
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

    private var checkedIn: Bool { store.isCheckedIn(at: venueId) }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                BPHaptics.light()
                Task {
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
            .disabled(store.isLoading)
            .bpAccessibility(label: checkedIn ? l10n.t("checkin.leave") : l10n.t("checkin.here"), isButton: true)

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
        .sheet(isPresented: $store.justCheckedOut) {
            AgeReportSheet(venueId: venueId, venueName: venueName) {
                store.justCheckedOut = false
            }
        }
    }
}
