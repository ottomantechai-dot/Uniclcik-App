import SwiftUI

// MARK: - Ficha de una carta
// Mismo esquema que la ficha de un zapato: la carta, otras de su colección, sus datos, la
// comparativa de precios y más cartas recomendadas. Al tocar otra carta, cambia aquí mismo.

struct CardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State var card: PokemonCardData
    @State private var related: [PokemonCardData] = []
    @State private var report: SaleReport?
    @State private var checkedCardID: String?
    @State private var publicPrices: PublicCardPrices?
    /// Cartas de cada colección ya pedidas: al volver a una colección salen al instante.
    private static var relatedCache: [String: [PokemonCardData]] = [:]

    private let gray = Color(red: 0.965, green: 0.965, blue: 0.975)
    private var number: String { card.id.split(separator: "-").last.map { "#" + $0 } ?? "—" }
    private var quotes: PublicCardPrices? { checkedCardID == card.id ? publicPrices : nil }
    private let priceSources = ["PriceCharting", "TCGplayer", "eBay"]
    private static let saleDateFormat = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)
    private var setLogo: URL? { PokemonTCGClient.storedSets().first { $0.name == card.setName }?.logoURL }

    var body: some View {
        Group {   // se abre apilada, como la ficha de un zapato: entra por la derecha y se vuelve deslizando
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
                                        // Mismo contenedor que en la rejilla: carta, edición arriba y fuentes abajo.
                                        CardImage(url: other.thumbURL)
                                        .frame(width: 82, height: 114)
                                        .overlay(alignment: .bottomLeading) { CardSourceDots(size: 16).padding(2) }
                                        .padding(6)
                                        .background(Color.white, in: .rect(cornerRadius: 14))
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                                        .overlay(alignment: .topTrailing) { CardEditionBadge(card: other).scaleEffect(0.62, anchor: .topTrailing).padding(3) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollClipDisabled()   // las cartas llegan hasta el borde de la pantalla, sin corte
                        .padding(.top, 14)
                    }

                    priceCard.tourTarget("card.price").padding(.top, 16)

                    SellButton(item: .card(card)).padding(.top, 12)

                    gradeTable.tourTarget("card.grades").padding(.top, 18)

                    if let quotes {
                        let history = saleHistory(quotes)
                        if !history.isEmpty {
                            ShoeMarketHistoryCard(sales: history, source: "via PriceCharting", sourceBrand: "eBay")
                                .background(.white, in: .rect(cornerRadius: 24))
                                .padding(.top, 18)
                        }
                    }

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
                                            .overlay(alignment: .bottomLeading) { CardSourceDots(size: 20).padding(.leading, 2).padding(.bottom, 3) }
                                            Text(other.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black).lineLimit(1).frame(width: 118, alignment: .leading)
                                            Text(other.rarity)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        .padding(10)
                                        .background(.white, in: .rect(cornerRadius: 18))
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                                        .overlay(alignment: .topTrailing) { CardEditionBadge(card: other).padding(6) }
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
                .padding(.horizontal, 16).padding(.bottom, 120)   // aire para que el difuminado de abajo no tape las últimas cartas
                .id(card.id)
            }
            .background(Color(red: 0.965, green: 0.965, blue: 0.975).ignoresSafeArea())
            // Barra nativa, como en la ficha de un zapato: así el gesto de volver funciona igual que en la ficha de un zapato
            // y se ve la pantalla anterior por detrás al deslizar.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Arriba a la derecha, a la altura del botón de volver: la colección y dónde se compara.
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        CardImage(url: setLogo, placeholder: false).frame(width: 64, height: 24)
                        CardSourceDots(size: 24)
                    }
                    .padding(.horizontal, 6)
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
            .task(id: scenePhase == .active ? card.id : nil) {
                guard scenePhase == .active else { return }
                let id = card.id
                let collectorNumber = id.split(separator: "-").last.map(String.init) ?? ""
                let lookup = PublicPriceService.CardQuery(name: card.name, set: card.setName, number: collectorNumber)
                await PublicPriceService.poll {
                    let result = await PublicPriceService.card(lookup)
                    guard !Task.isCancelled else { return }
                    publicPrices = result
                    checkedCardID = id
                }
            }
            .fullScreenCover(item: $report) { SaleReportView(report: $0) }
        }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .tabBar)
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

    private var priceCard: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ungraded market estimate")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.55))
                Text(quotes?.estimates["Raw"].map(SaleReport.usd) ?? "—")
                    .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                if let quotes {
                    Link("PriceCharting · Checked \(quotes.checkedAt.formatted(date: .omitted, time: .shortened))", destination: quotes.url)
                        .font(.system(size: 11, weight: .medium))
                } else {
                    Text(checkedCardID == card.id ? "Public prices unavailable" : "Checking public prices…")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(.white, in: .rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func saleHistory(_ prices: PublicCardPrices) -> [DailySalePoint] {
        let groups = Dictionary(grouping: prices.sales.filter {
            $0.source == "eBay" && $0.grade == "Raw"
        }, by: \.date)
        return groups.map { day, sales in
            DailySalePoint(date: day, avg: sales.map(\.amount).reduce(0, +) / Double(sales.count), orders: sales.count)
        }.sorted { $0.date < $1.date }
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
                // Cada plataforma con su logo y su nombre completo. Solo empresas americanas.
                ForEach(priceSources, id: \.self) { name in
                    Group {
                        if name == "eBay" {
                            StylizedMarketplaceLogo(brand: "eBay").frame(height: 15)
                        } else {
                            HStack(spacing: 4) {
                                if name == "TCGplayer" {
                                    Image("LogoTCGplayer").resizable().scaledToFit().frame(width: 16, height: 16).clipShape(.rect(cornerRadius: 4))
                                }
                                Text(name).font(.system(size: 10, weight: .heavy)).foregroundStyle(.black).lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 38).background(Color.black.opacity(0.05), in: .rect(cornerRadius: 11))
                    .accessibilityLabel(name)
                }
            }
            ForEach(["Raw", "8", "9", "10"], id: \.self) { grade in
                HStack(spacing: 8) {
                    Group {
                        if grade == "Raw" { Text("RAW").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white) }
                        else { DotMatrixText(text: grade) }
                    }
                    .frame(width: 58, height: 40).background(Color.black, in: .rect(cornerRadius: 11))
                    ForEach(priceSources, id: \.self) { source in
                        gradeCell(source: source, grade: grade)
                    }
                }
            }
            Text("PriceCharting shows estimates. eBay and TCGplayer show sales recorded by PriceCharting.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.45))
                .frame(maxWidth: .infinity).padding(.top, 4)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func gradeCell(source: String, grade: String) -> some View {
        let sale = quotes?.latestSale(source: source, grade: grade)
        let value = source == "PriceCharting" ? quotes?.estimates[grade] : sale?.amount
        let cell = VStack(spacing: 2) {
            Text(value.map(SaleReport.usd) ?? "—")
                .font(.system(size: 14, weight: value == nil ? .semibold : .heavy, design: .rounded))
                .foregroundStyle(value == nil ? Color.black.opacity(0.25) : .black)
                .minimumScaleFactor(0.65).lineLimit(1)
            if let sale {
                Text(sale.date, format: Self.saleDateFormat)
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .background { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.black.opacity(0.08)) }

        return Group {
            if let url = sale?.url {
                Link(destination: url) { cell }.buttonStyle(.plain)
            } else {
                cell
            }
        }
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
            else if placeholder { Skeleton(corner: 8) }
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


/// Fuentes que se presentan en la tabla de precios de cartas.
struct CardSourceDots: View {
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(["PriceCharting", "TCGplayer", "eBay"].enumerated()), id: \.offset) { index, name in
                Group {
                    if name == "eBay" {
                        StylizedMarketplaceLogo(brand: "eBay").frame(width: size * 0.72, height: size * 0.34)
                    } else if name == "PriceCharting" {
                        Text("PC").font(.system(size: size * 0.33, weight: .heavy)).foregroundStyle(.black)
                    } else {
                        Image("Logo" + name).resizable().scaledToFill().frame(width: size * 0.68, height: size * 0.68).clipShape(.circle)
                    }
                }
                .frame(width: size, height: size)
                .background(.white, in: .circle)
                .overlay { Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5) }
                .zIndex(Double(index))
                .accessibilityLabel(name)
            }
        }
    }
}
