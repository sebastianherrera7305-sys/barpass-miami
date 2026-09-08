import SwiftUI
import PhotosUI

/// Shown the instant a check-in succeeds — the one moment we KNOW the user
/// is standing in the venue with a phone in hand. Asks for a photo or video
/// right there, instead of hoping they scroll to the bottom of the venue
/// page later (they didn't: two photos in two days, both uploaded the next
/// afternoon). One tap to pick, one tap to skip; never blocks anything.
struct CheckInMomentSheet: View {
    let venueId: String
    let venueName: String
    let onDone: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @StateObject private var uploader = VenueMediaUploader()
    @State private var pickerItem: PhotosPickerItem?
    @State private var uploaded = false

    var body: some View {
        let isBusy = uploader.isBusy
        let addTitle = l10n.t("checkin.moment.add")
        VStack(spacing: 18) {
            Capsule().fill(Color.bpInk.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 8)

            Image("BarPassMascot")
                .resizable().scaledToFit()
                .frame(width: 72, height: 72)

            VStack(spacing: 6) {
                Text(String(format: l10n.t("checkin.moment.title"), venueName))
                    .font(.bpTitle2()).foregroundStyle(Color.bpInk)
                    .multilineTextAlignment(.center)
                Text(uploaded ? l10n.t("checkin.moment.done") : l10n.t("checkin.moment.subtitle"))
                    .font(.bpBody()).foregroundStyle(uploaded ? Color.bpGreen : Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            if let label = uploader.stageLabel(l10n) {
                VStack(spacing: 6) {
                    Text(label).font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                    ProgressView(value: uploader.stage == .uploading ? uploader.fraction : nil)
                        .tint(Color.bpAmber)
                }
                .padding(.horizontal, 32)
            }

            if let error = uploader.error {
                Text(error)
                    .font(.bpCaption()).foregroundStyle(Color.bpDanger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if uploaded {
                Button {
                    BPHaptics.light()
                    onDone()
                } label: {
                    Text(l10n.t("common.done"))
                        .font(.bpScaled(15, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView().tint(.black).controlSize(.small)
                        } else {
                            Image(systemName: "camera.fill").font(.bpScaled(15, weight: .bold))
                        }
                        Text(addTitle).font(.bpScaled(15, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
                }
                .disabled(isBusy)
                .padding(.horizontal, 24)
                .bpAccessibility(label: addTitle, hint: l10n.t("venueMedia.add.hint"), isButton: true)

                Button {
                    BPHaptics.light()
                    onDone()
                } label: {
                    Text(l10n.t("checkin.moment.later"))
                        .font(.bpScaled(14, weight: .semibold)).foregroundStyle(Color.bpTextSecondary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
        .background(Color.bpSurface.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isBusy)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if await uploader.upload(newItem, venueId: venueId) != nil {
                    withAnimation { uploaded = true }
                }
                pickerItem = nil
            }
        }
    }
}
