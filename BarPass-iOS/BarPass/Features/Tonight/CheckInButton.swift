import SwiftUI

@MainActor
final class CheckInStore: ObservableObject {
    @Published private(set) var activeCheckin: ActiveCheckin?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repository: any VenueCheckinRepository

    init(repository: any VenueCheckinRepository = RepositoryDependencies.venueCheckin) {
        self.repository = repository
    }

    func load() async {
        activeCheckin = try? await repository.getActiveCheckin()
    }

    func isCheckedIn(at venueId: String) -> Bool {
        activeCheckin?.venueId == venueId
    }

    func checkIn(venueId: String, tripId: String?) async {
        isLoading = true
        errorMessage = nil
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

    func checkOut() async {
        guard let checkinId = activeCheckin?.checkinId else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await repository.checkOut(checkinId: checkinId)
            activeCheckin = nil
            BPHaptics.medium()
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
    var tripId: String? = nil

    @StateObject private var store = CheckInStore()
    @ObservedObject private var l10n = L10n.shared

    private var checkedIn: Bool { store.isCheckedIn(at: venueId) }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                BPHaptics.light()
                Task {
                    if checkedIn { await store.checkOut() }
                    else { await store.checkIn(venueId: venueId, tripId: tripId) }
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
            }
        }
        .task { await store.load() }
    }
}
