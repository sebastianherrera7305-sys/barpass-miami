import SwiftUI
import MapKit

struct VenueDetailView: View {
    let venue: BarPassVenue
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var points = PointsEngine.shared
    @State private var checkinMessage: String?
    @State private var checkingIn = false
    @State private var showReviewComposer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            BPBackgroundView()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    contentSection
                        .padding(.bottom, 100)
                }
            }
            .coordinateSpace(name: "venueDetailScroll")
            .ignoresSafeArea(edges: .top)

            ctaBar
        }
            .onAppear { BPAnalytics.track(.viewVenue(venue.id)) }
            .navigationBarHidden(true)
        .overlay(alignment: .topLeading) { navBar }
        .sheet(isPresented: $showReviewComposer) {
            PostComposer(venue: venue) { post in
                Task {
                    try? await RepositoryDependencies.post.create(post)
                    await MainActor.run {
                        NotificationCenter.default.post(name: .bpPostsChanged, object: venue.id)
                        checkinMessage = l10n.t("venueDetail.reviewPublished")
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(.black)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Stretchy header: without this, pulling down past the top of
            // the ScrollView reveals BPBackgroundView's city art behind the
            // fixed-height hero — a visible, mismatched background flash
            // that doesn't relate to this venue's own photo/colors at all.
            GeometryReader { geo in
                let minY = geo.frame(in: .named("venueDetailScroll")).minY
                let stretch = max(0, minY)
                heroBackground
                    .frame(width: geo.size.width, height: 300 + stretch)
                    .clipped()
                    .offset(y: -stretch)
            }
            .frame(height: 300)
            // TestFlight feedback: "the app has a middle space inside of
            // the cards of the venues where it has a background and it
            // gets everything messed up" — if `minY`/`stretch` above is
            // even briefly out of sync with the real scroll offset (a
            // known GeometryReader-in-ScrollView timing gap right after a
            // push/sheet transition), the offset can walk the photo's
            // bottom edge past this 300pt slot before layout settles. The
            // inner .clipped() only bounds the image to its OWN (taller,
            // 300+stretch) frame, not to this outer one — this second
            // .clipped() is the hard stop that guarantees nothing ever
            // bleeds into contentSection below, regardless of that timing.
            .clipped()

            LinearGradient(
                colors: [.clear, .black],
                startPoint: .init(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .frame(height: 300)

            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(venue.vibes.prefix(4), id: \.self) { vibe in
            Text("#\(vibe)")
                .font(.bpCaption())
                .foregroundStyle(Color.white.opacity(0.65))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.bpInk.opacity(0.1), in: Capsule())
                        }
                    }
                }

                Text(venue.name)
                .font(.bpLargeTitle())
                .foregroundStyle(.white)

                HStack(spacing: 12) {
                    if let passport = MusicProfileStore.shared.passport {
                        if let tier = HypeEngine.musicMatchTier(passport: passport, venue: venue) {
                            HStack(spacing: 3) {
                                Text("🎵")
                                Text(tier.rawValue)
                            }
                            .font(.bpScaled(11, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.bpAmber, in: Capsule())
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.bpScaled(12)).foregroundStyle(Color.bpAmber)
                        Text(String(format: "%.1f", venue.rating))
                            .font(.bpScaled(13, weight: .bold)).foregroundStyle(.white)
                        Text("(\(venue.reviewCount))")
                            .font(.bpScaled(12)).foregroundStyle(Color.white.opacity(0.65))
                    }
                    Text("·").foregroundStyle(.white.opacity(0.35))
                    Text(venue.type.rawValue)
                        .font(.bpScaled(13)).foregroundStyle(Color.white.opacity(0.65))
                    Text("·").foregroundStyle(.white.opacity(0.35))
                    Text(venue.neighborhood)
                        .font(.bpScaled(13)).foregroundStyle(Color.white.opacity(0.65))
                }
            }
            .padding(.horizontal, BPSpacing.lg)
            .padding(.bottom, 20)
        }
        .frame(height: 300)
    }

    /// Real Google photo when available, emoji gradient as graceful fallback.
    @ViewBuilder private var heroBackground: some View {
        if let first = venue.photoUrls.first, let url = URL(string: first) {
            CachedImage(url: url, targetSize: CGSize(width: 420, height: 420), priority: .hot) { image in
                // Color.clear adopts the PROPOSED size; the overlaid fill image
                // is then clipped to it. A bare scaledToFill here reports the
                // bitmap's ideal width (~1260pt) and blows the whole screen
                // layout sideways.
                Color.clear
                    .overlay(image.resizable().scaledToFill())
                    .clipped()
            } placeholder: {
                ZStack {
                    heroEmojiFallback
                    BarPassLoadingView(size: 48)
                }
            }
        } else {
            heroEmojiFallback
        }
    }

    private var heroEmojiFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.15), Color.bpSurface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(venue.emoji).font(.bpScaled(120)).opacity(0.12)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            quickStats
                .padding(.horizontal, BPSpacing.lg)
                .padding(.top, 20)

            CheckInButton(venueId: venue.id, venueName: venue.name, venueLat: venue.latitude, venueLng: venue.longitude)
                .padding(.horizontal, BPSpacing.lg)

            if !goodToKnowChips.isEmpty {
                goodToKnowSection
                    .padding(.horizontal, BPSpacing.lg)
            }

            divider

            timingSection
                .padding(.horizontal, BPSpacing.lg)

            divider

            // AI Insight — prominent position
            aiInsightSection
                .padding(.horizontal, BPSpacing.lg)

            divider

            musicSection
                .padding(.horizontal, BPSpacing.lg)

            if !venue.popularDrinks.isEmpty {
                divider
                drinksSection
                    .padding(.horizontal, BPSpacing.lg)
            }

            if !venue.upcomingEvents.isEmpty {
                divider
                eventsSection
                    .padding(.horizontal, BPSpacing.lg)
            }

            if !venue.photoUrls.isEmpty {
                divider
                photosSection
            }

            divider

            reviewsSection
                .padding(.horizontal, BPSpacing.lg)

            divider

            VenuePostsSection(venue: venue)
                .padding(.horizontal, BPSpacing.lg)

            divider

            locationSection
                .padding(.horizontal, BPSpacing.lg)
        }
    }

    // MARK: - Quick stats

    private var quickStats: some View {
        HStack(spacing: 0) {
            quickStat(icon: "clock.fill", label: l10n.t("venueDetail.closes"), value: venue.closeTime, primary: true)
            Divider().background(Color.bpInk.opacity(0.08)).frame(height: 40)
            // Real price_tier ($–$$$$) replaces the old "Cover" stat, which
            // always read "Sin cover" — coverMen/coverWomen are NULL for
            // every venue in the catalog, so it was a false claim shown with
            // full confidence, never an honest "unknown."
            quickStat(icon: "dollarsign.circle.fill", label: l10n.t("venueDetail.priceTier"), value: venue.priceTier.symbol ?? l10n.t("venue.crowd.na"), primary: false)
            Divider().background(Color.bpInk.opacity(0.08)).frame(height: 40)
            // "Crowd" used to show crowdDescriptionKey, driven by
            // crowd_level — confirmed 100% "steady" for all 1,817 venues
            // (no real live-busyness source), so this was a fake indicator
            // shown with full confidence, same class of bug as the old
            // "Sin cover" claim above. Rating is a real per-venue signal we
            // do have, even though the hero header already shows it — this
            // stat row's job is "3 quick facts," and 2 honest facts beats
            // 3 where one is fabricated.
            quickStat(icon: "star.fill", label: l10n.t("venueDetail.rating"), value: String(format: "%.1f", venue.rating), primary: false)
        }
        .padding(.vertical, 14)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpInk.opacity(0.07)))
    }

    private func quickStat(icon: String, label: String, value: String, primary: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.bpScaled(primary ? 18 : 14))
                .foregroundStyle(Color.bpAmber)
            Text(value)
                .font(.system(size: primary ? 16 : 13, weight: primary ? .black : .bold))
                .foregroundStyle(primary ? Color.bpAmber : .white)
            Text(label)
                .font(.bpSmall())
                .foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Good to know (real amenity data only — no chip for a nil/false value)

    private var goodToKnowChips: [(icon: String, labelKey: String)] {
        let a = venue.amenities
        var chips: [(String, String)] = []
        if a.goodForGroups == true          { chips.append(("🎉", "venueDetail.chip.groups")) }
        if a.outdoorSeating == true         { chips.append(("🌳", "venueDetail.chip.outdoor")) }
        if a.hasLiveMusic == true           { chips.append(("🎤", "venueDetail.chip.liveMusic")) }
        if a.goodForWatchingSports == true  { chips.append(("🏈", "venueDetail.chip.sports")) }
        if a.wheelchairAccessible == true   { chips.append(("♿", "venueDetail.chip.accessible")) }
        if a.servesVegetarianFood == true   { chips.append(("🥗", "venueDetail.chip.vegetarian")) }
        return chips
    }

    private var goodToKnowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(l10n.t("venueDetail.goodToKnow"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(goodToKnowChips, id: \.labelKey) { chip in
                        HStack(spacing: 6) {
                            Text(chip.icon)
                            Text(l10n.t(chip.labelKey))
                                .font(.bpScaled(12, weight: .semibold))
                                .foregroundStyle(Color.bpInk.opacity(0.85))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.bpInk.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.bpInk.opacity(0.08)))
                    }
                }
            }
        }
    }

    // MARK: - Timing

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(l10n.t("venueDetail.whenToGo"))

            infoRow("calendar", l10n.t("venueDetail.hours"), "\(venue.openTime) – \(venue.closeTime)")
            infoRow("clock.arrow.2.circlepath", l10n.t("venueDetail.bestTime"), venue.bestArrivalTime)
            infoRow("waveform.path.ecg", l10n.t("venueDetail.peakHours"), venue.peakHours)
            infoRow("dollarsign.circle.fill", l10n.t("venueDetail.avgSpend"), venue.avgSpend + l10n.t("venueDetail.perPersonSuffix"))
            // The "Crowd" bar used to render here, driven by crowd_level —
            // confirmed 100% "steady" for all 1,817 venues (no real live-
            // busyness source exists), so the 5-segment bar always showed
            // the exact same fake reading for every venue. Removed rather
            // than shown with false confidence; see quickStats above for
            // the same fix applied to the summary row.
        }
    }

    // MARK: - Music

    // `music_genres` is never a real per-venue signal today — it's either
    // empty (90% of venues) or the identical ["house","hip_hop"] literal
    // stuck on one 2026-07-07 Miami seed batch regardless of venue type
    // (confirmed via direct Supabase audit). Showing it as a fact about the
    // venue would be fabricating data, so this section no longer renders
    // genre chips at all — only real per-venue dress code, when present.
    @ViewBuilder
    private var musicSection: some View {
        if !venue.dressCode.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(l10n.t("venueDetail.musicAmbience"))
                infoRow("tshirt.fill", l10n.t("venueDetail.dressCode"), venue.dressCode)
            }
        }
    }

    // MARK: - Drinks

    private var drinksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(l10n.t("venueDetail.popularDrinks"))
            VStack(spacing: 10) {
                ForEach(venue.popularDrinks) { drink in
                    HStack {
                        Text(drink.emoji).font(.bpScaled(22))
                        Text(drink.name)
                            .font(.bpScaled(14))
                            .foregroundStyle(Color.bpInk.opacity(0.7))
                        Spacer()
                        Text(String(format: "$%.0f", drink.price))
                            .font(.bpScaled(14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.bpAmber)
                    }
                    .bpAccessibility(label: "\(drink.name), \(String(format: "$%.0f", drink.price))", hint: l10n.t("venueDetail.drink.hint"))
                }
            }
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(l10n.t("venueDetail.upcomingEvents"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(venue.upcomingEvents.sorted { $0.date < $1.date }) { event in
                        EventFlyerCard(event: event, venue: venue, width: 190, height: 250)
                    }
                }
            }
        }
    }

    // MARK: - Photos (real Google photos via venue_media.json)

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(l10n.t("venueDetail.photos"))
                .padding(.horizontal, BPSpacing.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(venue.photoUrls, id: \.self) { urlString in
                        AsyncImage(url: URL(string: urlString)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .empty:
                                ZStack {
                                    Color.bpSurfaceRaised
                                    ProgressView().tint(Color.bpAmber)
                                }
                            case .failure:
                                ZStack {
                                    Color.bpSurfaceRaised
                                    Image(systemName: "photo")
                                        .foregroundStyle(Color.bpTextSecondary)
                                }
                            @unknown default:
                                Color.bpSurfaceRaised
                            }
                        }
                        .frame(width: 260, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: BPRadius.md))
                    }
                }
                .padding(.horizontal, BPSpacing.lg)
            }
        }
    }

    // MARK: - Reviews

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(l10n.t("profile.reviews"))

            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.bpScaled(20))
                    .foregroundStyle(Color.bpAmber)
                Text(String(format: "%.1f", venue.rating))
                    .font(.bpScaled(24, weight: .black))
                    .foregroundStyle(Color.bpInk)
                Text(String(format: l10n.t("venueDetail.reviewsCount"), venue.reviewCount))
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpTextSecondary)
                Spacer()
            }

            Text(l10n.t("venueDetail.googleRating"))
                .font(.bpScaled(11))
                .foregroundStyle(Color.bpTextSecondary.opacity(0.7))

            xpActions
        }
    }

    // MARK: - XP actions (check-in por proximidad + review)

    private var xpActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: attemptCheckIn) {
                    HStack(spacing: 6) {
                        if checkingIn { ProgressView().tint(.black).scaleEffect(0.7) }
                        else { Image(systemName: points.hasCheckedInToday(venueId: venue.id) ? "checkmark.seal.fill" : "mappin.and.ellipse").font(.bpScaled(13)) }
                        Text(points.hasCheckedInToday(venueId: venue.id) ? l10n.t("venueDetail.checkinDone") : l10n.t("venueDetail.checkin"))
                            .font(.bpScaled(13, weight: .bold))
                    }
                    .foregroundStyle(points.hasCheckedInToday(venueId: venue.id) ? Color.bpGreen : .black)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(points.hasCheckedInToday(venueId: venue.id) ? Color.bpGreen.opacity(0.12) : Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(checkingIn || points.hasCheckedInToday(venueId: venue.id))
                .bpAccessibility(label: l10n.t("venueDetail.checkin.label"), hint: l10n.t("venueDetail.checkin.hint"), isButton: true)

                Button {
                    BPHaptics.light()
                    showReviewComposer = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: points.hasReviewed(venueId: venue.id) ? "star.fill" : "square.and.pencil").font(.bpScaled(13))
                        Text(points.hasReviewed(venueId: venue.id) ? l10n.t("venueDetail.reviewDone") : l10n.t("venueDetail.leaveReview"))
                            .font(.bpScaled(13, weight: .bold))
                    }
                    .foregroundStyle(points.hasReviewed(venueId: venue.id) ? Color.bpGreen : Color.bpAmber)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.bpAmber.opacity(points.hasReviewed(venueId: venue.id) ? 0.06 : 0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(points.hasReviewed(venueId: venue.id))
                .bpAccessibility(label: l10n.t("venueDetail.leaveReview.label"), hint: l10n.t("venueDetail.leaveReview.hint"), isButton: true)
            }

            if let msg = checkinMessage {
                Text(msg)
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
                    .transition(.opacity)
            }
        }
        .padding(.top, 6)
    }

    private func attemptCheckIn() {
        checkingIn = true
        checkinMessage = nil
        Task {
            let service = LocationService()
            let coord = await service.requestOnce()
            await MainActor.run {
                checkingIn = false
                guard let coord else {
                    checkinMessage = l10n.t("venueDetail.enableLocation")
                    return
                }
                let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let there = CLLocation(latitude: venue.latitude, longitude: venue.longitude)
                let meters = here.distance(from: there)
                if meters <= 250 {
                    if points.checkIn(venueId: venue.id) != nil {
                        withAnimation { checkinMessage = String(format: l10n.t("venueDetail.checkinSuccess"), venue.name) }
                    }
                } else {
                    withAnimation { checkinMessage = String(format: l10n.t("venueDetail.tooFar"), Int(meters)) }
                }
            }
        }
    }

    // MARK: - AI Insight

    private var aiInsightSection: some View {
        ReviewSummaryView(venue: venue)
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(l10n.t("venueDetail.howToGet"))
            infoRow("location.fill", l10n.t("venueDetail.address"), venue.address)
            if !venue.parking.isEmpty {
                infoRow("car.fill", l10n.t("venueDetail.parking"), venue.parking)
            }

            HStack(spacing: 10) {
                linkButton(icon: "map.fill", label: l10n.t("venueDetail.mapsLink")) { openMaps() }
                linkButton(icon: "car.fill", label: "Uber") { openUber() }
                if let ig = venue.instagramHandle {
                    linkButton(icon: "camera.fill", label: "@\(ig)") { openInstagram(handle: ig) }
                }
                if let phone = venue.phone {
                    linkButton(icon: "phone.fill", label: l10n.t("venueDetail.call")) { callVenue(phone) }
                }
                if venue.website != nil {
                    linkButton(icon: "safari.fill", label: l10n.t("venueDetail.website")) { openWebsite() }
                }
            }
        }
    }

    // MARK: - CTA Bar

    private var ctaBar: some View {
        HStack(spacing: 10) {
            Button {
                BPHaptics.light()
                withAnimation(.spring(response: 0.3)) { favorites.toggle(venue.id) }
            } label: {
                Image(systemName: favorites.isFavorite(venue.id) ? "heart.fill" : "heart")
                    .font(.bpScaled(18))
                    .foregroundStyle(favorites.isFavorite(venue.id) ? Color.bpDanger : Color.bpInk)
                    .frame(width: 48, height: 48)
                    .background(Color.bpInk.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(Color.bpInk.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("venueDetail.save"), hint: l10n.t("venueDetail.save.hint"), isButton: true)
            .helpTarget("venueDetail.save")

            Button {
                appState.priorityVenueId = venue.id
                appState.priorityVenueName = venue.name
                appState.showPriorityEntry = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.bpScaled(12))
                    Text(l10n.t("priorityEntry.skipLine"))
                        .font(.bpScaled(14, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: BPRadius.md)
                )
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("priorityEntry.skipLine"), hint: l10n.t("venueDetail.skipLine.hint"), isButton: true)
            .helpTarget("venueDetail.skipLine")

            Button {
                BPAnalytics.track(.openMaps(venue: venue.name))
                let coords = "\(venue.latitude),\(venue.longitude)"
                guard let url = URL(string: "https://maps.apple.com/?ll=\(coords)&q=\(venue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { return }
                UIApplication.shared.open(url)
            } label: {
                Image(systemName: "mappin.circle.fill")
                    .font(.bpScaled(18))
                    .foregroundStyle(Color.bpAmber)
                    .frame(width: 48, height: 48)
                    .background(Color.bpAmber.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("venueDetail.directions"), hint: l10n.t("venueDetail.directions.hint"), isButton: true)
        }
        .padding(.horizontal, BPSpacing.lg)
        .padding(.vertical, 10)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            Button { BPHaptics.light(); dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("venueDetail.back"), hint: l10n.t("venueDetail.back.hint"), isButton: true)
            Spacer()
            Button {
                BPHaptics.light()
                ShareManager.present(ShareManager.shareVenue(venue))
                BPAnalytics.track(.shareVenue(venue: venue.id))
                PointsEngine.shared.award(.shareVenue)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("plan.share"), hint: l10n.t("venueDetail.share.hint"), isButton: true)

            HelpButton(route: .venueDetail)
        }
        .padding(.horizontal, BPSpacing.lg)
        .padding(.top, 56)
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.bpInk.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, BPSpacing.lg)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.bpScaled(16, weight: .bold))
            .foregroundStyle(Color.bpInk)
    }

    private func infoRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 18)
            Text(label)
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpTextSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpInk.opacity(0.7))
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }

    private func linkButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.bpScaled(11))
                Text(label).font(.bpScaled(12, weight: .semibold))
            }
            .foregroundStyle(Color.bpInk.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.sm))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.sm).strokeBorder(Color.bpInk.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: String(format: l10n.t("venueDetail.openIn"), label), isButton: true)
    }

    // MARK: - Actions

    private func openMaps() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: venue.latitude, longitude: venue.longitude))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = venue.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openUber() {
        let encoded = venue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let uberURL = URL(string: "uber://?action=setPickup&dropoff[latitude]=\(venue.latitude)&dropoff[longitude]=\(venue.longitude)&dropoff[nickname]=\(encoded)")
        if let url = uberURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://m.uber.com/ul/?action=setPickup&dropoff[latitude]=\(venue.latitude)&dropoff[longitude]=\(venue.longitude)") {
            UIApplication.shared.open(url)
        }
    }

    private func callVenue(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(digits)") { UIApplication.shared.open(url) }
    }

    private func openWebsite() {
        guard let website = venue.website, let url = URL(string: website) else { return }
        UIApplication.shared.open(url)
    }

    private func openInstagram(handle: String) {
        let cleanHandle = handle.replacingOccurrences(of: "@", with: "")
        if let url = URL(string: "instagram://user?username=\(cleanHandle)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://instagram.com/\(cleanHandle)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Previews
//
// The states below can't be reached by tapping through a running app: they
// depend on system settings (colour scheme, type size) or on venue data we
// don't control at runtime (no amenities vs. every amenity, very long name).
// Each is a separate canvas entry so a regression in any one is visible.
//
// All of them inject AppState — `ctaBar` reads it, so a preview without it
// traps at render time.

// @MainActor because AppState is main-actor isolated: the `#Preview` macro
// body is already isolated, but this free function is not, so constructing
// AppState here is an error under Swift 6 strict concurrency.
@MainActor
private func previewDetail(_ venue: BarPassVenue) -> some View {
    NavigationStack { VenueDetailView(venue: venue) }
        .environmentObject(AppState())
}

#Preview("Dark · sin chips") {
    previewDetail(.preview)
        .preferredColorScheme(.dark)
}

#Preview("Light · sin chips") {
    previewDetail(.preview)
        .preferredColorScheme(.light)
}

// These three consume fixtures that live behind `#if DEBUG` in Venue.swift,
// so they need the same guard — `#Preview` bodies are compiled in Release
// too, and without this the Release build fails to resolve the symbols.
#if DEBUG
#Preview("Todos los chips · $$$$") {
    previewDetail(.previewAllAmenities)
        .preferredColorScheme(.dark)
}

#Preview("Nombre largo") {
    previewDetail(.previewLongName)
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type XXXL") {
    previewDetail(.previewAllAmenities)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
