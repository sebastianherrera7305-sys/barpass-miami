import SwiftUI
import CoreLocation
import WidgetKit

@MainActor
final class GoHomeStore: ObservableObject {
    static let shared = GoHomeStore()

    @Published private(set) var homeAddress: HomeAddress?
    @Published var errorMessage: String?

    private let repository: any HomeAddressRepository
    private let locationService = LocationService()

    init(repository: any HomeAddressRepository = RepositoryDependencies.homeAddress) {
        self.repository = repository
    }

    private static let sharedSuite = UserDefaults(suiteName: "group.com.sebastian.barpass")

    func load() async {
        homeAddress = try? await repository.getHomeAddress()
        writeToWidget()
    }

    /// The BarPassWidget process can't reach Supabase/Keychain itself — this
    /// is the only bridge. Also nudges WidgetKit to redraw immediately
    /// instead of waiting for its own refresh schedule.
    private func writeToWidget() {
        guard let home = homeAddress, let suite = Self.sharedSuite else { return }
        suite.set(home.lat, forKey: "home_lat")
        suite.set(home.lng, forKey: "home_lng")
        suite.set(home.address, forKey: "home_address")
        WidgetCenter.shared.reloadTimelines(ofKind: "GoHomeWidget")
    }

    /// Geocodes on-device (CLGeocoder) — never sends the typed address to
    /// any BarPass backend for resolution, only the resulting coordinates.
    func save(addressText: String) async throws {
        let placemarks = try await CLGeocoder().geocodeAddressString(addressText)
        guard let coordinate = placemarks.first?.location?.coordinate else {
            throw HomeAddressError.notFound
        }
        let address = HomeAddress(address: addressText, lat: coordinate.latitude, lng: coordinate.longitude)
        try await repository.setHomeAddress(address)
        homeAddress = address
        writeToWidget()
    }

    /// Opens Uber with pickup = current device location, dropoff = the
    /// saved home address. Falls back to just centering on home in Apple
    /// Maps if location permission isn't available — never silently no-ops.
    func openRideHome() async {
        guard let home = homeAddress else { return }
        let pickup = await locationService.requestOnce()

        // Built as one literal string, not via URLComponents.queryItems —
        // assigning `.queryItems = [...]` REPLACES whatever the initial
        // "uber://?action=setPickup" string parsed as its query, silently
        // dropping "action=setPickup" itself. Matches the proven-working
        // pattern already used in VenueDetailView.openUber().
        var query = "action=setPickup"
        if let pickup {
            query += "&pickup[latitude]=\(pickup.latitude)&pickup[longitude]=\(pickup.longitude)"
        } else {
            query += "&pickup=my_location"
        }
        let nickname = L10n.shared.t("goHome.uberNickname").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Home"
        query += "&dropoff[latitude]=\(home.lat)&dropoff[longitude]=\(home.lng)&dropoff[nickname]=\(nickname)"

        guard let uberURL = URL(string: "uber://?\(query)") else { return }
        if await UIApplication.shared.canOpenURL(uberURL) {
            await UIApplication.shared.open(uberURL)
        } else if let mapsURL = URL(string: "https://maps.apple.com/?daddr=\(home.lat),\(home.lng)") {
            await UIApplication.shared.open(mapsURL)
        }
    }
}

enum HomeAddressError: Error {
    case notFound
}

/// Small corner button, mirrors the cart button's footprint — only rendered
/// by RootView while the user has an active check-in (per explicit product
/// decision: this isn't useful sitting on the home screen at 2pm, only
/// matters once you're actually out somewhere).
struct GoHomeButton: View {
    @ObservedObject private var store = GoHomeStore.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var isRequesting = false

    var body: some View {
        Group {
            if store.homeAddress != nil {
                Button {
                    BPHaptics.light()
                    isRequesting = true
                    Task {
                        await store.openRideHome()
                        isRequesting = false
                    }
                } label: {
                    ZStack {
                        if isRequesting {
                            ProgressView().tint(Color.bpInk)
                        } else {
                            Image(systemName: "house.fill")
                                .font(.bpScaled(14, weight: .semibold))
                                .foregroundStyle(Color.bpInk)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(Color.bpCardBackground.opacity(0.97), in: Circle())
                    .overlay(Circle().strokeBorder(Color.bpInk.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
                .bpAccessibility(label: l10n.t("goHome.button"), hint: l10n.t("goHome.button.hint"), isButton: true)
            }
        }
        .task { await store.load() }
    }
}
