import SwiftUI

/// Events organized by the chapter's own members — a mixer, a date party, a
/// study night — separate from BarPass's venue-anchored ticketed events.
/// Access, rate limiting, and bans are all enforced server-side by the
/// chapter_events RPCs; this view never decides who can post or RSVP, it
/// just shows what the RPC allows, same trust model as ChapterChatView.
struct ChapterEventsView: View {
    let chapter: GreekChapter

    @ObservedObject private var l10n = L10n.shared
    @State private var events: [ChapterEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var myUserId: String?

    private var upcoming: [ChapterEvent] { events.filter { $0.startsAt >= Date() } }
    private var past: [ChapterEvent] { events.filter { $0.startsAt < Date() } }

    var body: some View {
        ZStack {
            BPBackgroundView()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if events.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BPSpacing.lg) {
                        if !upcoming.isEmpty {
                            section(title: l10n.t("greek.events.upcoming"), events: upcoming)
                        }
                        if !past.isEmpty {
                            section(title: l10n.t("greek.events.past"), events: past)
                        }
                    }
                    .padding(BPSpacing.lg)
                }
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.bpCaption())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.bpDanger.opacity(0.9), in: Capsule())
                        .padding(.bottom, 20)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle(l10n.t("greek.events.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.bpAmber)
                }
                .bpAccessibility(label: l10n.t("greek.events.create"), hint: l10n.t("greek.events.create.hint"), isButton: true)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateChapterEventView { await load() }
        }
        .task {
            myUserId = AuthService.shared.restoreSession()?.user.id
            await load()
        }
    }

    private func section(title: String, events: [ChapterEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
                .textCase(.uppercase)
            ForEach(events) { event in
                eventCard(event)
            }
        }
    }

    private func eventCard(_ event: ChapterEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.bpHeadline())
                        .foregroundStyle(Color.bpInk)
                    Text(formattedDate(event.startsAt))
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpAmber)
                }
                Spacer()
                if event.createdBy == myUserId {
                    Menu {
                        Button(role: .destructive) { delete(event) } label: {
                            Label(l10n.t("greek.events.delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.bpTextSecondary)
                    }
                }
            }

            if let location = event.locationName {
                Label(location, systemImage: "mappin.circle.fill")
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpTextSecondary)
            }

            if let description = event.description {
                Text(description)
                    .font(.bpBody())
                    .foregroundStyle(Color.bpInk.opacity(0.85))
            }

            HStack {
                rsvpButton(event)
                Spacer()
                Text(String(format: event.rsvpCount == 1 ? l10n.t("greek.events.going.singular") : l10n.t("greek.events.going.plural"), event.rsvpCount))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
    }

    private func rsvpButton(_ event: ChapterEvent) -> some View {
        Button {
            toggleRSVP(event)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: event.going ? "checkmark.circle.fill" : "circle")
                Text(l10n.t(event.going ? "greek.events.going.yes" : "greek.events.going.rsvp"))
            }
            .font(.bpScaled(12, weight: .semibold))
            .foregroundStyle(event.going ? Color.bpGreen : Color.bpAmber)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background((event.going ? Color.bpGreen : Color.bpAmber).opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t(event.going ? "greek.events.going.yes" : "greek.events.going.rsvp"), hint: l10n.t("greek.events.rsvp.hint"), isButton: true)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.bpScaled(34))
                .foregroundStyle(Color.bpTextTertiary)
            Text(l10n.t("greek.events.empty"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showCreate = true } label: {
                Text(l10n.t("greek.events.create"))
                    .font(.bpScaled(14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: l10n.language.rawValue)
        f.dateFormat = "EEE d MMM · h:mm a"
        return f.string(from: date)
    }

    private func load() async {
        errorMessage = nil
        do {
            events = try await RepositoryDependencies.chapterEvents.events()
        } catch {
            errorMessage = l10n.t("greek.events.loadError")
        }
        isLoading = false
    }

    private func toggleRSVP(_ event: ChapterEvent) {
        Task {
            do {
                let (going, count) = try await RepositoryDependencies.chapterEvents.toggleRSVP(eventId: event.id)
                guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
                events[idx] = ChapterEvent(
                    id: event.id, title: event.title, description: event.description,
                    locationName: event.locationName, startsAt: event.startsAt, endsAt: event.endsAt,
                    createdBy: event.createdBy, createdAt: event.createdAt, rsvpCount: count, going: going
                )
            } catch {
                errorMessage = l10n.t("greek.events.rsvpError")
            }
        }
    }

    private func delete(_ event: ChapterEvent) {
        events.removeAll { $0.id == event.id }
        Task { try? await RepositoryDependencies.chapterEvents.delete(eventId: event.id) }
    }
}

/// Minimal creation form — title, optional description/location, start
/// (and optional end) time. No cover charge, no ticket tiers, no payment:
/// this is a member calling their own chapter together, not a commercial
/// ticketed event (that's PriorityEntry/EventTicketsView's job).
private struct CreateChapterEventView: View {
    let onCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var title = ""
    @State private var description = ""
    @State private var locationName = ""
    @State private var startsAt = Date().addingTimeInterval(3600 * 24)
    @State private var hasEndTime = false
    @State private var endsAt = Date().addingTimeInterval(3600 * 27)
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(l10n.t("greek.events.form.details")) {
                    TextField(l10n.t("greek.events.form.title"), text: $title)
                    TextField(l10n.t("greek.events.form.location"), text: $locationName)
                    TextField(l10n.t("greek.events.form.description"), text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section(l10n.t("greek.events.form.when")) {
                    DatePicker(l10n.t("greek.events.form.starts"), selection: $startsAt)
                    Toggle(l10n.t("greek.events.form.hasEndTime"), isOn: $hasEndTime.animation())
                    if hasEndTime {
                        DatePicker(l10n.t("greek.events.form.ends"), selection: $endsAt)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.bpCaption()).foregroundStyle(Color.bpDanger)
                }
            }
            .navigationTitle(l10n.t("greek.events.create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("greek.chat.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(l10n.t("greek.events.form.save")) { save() }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await RepositoryDependencies.chapterEvents.create(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description,
                    locationName: locationName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : locationName,
                    startsAt: startsAt,
                    endsAt: hasEndTime ? endsAt : nil
                )
                await onCreated()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
