import SwiftUI

/// La carta completa de un local.
///
/// Existe porque la pantalla del venue mostraba seis tragos y la tabla tiene
/// cuarenta y cinco (Boxcar, Gainesville, leídos de un JPG). Seis de cuarenta
/// y cinco no es un resumen: es una carta distinta.
///
/// Dos decisiones que no son cosméticas:
///
/// 1. Un precio que la carta no publica se muestra como "sin precio", nunca
///    como `$0`. El cero es un número que alguien puede creer.
/// 2. Al pie va la procedencia: de dónde salió cada precio y cuándo, con un
///    link a la fuente cuando la hay. La carta de un bar cambia; el usuario
///    tiene que poder ver si lo que está leyendo es de esta temporada, y
///    verificarlo sin salir de la app.
struct VenueMenuView: View {
    let venue: BarPassVenue
    let items: [VenueMenuItem]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    /// Las categorías presentes, en el orden en que una carta se lee, y sólo
    /// las que tienen algo adentro.
    private var groups: [(category: VenueMenuCategory, items: [VenueMenuItem])] {
        let byCategory = Dictionary(grouping: items) { VenueMenuCategory(raw: $0.category) }
        return VenueMenuCategory.allCases.compactMap { category in
            guard let rows = byCategory[category], !rows.isEmpty else { return nil }
            return (category, rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    /// Una línea de procedencia por origen distinto. Casi siempre es una sola
    /// (toda la carta salió del mismo PDF o de la misma foto), pero cuando un
    /// local tiene precios de dos orígenes hay que decirlo.
    private var provenance: [ProvenanceLine] {
        var seen: [String: ProvenanceLine] = [:]
        for item in items {
            let key = "\(item.source)|\(item.sourceUrl ?? "")"
            if var existing = seen[key] {
                existing.count += 1
                // La fecha que se muestra es la más reciente de ese origen.
                if let at = item.extractedAt, existing.extractedAt == nil || at > existing.extractedAt! {
                    existing.extractedAt = at
                }
                seen[key] = existing
            } else {
                seen[key] = ProvenanceLine(
                    id: key,
                    source: VenueMenuSource(raw: item.source),
                    sourceUrl: item.sourceUrl,
                    extractedAt: item.extractedAt,
                    count: 1
                )
            }
        }
        return seen.values.sorted { $0.count > $1.count }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: BPSpacing.xl) {
                            header
                            ForEach(groups, id: \.category) { group in
                                section(group.category, group.items)
                            }
                            provenanceFooter
                        }
                        .padding(.horizontal, BPSpacing.lg)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(l10n.t("menu.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("menu.close")) { dismiss() }
                        .foregroundStyle(Color.bpTextSecondary)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(venue.name)
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
            Text(String(format: l10n.t("menu.itemsCount"), items.count))
                .font(.bpSmall())
                .foregroundStyle(Color.bpTextSecondary)
        }
        .padding(.top, BPSpacing.md)
    }

    // MARK: - Una categoría

    private func section(_ category: VenueMenuCategory, _ rows: [VenueMenuItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.bpScaled(12, weight: .bold))
                Text(l10n.t(category.titleKey).uppercased())
                    .font(.bpScaled(12, weight: .bold))
                    .tracking(1.2)
                Spacer()
                Text("\(rows.count)")
                    .font(.bpScaled(12, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.bpTextTertiary)
            }
            .foregroundStyle(Color.bpAmber)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Color.bpBorder)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, BPSpacing.md)
            .padding(.vertical, 2)
            .background(Color.bpSurfaceRaised, in: RoundedRectangle(cornerRadius: BPRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BPRadius.lg, style: .continuous)
                    .stroke(Color.bpBorder, lineWidth: 1)
            )
        }
    }

    private func row(_ item: VenueMenuItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BPSpacing.md) {
            Text(item.name)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            priceLabel(item.price)
        }
        .padding(.vertical, 11)
        .bpAccessibility(label: "\(item.name), \(priceSpokenText(item.price))")
    }

    /// El único lugar donde se decide cómo se ve un precio. NULL no es cero:
    /// se dice que no hay precio, en gris, y el ítem sigue estando.
    @ViewBuilder
    private func priceLabel(_ price: Double?) -> some View {
        if let price {
            Text(Self.formatted(price))
                .font(.bpScaled(14, weight: .bold, design: .monospaced))
                // Números tabulares: las columnas de precios quedan
                // alineadas aunque los dígitos sean distintos.
                .monospacedDigit()
                .foregroundStyle(Color.bpAmber)
        } else {
            Text(l10n.t("menu.noPrice"))
                .font(.bpScaled(12))
                .foregroundStyle(Color.bpTextTertiary)
        }
    }

    private func priceSpokenText(_ price: Double?) -> String {
        price.map(Self.formatted) ?? l10n.t("menu.noPrice")
    }

    /// `$12` cuando el precio es redondo, `$12.50` cuando no. Una carta que
    /// imprime "12" no debería leerse "12.00".
    static func formatted(_ price: Double) -> String {
        let rounded = (price * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(format: "$%.0f", rounded)
        }
        return String(format: "$%.2f", rounded)
    }

    // MARK: - Procedencia

    private struct ProvenanceLine: Identifiable {
        let id: String
        let source: VenueMenuSource
        let sourceUrl: String?
        var extractedAt: Date?
        var count: Int
    }

    private var provenanceFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("menu.source.title").uppercased())
                .font(.bpScaled(11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Color.bpTextTertiary)

            ForEach(provenance) { line in
                VStack(alignment: .leading, spacing: 4) {
                    Text(provenanceText(line))
                        .font(.bpSmall())
                        .foregroundStyle(Color.bpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let urlString = line.sourceUrl, let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text(l10n.t("menu.source.open"))
                            }
                            .font(.bpScaled(11, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                        }
                        .bpAccessibility(label: l10n.t("menu.source.open"), isButton: true)
                    }
                }
            }

            Text(l10n.t("menu.source.disclaimer"))
                .font(.bpScaled(11))
                .foregroundStyle(Color.bpTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BPSpacing.md)
        .background(Color.bpSurfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: BPRadius.lg, style: .continuous))
    }

    private func provenanceText(_ line: ProvenanceLine) -> String {
        let sourceName = line.source.titleKey.map { l10n.t($0) } ?? (line.source.rawLabel ?? l10n.t("menu.source.unknown"))
        guard let extractedAt = line.extractedAt else {
            return String(format: l10n.t("menu.source.fromOnly"), sourceName)
        }
        let date = L10n.dateFormatter("d MMM yyyy").string(from: extractedAt)
        return String(format: l10n.t("menu.source.fromOn"), sourceName, date)
    }

    // MARK: - Sin carta

    /// No debería verse casi nunca: la entrada que abre esta pantalla no se
    /// dibuja cuando el local no tiene carta. Está igual porque la pantalla
    /// se puede abrir desde un deep link o quedar abierta mientras la carta
    /// se vacía, y un fondo negro sin explicación es peor.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.bpScaled(30))
                .foregroundStyle(Color.bpTextTertiary)
            Text(l10n.t("menu.empty.title"))
                .font(.bpHeadline())
                .foregroundStyle(Color.bpInk)
            Text(l10n.t("menu.empty.subtitle"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(BPSpacing.xl)
    }
}
