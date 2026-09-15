import SwiftUI

/// Pick the venue a night is anchored to, from the catalogue the app already
/// loaded. Deliberately offers no "can't find it? type it in" escape hatch:
/// uncurated supply is exactly what this product is not.
struct HostEventVenuePicker: View {
    @Binding var selection: BarPassVenue?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var venueStore: VenueStore
    @ObservedObject private var l10n = L10n.shared
    @State private var query = ""

    private var results: [BarPassVenue] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return venueStore.venues }
        return venueStore.venues.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.neighborhood.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                if venueStore.isLoading {
                    ProgressView().tint(Color.bpAmber)
                } else if venueStore.venues.isEmpty {
                    // The city picker, not this screen, is where an empty
                    // catalogue gets fixed — say so instead of showing nothing.
                    VStack(spacing: 8) {
                        Text("🗺️").font(.bpScaled(36))
                        Text(l10n.t("host.venuePicker.empty"))
                            .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(BPSpacing.xl)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { venue in
                                Button {
                                    BPHaptics.selection()
                                    selection = venue
                                    dismiss()
                                } label: {
                                    row(venue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, BPSpacing.lg)
                        .padding(.bottom, 30)
                    }
                }
            }
            .searchable(text: $query, prompt: l10n.t("host.venuePicker.search"))
            .navigationTitle(l10n.t("host.venuePicker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(l10n.t("host.common.cancel")) { dismiss() }
                        .foregroundStyle(Color.bpTextSecondary)
                }
            }
        }
    }

    private func row(_ venue: BarPassVenue) -> some View {
        HStack(spacing: 12) {
            Text(venue.emoji).font(.bpScaled(22))
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk).lineLimit(1)
                Text(venue.neighborhood)
                    .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary).lineLimit(1)
            }
            Spacer()
            if selection?.id == venue.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.bpAmber)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: venue.name, hint: l10n.t("host.venuePicker.row.hint"), isButton: true)
    }
}
