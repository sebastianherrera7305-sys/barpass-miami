import SwiftUI

/// The Interactive Venue Map's first shippable slice: browse a stadium by
/// level, see real sourced POIs. No routing/3D yet — see
/// BRIEF-hard-rock-stadium.md's phased research for why that's not
/// buildable with public data alone today. Every POI traces back to a real
/// official source; nothing here is invented.
struct StadiumDetailView: View {
    let stadium: Stadium

    @State private var pois: [StadiumPOI] = []
    @State private var events: [StadiumEvent] = []
    @State private var isLoading = true
    @State private var selectedLevel: String?
    @State private var mySection: Int?
    @State private var sectionInput = ""
    @State private var selectedMapPOI: StadiumPOI?
    @FocusState private var sectionFieldFocused: Bool
    @ObservedObject private var l10n = L10n.shared

    private var levels: [(name: String, order: Int)] {
        let unique = Dictionary(grouping: pois, by: \.levelName)
            .compactMapValues { $0.first?.levelOrder }
        return unique.map { (name: $0.key, order: $0.value) }.sorted { $0.order > $1.order }
        // Descending order: Suite/300 at the top of the rail, Field at the
        // bottom — mirrors how the levels physically stack in the building.
    }

    private var poisForSelectedLevel: [StadiumPOI] {
        guard let selectedLevel else { return [] }
        return pois.filter { $0.levelName == selectedLevel }
    }

    private var groupedByType: [(type: StadiumPOIType, pois: [StadiumPOI])] {
        let grouped = Dictionary(grouping: poisForSelectedLevel, by: \.type)
        return StadiumPOIType.allCases.compactMap { type in
            guard let list = grouped[type], !list.isEmpty else { return nil }
            return (type, sortedByProximity(list))
        }
    }

    /// Real POI data only carries a free-text section/concourse string (no
    /// coordinates), so "closest" is approximated by how far a POI's
    /// section number is from the user's — never a fabricated meter
    /// distance we don't actually have.
    private func sortedByProximity(_ list: [StadiumPOI]) -> [StadiumPOI] {
        guard let mySection else { return list.sorted { $0.name < $1.name } }
        return list.sorted { a, b in
            let da = sectionDistance(a, from: mySection)
            let db = sectionDistance(b, from: mySection)
            return da == db ? a.name < b.name : da < db
        }
    }

    /// Sections are numbered sequentially around the bowl, so a higher vs.
    /// lower section number gives a real (if approximate) walking
    /// direction — not GPS-precise, but more actionable than a bare
    /// distance number.
    private func directionBadge(from mySection: Int, to targetSection: Int) -> some View {
        let distance = abs(targetSection - mySection)
        return HStack(spacing: 3) {
            if distance > 0 {
                Image(systemName: targetSection > mySection ? "arrow.right" : "arrow.left")
            }
            Text(distance == 0 ? l10n.t("stadiums.sameSection") : "\(l10n.t("stadiums.sectionPrefix")) \(targetSection)")
        }
        .font(.bpTiny())
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.bpAmber.opacity(0.15), in: Capsule())
        .foregroundStyle(Color.bpAmber)
    }

    private func sectionDistance(_ poi: StadiumPOI, from mySection: Int) -> Int {
        guard let n = Self.sectionNumber(poi.sectionOrConcourse) else { return .max }
        return abs(n - mySection)
    }

    /// First contiguous digit run in a section string, e.g. "Section 118"
    /// -> 118, "Sections 117-119, 100-North side..." -> 117.
    private static func sectionNumber(_ text: String?) -> Int? {
        guard let text else { return nil }
        var current = ""
        for ch in text {
            if ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                break
            }
        }
        return current.isEmpty ? nil : Int(current)
    }

    var body: some View {
        ZStack {
            BPBackgroundView()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else {
                VStack(spacing: 0) {
                    header

                    if !events.isEmpty {
                        eventsRail
                    }

                    HStack(alignment: .top, spacing: 0) {
                        levelRail
                            .frame(width: 74)

                        ScrollView {
                            VStack(alignment: .leading, spacing: BPSpacing.lg) {
                                if let selectedLevel {
                                    Text(selectedLevel)
                                        .font(.bpTitle2())
                                        .foregroundStyle(Color.bpInk)
                                        .padding(.top, BPSpacing.lg)
                                }

                                ringMap

                                mySectionField

                                howToGetThereCard

                                ForEach(groupedByType, id: \.type) { group in
                                    poiSection(group)
                                }
                            }
                            .padding(.horizontal, BPSpacing.lg)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
        }
        .navigationTitle(stadium.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // TestFlight feedback: "doesn't show a picture or description
            // of the stadium" — real photo when we have one (sourced the
            // same way venue photos are); the mascot badge below still
            // carries the header when we don't, so there's no missing/
            // broken-looking gap either way.
            if let urlString = stadium.imageURL, let url = URL(string: urlString) {
                CachedImage(url: url, targetSize: CGSize(width: 800, height: 450), priority: .hot) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.bpCardBackground
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: BPRadius.lg))
                .padding(.horizontal, BPSpacing.lg)
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(
                        LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    Image(systemName: "sportscourt.fill")
                        .font(.bpScaled(20, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stadium.name)
                        .font(.bpTitle2())
                        .foregroundStyle(Color.bpInk)
                    Text(stadium.address)
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, BPSpacing.lg)

            if let description = stadium.description, !description.isEmpty {
                Text(description)
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
                    .padding(.horizontal, BPSpacing.lg)
            }
        }
        .padding(.vertical, BPSpacing.lg)
    }

    // MARK: - Events

    /// Real events from Ticketmaster (sync-stadium-events.ts) — never
    /// invented. Horizontal rail up top since events aren't tied to a
    /// single level the way POIs are.
    private var eventsRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("stadiums.upcomingEvents"))
                .font(.bpCaption())
                .foregroundStyle(Color.bpAmber)
                .textCase(.uppercase)
                .padding(.horizontal, BPSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(events) { event in
                        eventCard(event)
                    }
                }
                .padding(.horizontal, BPSpacing.lg)
            }
        }
        .padding(.bottom, BPSpacing.md)
    }

    private func eventCard(_ event: StadiumEvent) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Text(event.startsAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.bpTiny())
                .foregroundStyle(Color.bpAmber)
            Text(event.name)
                .font(.bpScaled(13, weight: .bold))
                .foregroundStyle(Color.bpInk)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(event.startsAt, format: .dateTime.hour().minute())
                .font(.bpSmall())
                .foregroundStyle(Color.bpTextSecondary)
        }
        .padding(BPSpacing.md)
        .frame(width: 180, alignment: .leading)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))

        if let urlString = event.ticketURL, let url = URL(string: urlString) {
            return AnyView(Link(destination: url) { content })
        }
        return AnyView(content)
    }

    // MARK: - Level rail

    /// A vertical stack of pills — visually reads as a cross-section of the
    /// building (Suite/300 at top, Field at the bottom), not a generic tab
    /// bar. Tapping a level is the whole interaction model for v1: no map
    /// geometry exists to tap into yet.
    private var levelRail: some View {
        VStack(spacing: 8) {
            ForEach(levels, id: \.name) { level in
                let isSelected = level.name == selectedLevel
                Button {
                    BPHaptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedLevel = level.name
                    }
                } label: {
                    Text(shortLabel(level.name))
                        .font(.bpScaled(11, weight: .bold))
                        .multilineTextAlignment(.center)
                        .frame(width: 58, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: BPRadius.md)
                                .fill(isSelected ? Color.bpAmber : Color.bpCardBackground)
                        )
                        .foregroundStyle(isSelected ? .black : Color.bpTextSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: BPRadius.md)
                                .strokeBorder(isSelected ? Color.clear : Color.bpBorder)
                        )
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: level.name, isButton: true)

                if level.name != levels.last?.name {
                    Rectangle().fill(Color.bpBorder).frame(width: 2, height: 10)
                }
            }
        }
        .padding(.vertical, BPSpacing.lg)
        .padding(.leading, BPSpacing.lg)
    }

    private func shortLabel(_ levelName: String) -> String {
        if let paren = levelName.firstIndex(of: "(") {
            return String(levelName[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        return levelName
    }

    // MARK: - Ring map

    /// The hand-drawn ring diagram never read as a real stadium — replaced
    /// with Ticketmaster's actual static seatmap image for this venue
    /// (`stadium.seatmapURL`, from a current event's `seatmap.staticUrl`).
    /// It's a real, official-quality graphic with true section geometry;
    /// we don't have per-section pixel coordinates for it, so it's shown
    /// as a reference image (pinch-zoomable) rather than pinned — the
    /// "where do I walk" guidance comes from `howToGetThereCard` below,
    /// driven by the real section-number data we do have.
    private var ringMap: some View {
        Group {
            if let urlString = stadium.seatmapURL, let url = URL(string: urlString) {
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    CachedImage(url: url, targetSize: CGSize(width: 1024, height: 1024), priority: .hot) { img in
                        img.resizable().scaledToFit().frame(width: 480)
                    } placeholder: {
                        ProgressView().tint(Color.bpAmber).frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .frame(height: 240)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
            }
        }
        .padding(.vertical, BPSpacing.sm)
    }

    /// The active "how do I get there" answer — appears once a POI is
    /// selected (from the list or the map) and stays pinned above the
    /// list so it reads as active guidance, not a passing tooltip.
    private var howToGetThereCard: some View {
        Group {
            if let selectedMapPOI {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: selectedMapPOI.type.icon)
                            .foregroundStyle(Color.bpAmber)
                        Text(selectedMapPOI.name)
                            .font(.bpScaled(14, weight: .bold))
                            .foregroundStyle(Color.bpInk)
                        Spacer()
                        Button {
                            BPHaptics.light()
                            self.selectedMapPOI = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.bpTextSecondary)
                        }
                    }

                    Text(selectedMapPOI.subtitle)
                        .font(.bpScaled(12, weight: .semibold))
                        .foregroundStyle(Color.bpTextSecondary)

                    if let mySection, let n = Self.sectionNumber(selectedMapPOI.sectionOrConcourse) {
                        directionBadge(from: mySection, to: n)
                    } else if mySection == nil {
                        Text(l10n.t("stadiums.enterSectionHint"))
                            .font(.bpScaled(11))
                            .foregroundStyle(Color.bpTextTertiary)
                    }
                }
                .padding(BPSpacing.md)
                .background(Color.bpAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpAmber.opacity(0.3)))
            }
        }
    }

    // MARK: - My section

    /// No coordinates exist in the data, so real routing isn't honest to
    /// offer — this lets the user anchor "closest" to their own seat
    /// section instead, which the data actually supports.
    private var mySectionField: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill")
                .foregroundStyle(Color.bpAmber)
                .font(.bpScaled(13))

            TextField(l10n.t("stadiums.mySectionPlaceholder"), text: $sectionInput)
                .keyboardType(.numberPad)
                .font(.bpScaled(14, weight: .semibold))
                .foregroundStyle(Color.bpInk)
                .focused($sectionFieldFocused)
                .onChange(of: sectionInput) { _, newValue in
                    mySection = Int(newValue.filter(\.isNumber))
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(l10n.t("common.done")) { sectionFieldFocused = false }
                            .foregroundStyle(Color.bpAmber)
                    }
                }

            if mySection != nil {
                Button {
                    BPHaptics.light()
                    sectionInput = ""
                    mySection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.bpTextSecondary)
                }
            }
        }
        .padding(.horizontal, BPSpacing.md)
        .padding(.vertical, 10)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
    }

    // MARK: - POI list

    private func poiSection(_ group: (type: StadiumPOIType, pois: [StadiumPOI])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(group.type.label, systemImage: group.type.icon)
                .font(.bpCaption())
                .foregroundStyle(Color.bpAmber)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(group.pois) { poi in
                    poiRow(poi)
                }
            }
        }
    }

    private func poiRow(_ poi: StadiumPOI) -> some View {
        HStack(spacing: 12) {
            Image(systemName: poi.type.icon)
                .font(.bpScaled(15))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name)
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                Text(poi.subtitle)
                    .font(.bpSmall())
                    .foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()

            if let mySection, let n = Self.sectionNumber(poi.sectionOrConcourse) {
                directionBadge(from: mySection, to: n)
            }

            if poi.confidence == "unverified" {
                Text(l10n.t("stadiums.unverified"))
                    .font(.bpTiny())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.bpDanger.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.bpDanger)
            } else if let url = URL(string: poi.sourceURL) {
                Link(destination: url) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.bpScaled(12))
                        .foregroundStyle(Color.bpGreen)
                }
            }
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(
            selectedMapPOI?.id == poi.id ? Color.bpAmber.opacity(0.6) : Color.bpBorder,
            lineWidth: selectedMapPOI?.id == poi.id ? 1.5 : 1
        ))
        .contentShape(Rectangle())
        .onTapGesture {
            BPHaptics.light()
            selectedMapPOI = selectedMapPOI?.id == poi.id ? nil : poi
        }
        .bpAccessibility(label: poi.name, hint: poi.subtitle, isButton: true)
    }

    private func load() async {
        async let poisTask = RepositoryDependencies.stadium.pois(stadiumId: stadium.id)
        async let eventsTask = RepositoryDependencies.stadium.events(stadiumId: stadium.id)
        pois = (try? await poisTask) ?? []
        events = (try? await eventsTask) ?? []
        if selectedLevel == nil {
            selectedLevel = levels.first?.name
        }
        isLoading = false
    }
}
