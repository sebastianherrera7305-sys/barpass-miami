import SwiftUI

/// "Inside the venue" guide for large compounds where the pin on a map
/// tells you nothing about what's in there — zones, bars, what drinks
/// cost, how to get in and out. Every fact carries its source and date;
/// nothing here is inferred. Factory Town (2026-09-06) is the first entry:
/// seven acres, five stages, no published floor plan — so this is a zone
/// guide, deliberately NOT a drawn map (positions change per event and we
/// have no source for them).
struct VenueInsideGuide {
    struct Fact: Identifiable {
        let id = UUID()
        let es: String
        let en: String
        /// Where this came from — shown to the user, always.
        let source: String
        /// "official" = the venue itself; "reported" = attendee reviews.
        let isOfficial: Bool
        let date: String
        func text(_ lang: AppLanguage) -> String { lang == .es ? es : en }
    }

    struct Zone: Identifiable {
        let id = UUID()
        let name: String
        let es: String
        let en: String
        let icon: String
        func blurb(_ lang: AppLanguage) -> String { lang == .es ? es : en }
    }

    struct TonightLineup {
        /// Local calendar day (venue timezone) this lineup applies to.
        let year: Int, month: Int, day: Int
        let timeZone: TimeZone
        let title: String
        let artists: [String]
        let source: String

        var isToday: Bool {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let now = cal.dateComponents([.year, .month, .day], from: Date())
            // Nights run past midnight — the event "day" also covers the
            // small hours of the following morning.
            if now.year == year && now.month == month && now.day == day { return true }
            let next = cal.date(byAdding: .day, value: 1, to: cal.date(from: DateComponents(year: year, month: month, day: day))!)!
            let nextC = cal.dateComponents([.year, .month, .day], from: next)
            let hour = cal.component(.hour, from: Date())
            return now.year == nextC.year && now.month == nextC.month && now.day == nextC.day && hour < 8
        }
    }

    let zonesSource: String
    let zones: [Zone]
    let barsAndPrices: [Fact]
    let logistics: [Fact]
    let tonight: TonightLineup?

    /// Keyed by venues.id — never by name (names repeat across cities).
    static func guide(for venueId: String) -> VenueInsideGuide? {
        guides[venueId]
    }

    private static let guides: [String: VenueInsideGuide] = [
        // Factory Town, 4800 NW 37th Ave, Miami — venues.id verified 2026-09-06
        "dfeef7e2-509a-42be-a72d-01a087e07e47": VenueInsideGuide(
            zonesSource: "factorytown.com/venue",
            zones: [
                Zone(name: "Infinity Room",
                     es: "Columnas de acero enmarcando el cielo abierto — el escenario principal, el rig de luces y láseres más grande.",
                     en: "Towering steel columns framing the open sky — the main stage, biggest lighting and laser rig.",
                     icon: "sparkles"),
                Zone(name: "The Park",
                     es: "El escenario al aire libre entre estructura y cielo; la zona más amplia para moverse.",
                     en: "The open-air stage between structure and sky; the roomiest area to move around.",
                     icon: "leaf.fill"),
                Zone(name: "Warehouse",
                     es: "Nave cerrada de concreto, cuatro paredes hechas para el bajo más pesado. Frío e industrial.",
                     en: "Indoor concrete fortress, four walls built to trap the heaviest frequencies. Cold and industrial.",
                     icon: "building.2.fill"),
                Zone(name: "Chain Room",
                     es: "El «motor subterráneo»: las cadenas transportadoras de la fábrica de colchones siguen en el techo. Crudo, con cañones de CO₂.",
                     en: "The 'underground engine': the mattress factory's conveyor chains still hang overhead. Raw, with CO₂ cannons.",
                     icon: "link"),
                Zone(name: "Cypress End",
                     es: "Pegado a las vías del tren — íntimo, sin filtro. El escenario más pequeño.",
                     en: "Hard against the train tracks — intimate, unfiltered. The smallest stage.",
                     icon: "tram.fill"),
            ],
            barsAndPrices: [
                Fact(es: "Hay bares y comida en todas las zonas; asistentes reportan filas cortas y servicio rápido.",
                     en: "Bars and food are spread across every zone; attendees report short lines and fast service.",
                     source: "Google reviews", isOfficial: false, date: "nov 2025"),
                Fact(es: "Agua embotellada: $5 reportado por asistentes.",
                     en: "Bottled water: $5 reported by attendees.",
                     source: "Google review", isOfficial: false, date: "mar 2026"),
                Fact(es: "Cócteles: reportados desde $25. Otros asistentes los describen como «precio razonable» — depende del evento.",
                     en: "Cocktails: reported from $25. Other attendees call them 'reasonably priced' — varies by event.",
                     source: "Reseñas de asistentes (mindtrip.ai)", isOfficial: false, date: "2026"),
                Fact(es: "Marcas oficiales en barra: Stella Artois, Red Bull, NÜTRL, Happy Dad, Monaco.",
                     en: "Official beverage partners at the bars: Stella Artois, Red Bull, NÜTRL, Happy Dad, Monaco.",
                     source: "factorytown.com", isOfficial: true, date: "2026"),
                Fact(es: "VIP: barras privadas junto a cada zona y baños exclusivos; plataformas de vista a ambos lados del escenario.",
                     en: "VIP: private bars next to every area and VIP-only restrooms; viewing platforms on both sides of the stage.",
                     source: "Google reviews", isOfficial: false, date: "nov–dic 2025"),
                Fact(es: "Mesas VIP: desde ~$1,500–3,000 en noches regulares, según revendedores. Solo 21+.",
                     en: "VIP tables: from ~$1,500–3,000 on regular nights per resellers. 21+ only.",
                     source: "miamiviplife.com · factorytown.com", isOfficial: false, date: "2026"),
            ],
            logistics: [
                Fact(es: "Entrada norte. El contenedor de Guest Services (objetos perdidos) está junto a la entrada norte.",
                     en: "North entrance. The Guest Services container (lost & found) sits near the north entrance.",
                     source: "factorytown.com/about", isOfficial: true, date: "2026"),
                Fact(es: "NO hay reingreso en ningún evento. Si sales, no vuelves a entrar.",
                     en: "NO re-entry at any event. Once you leave, you're out.",
                     source: "factorytown.com/about", isOfficial: true, date: "2026"),
                Fact(es: "No hay parqueo. Ve en Uber/Lyft; carros mal parqueados se remolcan.",
                     en: "No parking on site. Take Uber/Lyft; illegally parked cars get towed.",
                     source: "factorytown.com/about", isOfficial: true, date: "2026"),
                Fact(es: "Bolsos: hasta 6\"×9\" de cualquier material; más grandes deben ser transparentes (máx. 12\"×6\"×12\").",
                     en: "Bags: up to 6\"×9\" any material; larger bags must be clear (max 12\"×6\"×12\").",
                     source: "factorytown.com/about", isOfficial: true, date: "2026"),
                Fact(es: "ID oficial con foto obligatorio. Eventos 18+; alcohol y mesas VIP solo 21+.",
                     en: "Government photo ID required. Events are 18+; alcohol and VIP tables 21+ only.",
                     source: "factorytown.com/about", isOfficial: true, date: "2026"),
                Fact(es: "Baños: asistentes reportan muchos en GA y zonas para sentarse.",
                     en: "Restrooms: attendees report plenty in GA plus places to sit.",
                     source: "Google review", isOfficial: false, date: "dic 2025"),
            ],
            tonight: TonightLineup(
                year: 2026, month: 9, day: 6,
                timeZone: TimeZone(identifier: "America/New_York")!,
                title: "Sara Landry",
                artists: ["Sara Landry", "fumi (DE)", "hhunter", "Mischluft", "Serafina", "Supergloss"],
                source: "ra.co"
            )
        ),
    ]
}

struct VenueInsideSection: View {
    let venue: BarPassVenue
    let guide: VenueInsideGuide
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: l10n.t("venueInside.title"), venue.name))
                .font(.bpTitle2()).foregroundStyle(Color.bpInk)

            // Honest framing: this is a zone guide, not a floor plan.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(Color.bpAmber)
                Text(l10n.t("venueInside.disclaimer"))
                    .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
            }

            if let tonight = guide.tonight, tonight.isToday {
                VStack(alignment: .leading, spacing: 6) {
                    Label(l10n.t("venueInside.tonight"), systemImage: "music.mic")
                        .font(.bpCaption()).foregroundStyle(Color.bpAmber)
                    Text(tonight.artists.joined(separator: " · "))
                        .font(.bpBody()).foregroundStyle(Color.bpInk)
                    sourceLine(tonight.source, isOfficial: false, date: nil)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bpAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: BPRadius.md))
            }

            sectionHeader(l10n.t("venueInside.zones"))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(guide.zones) { zone in
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: zone.icon).foregroundStyle(Color.bpAmber)
                        Text(zone.name).font(.bpHeadline()).foregroundStyle(Color.bpInk)
                        Text(zone.blurb(l10n.language))
                            .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
                }
            }
            sourceLine(guide.zonesSource, isOfficial: true, date: nil)

            sectionHeader(l10n.t("venueInside.barsPrices"))
            ForEach(guide.barsAndPrices) { factRow($0) }

            sectionHeader(l10n.t("venueInside.logistics"))
            ForEach(guide.logistics) { factRow($0) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.bpTiny()).tracking(1.2).foregroundStyle(Color.bpTextTertiary)
            .padding(.top, 6)
    }

    private func factRow(_ fact: VenueInsideGuide.Fact) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(fact.text(l10n.language))
                .font(.bpBody()).foregroundStyle(Color.bpInk)
                .fixedSize(horizontal: false, vertical: true)
            sourceLine(fact.source, isOfficial: fact.isOfficial, date: fact.date)
        }
    }

    private func sourceLine(_ source: String, isOfficial: Bool, date: String?) -> some View {
        HStack(spacing: 6) {
            Text(isOfficial ? l10n.t("venueInside.official") : l10n.t("venueInside.reported"))
                .font(.bpTiny())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background((isOfficial ? Color.bpGreen : Color.bpAmber).opacity(0.15), in: Capsule())
                .foregroundStyle(isOfficial ? Color.bpGreen : Color.bpAmber)
            Text([source, date].compactMap { $0 }.joined(separator: " · "))
                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
        }
    }
}
