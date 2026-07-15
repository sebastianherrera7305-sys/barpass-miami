import SwiftUI

struct TripCreateFlow: View {
    @ObservedObject private var l10n = L10n.shared
    let venues: [BarPassVenue]
    let tripStore: TripStore
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var destinationCity = "Miami"
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var visibility: TripVisibility = .privateTrip
    @State private var selectedVenueIds: Set<String> = []
    @State private var step = 0

    private let amber  = Color.bpAmber

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                switch step {
                case 0: titleStep
                case 1: datesStep
                case 2: venuesStep
                case 3: reviewStep
                default: EmptyView()
                }
            }
            .navigationTitle(l10n.t("tripCreate.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > 0 {
                        Button(l10n.t("tripCreate.back")) {
                            withAnimation { step -= 1 }
                        }
                        .foregroundStyle(amber)
                        .bpAccessibility(label: l10n.t("tripCreate.back"), hint: l10n.t("tripCreate.back.hint"), isButton: true)
                    } else {
                        Button(l10n.t("tripCreate.cancel")) { onDismiss() }
                            .foregroundStyle(Color.bpTextSecondary)
                            .bpAccessibility(label: l10n.t("tripCreate.cancel"), hint: l10n.t("tripCreate.cancel.hint"), isButton: true)
                    }
                }
            }
        }
    }

    private var titleStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(l10n.t("tripCreate.step1.title"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            TextField(l10n.t("tripCreate.step1.placeholder"), text: $title)
                .font(.bpBody())
                .foregroundStyle(Color.bpInk)
                .padding(14)
                .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
                .padding(.horizontal, BPSpacing.lg)
                .bpAccessibility(label: l10n.t("tripCreate.step1.label"), hint: l10n.t("tripCreate.step1.hint"))

            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.t("tripCreate.city"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)

                TextField(l10n.t("tripCreate.city.placeholder"), text: $destinationCity)
                    .font(.bpBody())
                    .foregroundStyle(Color.bpInk)
                    .padding(14)
                    .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
                    .bpAccessibility(label: l10n.t("tripCreate.city"), hint: l10n.t("tripCreate.city.hint"))
            }
            .padding(.horizontal, BPSpacing.lg)

            nextButton
            Spacer()
        }
    }

    private var datesStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(l10n.t("tripCreate.step2.title"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("tripCreate.from"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(amber)
                    .bpAccessibility(label: l10n.t("tripCreate.startDate"), hint: l10n.t("tripCreate.startDate.hint"))
            }
            .padding(.horizontal, BPSpacing.lg)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("tripCreate.to"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(amber)
                    .bpAccessibility(label: l10n.t("tripCreate.endDate"), hint: l10n.t("tripCreate.endDate.hint"))
            }
            .padding(.horizontal, BPSpacing.lg)

            nextButton
            Spacer()
        }
    }

    private var venuesStep: some View {
        VStack(spacing: 14) {
            Text(l10n.t("tripCreate.step3.title"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
                .padding(.top, 20)

            Text(l10n.t("tripCreate.step3.subtitle"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(venues) { v in
                        let selected = selectedVenueIds.contains(v.id)
                        Button {
                            BPHaptics.light()
                            if selected { selectedVenueIds.remove(v.id) }
                            else { selectedVenueIds.insert(v.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(selected ? amber : Color.bpInk.opacity(0.06))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Image(systemName: selected ? "checkmark" : "")
                                            .font(.bpScaled(12, weight: .bold))
                                            .foregroundStyle(.black)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name)
                                        .font(.bpHeadline())
                                        .foregroundStyle(Color.bpInk)
                                    Text("\(v.neighborhood) · \(v.type.rawValue)")
                                        .font(.bpSmall())
                                        .foregroundStyle(Color.bpTextSecondary)
                                }
                                Spacer()
                                Text(v.emoji)
                                    .font(.title3)
                            }
                            .padding(12)
                            .background(selected ? amber.opacity(0.08) : Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                            .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(selected ? amber.opacity(0.3) : Color.bpBorder))
                        }
                        .buttonStyle(.plain)
                        .bpAccessibility(label: v.name, hint: l10n.t("tripCreate.venue.select.hint"), isButton: true)
                        .padding(.horizontal, BPSpacing.lg)
                    }
                }
            }

            nextButton
        }
    }

    private var reviewStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Text(l10n.t("tripCreate.summary.title"))
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)

            VStack(spacing: 10) {
                summaryRow(l10n.t("tripCreate.summary.titleLabel"), title)
                summaryRow(l10n.t("tripCreate.city"), destinationCity)
                summaryRow(l10n.t("tripCreate.from"), startDate.formatted(date: .abbreviated, time: .omitted))
                summaryRow(l10n.t("tripCreate.to"), endDate.formatted(date: .abbreviated, time: .omitted))
                summaryRow(l10n.t("tripCreate.summary.visibility"), visibility.label)
                summaryRow(l10n.t("tripCreate.summary.venues"), String(format: l10n.t("tripCreate.summary.venuesSelected"), selectedVenueIds.count))
            }
            .padding(16)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))

            Button {
                createTrip()
            } label: {
                Text(l10n.t("tripCreate.createButton"))
                    .font(.bpHeadline())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(amber, in: Capsule())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("tripCreate.createButton"), hint: l10n.t("tripCreate.createButton.hint"), isButton: true)
            .padding(.horizontal, BPSpacing.lg)

            Spacer()
        }
        .padding(BPSpacing.lg)
    }

    private var nextButton: some View {
        Button {
            withAnimation { step += 1 }
        } label: {
            Text(l10n.t("tripCreate.next"))
                .font(.bpHeadline())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(amber, in: Capsule())
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("tripCreate.next"), hint: l10n.t("tripCreate.next.hint"), isButton: true)
        .disabled(step == 0 && title.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(step == 0 && title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        .padding(.horizontal, BPSpacing.lg)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
            Spacer()
            Text(value)
                .font(.bpBody())
                .foregroundStyle(Color.bpInk)
        }
    }

    private func createTrip() {
        let selectedVenues = venues.filter { selectedVenueIds.contains($0.id) }
        let stops = selectedVenues.enumerated().map { i, v in
            Stop(
                tripId: "",
                refId: v.id,
                venueName: v.name,
                emoji: v.emoji,
                date: startDate,
                startTime: "\(7 + i * 2):00 PM",
                endTime: "\(9 + i * 2):00 PM"
            )
        }
        let trip = Trip(
            creatorId: TripStore.currentUserId,
            title: title,
            destinationCity: destinationCity,
            startDate: startDate,
            endDate: endDate,
            visibility: visibility,
            stops: stops
        )
        Task { await tripStore.create(trip) }
        onDismiss()
    }
}
