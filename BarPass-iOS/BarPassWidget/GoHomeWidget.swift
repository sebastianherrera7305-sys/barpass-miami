import WidgetKit
import SwiftUI

/// Reads the same home-address coordinates GoHomeStore (main app) writes to
/// the shared App Group container — the widget process can't call
/// Supabase/Keychain itself, so the main app is the only writer here.
private enum SharedHomeAddress {
    private nonisolated(unsafe) static let suite = UserDefaults(suiteName: "group.com.sebastian.barpass")

    static var coordinate: (lat: Double, lng: Double)? {
        guard let suite else { return nil }
        let lat = suite.double(forKey: "home_lat")
        let lng = suite.double(forKey: "home_lng")
        guard lat != 0 || lng != 0 else { return nil }
        return (lat, lng)
    }

}

struct GoHomeEntry: TimelineEntry {
    let date: Date
    let coordinate: (lat: Double, lng: Double)?

    var hasHomeAddress: Bool { coordinate != nil }

    /// Built from the entry's own captured coordinate, not a fresh
    /// UserDefaults read — the tap action must use exactly the data that
    /// decided what got displayed, not a second, independent read of the
    /// shared container that could disagree with the first.
    var uberURL: URL? {
        guard let coordinate else { return nil }
        // Built as one literal string, not via URLComponents.queryItems —
        // assigning `.queryItems = [...]` REPLACES whatever the initial
        // "uber://?action=setPickup" string parsed as its query, silently
        // dropping "action=setPickup" (the parameter that tells Uber this
        // is a pickup/dropoff request at all). Matches the proven-working
        // pattern already used in VenueDetailView.openUber().
        return URL(string: "uber://?action=setPickup&pickup=my_location&dropoff[latitude]=\(coordinate.lat)&dropoff[longitude]=\(coordinate.lng)&dropoff[nickname]=Home")
    }
}

struct GoHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoHomeEntry {
        GoHomeEntry(date: Date(), coordinate: (lat: 25.7617, lng: -80.1918))
    }

    func getSnapshot(in context: Context, completion: @escaping (GoHomeEntry) -> Void) {
        completion(GoHomeEntry(date: Date(), coordinate: SharedHomeAddress.coordinate))
    }

    /// One entry, no expiry — this isn't time-varying content, it just
    /// needs to reflect "is a home address configured" whenever iOS
    /// chooses to render it. WidgetCenter.reloadTimelines(...) from the
    /// main app (called when GoHomeStore saves) is what actually refreshes
    /// this, not a timeline schedule.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GoHomeEntry>) -> Void) {
        let entry = GoHomeEntry(date: Date(), coordinate: SharedHomeAddress.coordinate)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct GoHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoHomeEntry

    var body: some View {
        Group {
            if entry.hasHomeAddress {
                content
            } else {
                Text("Configurá tu dirección de casa en BarPass")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
        }
        .widgetURL(entry.uberURL)
        // Required since iOS 17 — a manual .background() on the root view
        // (the old pattern below) makes WidgetKit refuse to render the
        // widget at all, showing "Please adopt containerBackground API"
        // instead of any content.
        .containerBackground(for: .widget) {
            if family == .systemSmall { Color.black } else { Color.clear }
        }
    }

    /// The mascot with a small house badge — same visual language as the
    /// app's real logo (BarPassLogo in DesignSystem.swift: mascot in a
    /// white circle), not a generic SF Symbol house icon.
    private func mascotBadge(size: CGFloat, badgeSize: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image("BarPassMascot")
                .resizable()
                .scaledToFit()
                .padding(size * 0.14)
                .frame(width: size, height: size)
                .background(.white, in: Circle())

            ZStack {
                Circle().fill(Color(red: 0.92, green: 0.72, blue: 0.28))
                Image(systemName: "house.fill")
                    .font(.system(size: badgeSize * 0.55, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: badgeSize, height: badgeSize)
            .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            mascotBadge(size: 48, badgeSize: 20)
        case .accessoryRectangular:
            HStack(spacing: 8) {
                mascotBadge(size: 34, badgeSize: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ir a casa").font(.headline)
                    Text("Un toque, Uber directo").font(.caption2)
                }
            }
        default:
            // The same psychedelic sunburst art used behind Tonight/Plan/
            // Profile in the main app (CityArtMiami) — makes the widget
            // instantly recognizable as BarPass on a home screen full of
            // generic gray/white widgets, not just a mascot on a flat tile.
            ZStack {
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                VStack(spacing: 6) {
                    Spacer()
                    mascotBadge(size: 56, badgeSize: 24)
                    Text("IR A CASA")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                    Spacer().frame(height: 6)
                }
            }
        }
    }
}

struct GoHomeWidget: Widget {
    let kind: String = "GoHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GoHomeProvider()) { entry in
            GoHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Ir a casa")
        .description("Un toque para pedir un Uber a tu casa.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
