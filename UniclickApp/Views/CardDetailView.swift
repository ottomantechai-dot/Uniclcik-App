import SwiftUI

// MARK: - Ficha de una carta
// Mismo esquema que la ficha de un zapato: la carta, otras de su colección, sus datos, la
// comparativa de precios y más cartas recomendadas. Al tocar otra carta, cambia aquí mismo.

struct CardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State var card: PokemonCardData
    @State private var related: [PokemonCardData] = []
    @State private var report: SaleReport?
    /// Cartas de cada colección ya pedidas: al volver a una colección salen al instante.
    private static var relatedCache: [String: [PokemonCardData]] = [:]

    private let gray = Color(red: 0.965, green: 0.965, blue: 0.975)
    private var number: String { card.id.split(separator: "-").last.map { "#" + $0 } ?? "—" }
    private var setLogo: URL? { PokemonTCGClient.storedSets().first { $0.name == card.setName }?.logoURL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CardImage(url: card.imageURL, preview: card.thumbURL)
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
                                        CardImage(url: other.thumbURL)
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

                    gradeTable.padding(.top, 18)

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
                                            CardImage(url: other.thumbURL)
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
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 52) }
            .overlay(alignment: .top) {
                HStack {
                    Button { dismiss() } label: { TopBarGlassButton(systemImage: "xmark") }.buttonStyle(.plain)
                    Spacer()
                    CardImage(url: setLogo, placeholder: false).frame(width: 96, height: 30)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
                .background {
                    LinearGradient(colors: [gray, gray.opacity(0.92), gray.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top)
                }
            }
            .modifier(BottomFade(color: gray))
            .task(id: card.setName) {
                if let known = Self.relatedCache[card.setName] { related = known.filter { $0.id != card.id }; return }
                let found = await PokemonTCGClient.fetchPage(query: "set.name:\"\(card.setName)\"", page: 1, pageSize: 30) ?? []
                if !found.isEmpty { Self.relatedCache[card.setName] = found }
                CardImage.prefetch(found.compactMap(\.thumbURL))
                related = found.filter { $0.id != card.id }
            }
            .fullScreenCover(item: $report) { SaleReportView(report: $0) }
        }
        .preferredColorScheme(.light)
        .swipeBackToDismiss()
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
            source(name: "Collectr", logo: nil, value: nil)
            HStack(spacing: 8) {
                source(name: "TCGplayer", logo: nil, value: card.tcgMarketUSD.map(SaleReport.usd))
                source(name: "Cardmarket", logo: nil, value: card.cardmarketEUR.map { String(format: "€%.2f", $0) })
            }
            Text("TCGplayer and Cardmarket prices are live. Collectr appears once connected.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.45))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// «Market prices» de la carta: una fila por gradación y una columna por plataforma.
    private var gradeTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image("IconMercado").resizable().scaledToFit().frame(width: 20, height: 20).foregroundStyle(.black)
                Text("MARKET PRICES").font(.system(size: 12, weight: .heavy)).tracking(0.9).foregroundStyle(.black.opacity(0.88))
            }
            .padding(.bottom, 6)
            HStack(spacing: 8) {
                Image("LogoPSAMark").resizable().scaledToFit().frame(height: 11).foregroundStyle(Color(red: 0.93, green: 0.05, blue: 0.05))
                    .frame(width: 58, height: 38).background(Color.black.opacity(0.05), in: .rect(cornerRadius: 11))
                ForEach(["Collectr", "TCGplayer", "Cardmarket"], id: \.self) { name in
                    Text(name).font(.system(size: 10, weight: .heavy)).foregroundStyle(.black).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 38).background(Color.black.opacity(0.05), in: .rect(cornerRadius: 11))
                }
            }
            ForEach(["Raw", "8", "9", "10"], id: \.self) { grade in
                HStack(spacing: 8) {
                    Group {
                        if grade == "Raw" { Text("RAW").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white) }
                        else { DotMatrixText(text: grade) }
                    }
                    .frame(width: 58, height: 40).background(Color.black, in: .rect(cornerRadius: 11))
                    ForEach(0..<3, id: \.self) { column in
                        let value: String? = grade != "Raw" ? nil
                            : column == 1 ? card.tcgMarketUSD.map(SaleReport.usd)
                            : column == 2 ? card.cardmarketEUR.map { String(format: "€%.2f", $0) } : nil
                        Text(value ?? "—").font(.system(size: 14, weight: value == nil ? .semibold : .heavy, design: .rounded))
                            .foregroundStyle(value == nil ? Color.black.opacity(0.25) : .black)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.black.opacity(0.08)) }
                    }
                }
            }
            Text("Graded prices appear here as soon as the market responds")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.45))
                .frame(maxWidth: .infinity).padding(.top, 4)
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


// MARK: - Imágenes de cartas con caché

/// Imagen de carta que carga al instante si ya se vio: memoria → disco → red.
struct CardImage: View {
    let url: URL?
    var placeholder = true
    /// Versión pequeña que se enseña al instante mientras llega la grande.
    var preview: URL?
    @State private var image: UIImage?

    private static let memory: NSCache<NSURL, UIImage> = { let c = NSCache<NSURL, UIImage>(); c.countLimit = 600; return c }()
    private static let folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("card-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private static func file(_ url: URL) -> URL {
        folder.appendingPathComponent(url.absoluteString.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_"))
    }

    init(url: URL?, placeholder: Bool = true, preview: URL? = nil) {
        self.url = url
        self.placeholder = placeholder
        self.preview = preview
        _image = State(initialValue: url.flatMap { Self.memory.object(forKey: $0 as NSURL) }
                       ?? preview.flatMap { Self.memory.object(forKey: $0 as NSURL) })
    }

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if placeholder { RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)) }
            else { Color.clear }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = Self.memory.object(forKey: url as NSURL) { image = hit; return }
            if let preview, image == nil { image = await Self.load(preview) }
            if let full = await Self.load(url) { image = full }
        }
    }

    static func load(_ url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        let path = file(url)
        if let data = try? Data(contentsOf: path), let image = UIImage(data: data) {
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        try? data.write(to: path, options: .atomic)
        return image
    }

    /// Baja por adelantado las imágenes de una lista (las siguientes cartas, las de la colección).
    static func prefetch(_ urls: [URL]) {
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls.prefix(60) { group.addTask { _ = await load(url) } }
            }
        }
    }
}
