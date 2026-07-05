import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var venueStore: VenueStore
    @State private var searchText = ""
    @State private var selectedType: VenueType? = nil

    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Header
                    Text("Explorar")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.top, 60)

                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.white.opacity(0.35))
                        TextField("Buscar venues, zonas, vibes...", text: $searchText)
                            .foregroundStyle(.white)
                            .tint(amber)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.09)))
                    .padding(.horizontal, 20)

                    // Type filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            typeChip(nil, label: "Todos")
                            ForEach(VenueType.allCases, id: \.self) { type in
                                typeChip(type, label: type.rawValue)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Venue grid
                    let filtered = searchText.isEmpty
                        ? venueStore.venues.filter { selectedType == nil || $0.type == selectedType }
                        : venueStore.filtered(by: searchText)

                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { venue in
                            NavigationLink(destination: VenueDetailView(venue: venue)) {
                                VenueListRow(venue: venue)
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 1)
                                .padding(.leading, 76)
                        }
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 120)
                }
            }
        }
    }

    private func typeChip(_ type: VenueType?, label: String) -> some View {
        let selected = selectedType == type
        return Button {
            withAnimation(.spring(response: 0.3)) { selectedType = type }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(selected ? amber : Color.white.opacity(0.08))
                )
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

struct VenueListRow: View {
    let venue: Venue
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        HStack(spacing: 14) {
            Text(venue.emoji)
                .font(.system(size: 28))
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(venue.neighborhood) · \(venue.type.rawValue)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(amber)
                    Text(String(format: "%.1f", venue.rating))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text("·").foregroundStyle(Color.white.opacity(0.2))
                    Text(venue.priceRange)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }

            Spacer()

            if venue.isOpenNow {
                Text("Abierto")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.9, blue: 0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.2, green: 0.9, blue: 0.4).opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
