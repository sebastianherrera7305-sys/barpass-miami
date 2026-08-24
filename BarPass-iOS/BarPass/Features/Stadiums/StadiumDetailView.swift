import SwiftUI

/// The Interactive Venue Map's first shippable slice: browse a stadium by
/// level, see real sourced POIs. No routing/3D yet — see
/// BRIEF-hard-rock-stadium.md's phased research for why that's not
/// buildable with public data alone today. Every POI traces back to a real
/// official source; nothing here is invented.
struct StadiumDetailView: View {
    let stadium: Stadium

    @State private var pois: [StadiumPOI] = []
    @State private var isLoading = true
    @State private var selectedLevel: String?

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
            return (type, list.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        ZStack {
            BPBackgroundView()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else {
                VStack(spacing: 0) {
                    header

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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(
                        LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    Text("🏟️").font(.bpScaled(24))
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
        }
        .padding(BPSpacing.lg)
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
                if let section = poi.sectionOrConcourse {
                    Text(section)
                        .font(.bpSmall())
                        .foregroundStyle(Color.bpTextSecondary)
                }
            }
            Spacer()

            if poi.confidence == "unverified" {
                Text("sin verificar")
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
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
    }

    private func load() async {
        pois = (try? await RepositoryDependencies.stadium.pois(stadiumId: stadium.id)) ?? []
        if selectedLevel == nil {
            selectedLevel = levels.first?.name
        }
        isLoading = false
    }
}
