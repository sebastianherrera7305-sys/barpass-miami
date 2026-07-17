import SwiftUI
import PhotosUI

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
    @State private var coverPickerItem: PhotosPickerItem?
    /// Already downsampled (~1200px) — never the raw picked photo. A 12MP+
    /// camera photo decoded at full resolution for a 140pt preview box was
    /// exactly the kind of memory spike that got the app killed by jetsam.
    @State private var coverImage: UIImage?

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
        ScrollView {
            VStack(spacing: 20) {
                Text(l10n.t("tripCreate.step1.title"))
                    .font(.bpTitle2())
                    .foregroundStyle(Color.bpInk)
                    .padding(.top, 20)

                coverImagePicker

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

                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("tripCreate.summary.visibility"))
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpTextSecondary)

                    Picker(l10n.t("tripCreate.summary.visibility"), selection: $visibility) {
                        ForEach(TripVisibility.allCases, id: \.self) { v in
                            Text(v.label).tag(v)
                        }
                    }
                    .pickerStyle(.segmented)
                    .bpAccessibility(label: l10n.t("tripCreate.summary.visibility"), hint: l10n.t("tripCreate.visibility.hint"))
                }
                .padding(.horizontal, BPSpacing.lg)

                nextButton
            }
            .padding(.bottom, 20)
        }
    }

    private var coverImagePicker: some View {
        PhotosPicker(selection: $coverPickerItem, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: BPRadius.lg)
                    .fill(Color.bpInk.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))

                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: BPRadius.lg))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(amber)
                        Text(l10n.t("tripCreate.coverImage.pick"))
                            .font(.bpCaption())
                            .foregroundStyle(Color.bpTextSecondary)
                    }
                }
            }
            .frame(height: 140)
            .clipped()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, BPSpacing.lg)
        .bpAccessibility(label: l10n.t("tripCreate.coverImage.pick"), hint: l10n.t("tripCreate.coverImage.hint"), isButton: true)
        .onChange(of: coverPickerItem) { _, newItem in
            Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                let resized = await Task.detached(priority: .utility) {
                    ImageCache.downsampled(from: data, maxPixel: 1200)
                }.value
                coverImage = resized
            }
        }
    }

    private var datesStep: some View {
        // Two full graphical DatePickers (~340pt each) plus title/button
        // overflow the screen on every real device — without a ScrollView
        // (unlike titleStep, which has one) the "Next" button was pushed
        // below the visible viewport with no way to reach it, reading as
        // the whole flow being "stuck" on this step.
        ScrollView {
            VStack(spacing: 20) {
                Text(l10n.t("tripCreate.step2.title"))
                    .font(.bpTitle2())
                    .foregroundStyle(Color.bpInk)
                    .padding(.top, 20)

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
            }
            .padding(.bottom, 20)
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
        let stops = Stop.sequence(for: selectedVenues, tripId: "", date: startDate)
        var trip = Trip(
            creatorId: TripStore.currentUserId,
            title: title,
            destinationCity: destinationCity,
            startDate: startDate,
            endDate: endDate,
            visibility: visibility,
            stops: stops
        )
        trip.coverImage = saveCoverImageIfNeeded(tripId: trip.id)
        Task { await tripStore.create(trip) }
        onDismiss()
    }

    /// Saves the already-downsampled (~1200px) cover photo to disk and
    /// returns its file path — writes the resized image re-encoded as
    /// JPEG, never the original multi-MB picked photo, so both the file on
    /// disk and every future re-read of it stay small. No upload backend
    /// exists for trip covers, so this stays local (same device only)
    /// until one does; never fabricates a remote URL.
    private func saveCoverImageIfNeeded(tripId: String) -> String? {
        guard let coverImage, let jpeg = coverImage.jpegData(compressionQuality: 0.8) else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BarPassTripCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(tripId).jpg")
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }
}
