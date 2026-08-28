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

    /// Opens the app straight into Tonight with Prompt Your Night's text
    /// field focused — DeepLinkRouter parses the bare `prompt` host with no
    /// id required (see DeepLinkRouter.swift).
    var promptURL: URL { URL(string: "barpass://prompt")! }
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
            if family == .systemSmall {
                // Two independent tap zones (Prompt Your Night / Go Home),
                // each its own Link — a single .widgetURL() can't do that,
                // it's one destination for the whole widget. The Lock
                // Screen families below stay single-target: there's no room
                // for two zones at that size, and .widgetURL is what they
                // support anyway.
                promptAndHomeContent
            } else if entry.hasHomeAddress {
                content
            } else {
                Text("Configurá tu dirección de casa en BarPass")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .widgetURL(nil)
            }
        }
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

    /// systemSmall layout: the mascot tile opens Prompt Your Night, the "P"
    /// tile opens the Uber home flow when an address is configured (falls
    /// back to just opening the app to set one). Same flat-fill / thick-
    /// outline / hard-shadow "sticker" language as the app's real logo,
    /// sized from the design exploration (BarPass Widget Concepts canvas).
    private var promptAndHomeContent: some View {
        HStack(spacing: 10) {
            Link(destination: entry.promptURL) {
                ZStack {
                    Color.white
                    Image("BarPassMascot")
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                    Text("PROMPT")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.black)
                        .padding(.bottom, 6)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.black, lineWidth: 3))
            }
            .buttonStyle(.plain)

            Link(destination: entry.hasHomeAddress ? (entry.uberURL ?? entry.promptURL) : entry.promptURL) {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.92, green: 0.72, blue: 0.28), Color(red: 0.98, green: 0.86, blue: 0.50)],
                        startPoint: .top, endPoint: .bottomTrailing
                    )
                    Image(systemName: "house.fill")
                        .font(.system(size: 46, weight: .black))
                        .foregroundStyle(.black)
                        .offset(y: -4)
                    Text(entry.hasHomeAddress ? "GO HOME" : "SET HOME")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.black.opacity(0.65))
                        .padding(.bottom, 6)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.black, lineWidth: 3))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            mascotBadge(size: 48, badgeSize: 20)
                .widgetURL(entry.uberURL)
        case .accessoryRectangular:
            HStack(spacing: 8) {
                mascotBadge(size: 34, badgeSize: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ir a casa").font(.headline)
                    Text("Un toque, Uber directo").font(.caption2)
                }
            }
            .widgetURL(entry.uberURL)
        default:
            EmptyView()
        }
    }
}

struct GoHomeWidget: Widget {
    let kind: String = "GoHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GoHomeProvider()) { entry in
            GoHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("BarPass")
        .description("Armá tu noche, o pedí un Uber a casa — un toque.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
