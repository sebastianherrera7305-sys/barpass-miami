import SwiftUI
import PhotosUI

/// Basic trip editing — title/city/dates/visibility/cover, pre-filled from
/// the current trip. One screen, not a wizard (unlike TripCreateFlow), since
/// there's no "collect info step by step" need when the info already
/// exists. Doesn't touch the itinerary — that's a separate, larger feature.
struct EditTripView: View {
    let trip: Trip
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var title: String
    @State private var destinationCity: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var visibility: TripVisibility
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var coverImage: UIImage?
    @State private var existingCoverPath: String?

    private let amber = Color.bpAmber

    init(trip: Trip) {
        self.trip = trip
        _title = State(initialValue: trip.title)
        _destinationCity = State(initialValue: trip.destinationCity)
        _startDate = State(initialValue: trip.startDate)
        _endDate = State(initialValue: trip.endDate)
        _visibility = State(initialValue: trip.visibility)
        _existingCoverPath = State(initialValue: trip.coverImage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                ScrollView {
                    VStack(spacing: 20) {
                        coverImagePicker
                            .padding(.top, 12)

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

                        VStack(alignment: .leading, spacing: 6) {
                            Text(l10n.t("tripCreate.from"))
                                .font(.bpCaption())
                                .foregroundStyle(Color.bpTextSecondary)
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(amber)
                                .labelsHidden()
                                .bpAccessibility(label: l10n.t("tripCreate.startDate"), hint: l10n.t("tripCreate.startDate.hint"))
                        }
                        .padding(.horizontal, BPSpacing.lg)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(l10n.t("tripCreate.to"))
                                .font(.bpCaption())
                                .foregroundStyle(Color.bpTextSecondary)
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(amber)
                                .labelsHidden()
                                .bpAccessibility(label: l10n.t("tripCreate.endDate"), hint: l10n.t("tripCreate.endDate.hint"))
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

                        Button {
                            save()
                        } label: {
                            Text(l10n.t("editTrip.save"))
                                .font(.bpHeadline())
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(amber.opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.horizontal, BPSpacing.lg)
                        .padding(.top, 8)
                        .bpAccessibility(label: l10n.t("editTrip.save"), hint: l10n.t("editTrip.save.hint"), isButton: true)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(l10n.t("editTrip.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("tripCreate.cancel")) { dismiss() }
                        .foregroundStyle(Color.bpTextSecondary)
                        .bpAccessibility(label: l10n.t("tripCreate.cancel"), hint: l10n.t("tripCreate.cancel.hint"), isButton: true)
                }
            }
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
                } else if let path = existingCoverPath, let uiImage = ImageCache.downsampled(contentsOf: URL(fileURLWithPath: path), maxPixel: 900) {
                    Image(uiImage: uiImage)
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

    private func save() {
        let newCoverPath = saveCoverImageIfNeeded() ?? existingCoverPath
        store.updateBasicInfo(
            trip.id,
            title: title,
            destinationCity: destinationCity,
            startDate: startDate,
            endDate: endDate,
            visibility: visibility,
            coverImage: newCoverPath
        )
        dismiss()
    }

    private func saveCoverImageIfNeeded() -> String? {
        guard let coverImage, let jpeg = coverImage.jpegData(compressionQuality: 0.8) else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BarPassTripCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(trip.id).jpg")
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }
}
