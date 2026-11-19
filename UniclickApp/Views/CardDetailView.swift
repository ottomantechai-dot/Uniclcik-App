import SwiftUI

// MARK: - Ficha de una carta
// Mismo esquema que la ficha de un zapato: la carta, otras de su colección, sus datos, la
// comparativa de precios y más cartas recomendadas. Al tocar otra carta, cambia aquí mismo.

struct CardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State var card: PokemonCardData
    @State private var related: [PokemonCardData] = []
    @State private var report: SaleReport?

    private var number: String { card.id.split(separator: "-").last.map { "#" + $0 } ?? "—" }
    private var setLogo: URL? { PokemonTCGClient.storedSets().first { $0.name == card.setName }?.logoURL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AsyncImage(url: card.imageURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else {
                            RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.05)).aspectRatio(0.72, contentMode: .fit)
                        }
                    }
                    .frame(height: 330).frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    .padding(.top, 6)

                    Text(card.name).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.black).padding(.top, 16)
                    HStack(spacing: 8) {
                        chip(card.setName)
                        chip(number)
                        if !card.rarity.isEmpty { chip(card.rarity) }
                    }
                    .padding(.top, 6)

                    // Otras cartas de la misma colección.
                    if !related.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(related.prefix(10)) { other in
                                    Button { select(other) } label: {
                                        AsyncImage(url: other.thumbURL) { phase in
                                            if let image = phase.image { image.resizable().scaledToFit() } else { Color.black.opacity(0.05) }
                                        }
                                        .frame(width: 46, height: 64)
                                        .padding(5)
                                        .background(Color.white, in: .rect(cornerRadius: 12))
                                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.08)) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 14)
                    }

                    priceCard.padding(.top, 16)

                    Button { report = SaleReport.from(card: card) } label: {
                        Label("Sale report and listing", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(.black, in: .capsule)
                    }
                    .buttonStyle(.plain).padding(.top, 12)

                    comparisonCard.padding(.top, 18)

                    ShoeProductDetailsCard(rows: [
                        (icon: "square.stack.3d.up", title: "Set", value: card.setName),
                        (icon: "number", title: "Card number", value: number),
                        (icon: "sparkles", title: "Rarity", value: card.rarity.isEmpty ? "—" : card.rarity),
                        (icon: "checkmark.seal", title: "Grading", value: "Ungraded (raw)"),
                    ])
                    .padding(.top, 18)

                    if !related.isEmpty {
                        Text("More from \(card.setName)").font(.system(size: 18, weight: .bold)).foregroundStyle(.black).padding(.top, 22)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(related) { other in
                                    Button { select(other) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            AsyncImage(url: other.thumbURL) { phase in
                                                if let image = phase.image { image.resizable().scaledToFit() } else { Color.black.opacity(0.05) }
                                            }
                                            .frame(width: 118, height: 160)
                                            Text(other.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black).lineLimit(1).frame(width: 118, alignment: .leading)
                                            Text(other.tcgMarketUSD.map(SaleReport.usd) ?? "No price")
                                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                                .foregroundStyle(other.tcgMarketUSD == nil ? Color.black.opacity(0.4) : .black)
                                        }
                                        .padding(10)
                                        .background(.white, in: .rect(cornerRadius: 18))
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollClipDisabled()
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
                .id(card.id)
            }
            .background(Color(red: 0.965, green: 0.965, blue: 0.975).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItem(placement: .principal) {
                    AsyncImage(url: setLogo) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { Color.clear }
                    }
                    .frame(width: 90, height: 28)
                }
            }
            .task(id: card.setName) {
                let found = await PokemonTCGClient.fetchPage(query: "set.name:\"\(card.setName)\"", page: 1, pageSize: 30) ?? []
                related = found.filter { $0.id != card.id }
            }
            .fullScreenCover(item: $report) { SaleReportView(report: $0) }
        }
        .preferredColorScheme(.light)
    }

    private func select(_ other: PokemonCardData) {
        let previous = card
        withAnimation(.snappy) {
            card = other
            related = related.filter { $0.id != other.id } + [previous]
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.65)).lineLimit(1)
            .padding(.horizontal, 10).frame(height: 28)
            .background(.white, in: .capsule)
            .glassEffect(.regular, in: .capsule)
    }

    /// Precio de mercado real y su tendencia.
    private var priceCard: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Market price").font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.55))
                Text(card.tcgMarketUSD.map(SaleReport.usd) ?? "—")
                    .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            }
            Spacer()
            if card.changePercent != 0 {
                Text(String(format: "%+.0f%%", card.changePercent))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(card.changePercent >= 0 ? Color(red: 0.13, green: 0.55, blue: 0.30) : Color.red, in: .capsule)
            }
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(.white, in: .rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// Dónde comprarla o venderla: precios confirmados donde los hay; raya donde no.
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Price comparison").font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
            HStack(spacing: 8) {
                source(name: "TCGplayer", logo: nil, value: card.tcgMarketUSD.map(SaleReport.usd))
                source(name: "Cardmarket", logo: nil, value: card.cardmarketEUR.map { String(format: "€%.2f", $0) })
            }
            HStack(spacing: 8) {
                source(name: "eBay", logo: "eBay", value: nil)
                source(name: "StockX", logo: "StockX", value: nil)
            }
            Text("TCGplayer and Cardmarket prices are live. eBay and StockX appear once connected.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.45))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func source(name: String, logo: String?, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let logo {
                StylizedMarketplaceLogo(brand: logo).frame(height: 14).frame(maxWidth: 62, alignment: .leading)
            } else {
                Text(name).font(.system(size: 13, weight: .heavy)).foregroundStyle(.black)
            }
            Text(value ?? "—").font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(value == nil ? Color.black.opacity(0.25) : .black)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.04), in: .rect(cornerRadius: 14))
    }
}
