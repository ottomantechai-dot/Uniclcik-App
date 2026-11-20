import SwiftUI

// MARK: - Vender un producto
// Flujo de venta a pantalla completa, para zapatos y para cartas: estado → talla (o gradación) y
// precio, con la referencia del mercado → revisión con comisiones → anuncio. También la pantalla de
// datos del mercado (precios de venta, ofertas de compra y ventas recientes).

/// Foto de los datos de mercado de un producto.
struct MarketSnapshot {
    struct Row: Identifiable {
        let id = UUID()
        let price: Double
        let size: String
        var quantity = 1
        var date: String?
    }
    let asOf: String
    let sizes: [String]
    let lowestAsk: [String: Double]     // por talla
    let highestBid: [String: Double]    // por talla
    let lastSale: Double
    let asks: [Row]
    let sales: [Row]

    func ask(_ size: String?) -> Double? { size.flatMap { lowestAsk[$0] } ?? lowestAsk.values.min() }
    func bid(_ size: String?) -> Double? { size.flatMap { highestBid[$0] } ?? highestBid.values.max() }

    /// Único producto con datos de ejemplo: cifras reales tomadas de las capturas del mercado del 19 nov 2026.
    static func sample(for name: String) -> MarketSnapshot? {
        guard name.localizedCaseInsensitiveContains("Jordan 1 Low Green Toe") else { return nil }
        return MarketSnapshot(
            asOf: "Nov 19, 2026",
            sizes: ["3.5Y", "4Y", "4.5Y", "5Y", "5.5Y", "6Y", "6.5Y", "7Y"],
            lowestAsk: ["3.5Y": 57, "4Y": 88, "4.5Y": 69, "5Y": 49, "5.5Y": 75, "7Y": 77],
            highestBid: ["3.5Y": 20, "4Y": 31, "4.5Y": 22, "5Y": 21, "5.5Y": 28, "6Y": 67, "6.5Y": 60, "7Y": 51],
            lastSale: 74,
            asks: [Row(price: 49, size: "5Y"), Row(price: 57, size: "3.5Y"), Row(price: 61, size: "5Y"), Row(price: 62, size: "5Y"),
                   Row(price: 69, size: "4.5Y"), Row(price: 70, size: "4.5Y", quantity: 2), Row(price: 70, size: "5Y"),
                   Row(price: 75, size: "5Y", quantity: 2), Row(price: 75, size: "5.5Y"), Row(price: 75, size: "4.5Y"),
                   Row(price: 76, size: "4.5Y"), Row(price: 77, size: "7Y"), Row(price: 78, size: "7Y"),
                   Row(price: 80, size: "5.5Y", quantity: 2), Row(price: 85, size: "7Y"), Row(price: 86, size: "7Y"), Row(price: 88, size: "4Y"),
                   Row(price: 120, size: "3.5Y"), Row(price: 223, size: "3.5Y"), Row(price: 227, size: "3.5Y", quantity: 2), Row(price: 241, size: "3.5Y")],
            sales: [Row(price: 49, size: "3.5Y", date: "Nov 15, 2026"), Row(price: 50, size: "3.5Y", date: "Oct 3, 2026"),
                    Row(price: 71, size: "3.5Y", date: "Mar 27, 2026"), Row(price: 70, size: "3.5Y", date: "Nov 26, 2025"),
                    Row(price: 73, size: "3.5Y", date: "Oct 31, 2025"), Row(price: 68, size: "3.5Y", date: "Oct 5, 2025"),
                    Row(price: 75, size: "3.5Y", date: "Aug 13, 2025")]
        )
    }
}

/// Lo que se vende.
struct SellItem: Identifiable {
    enum Kind { case shoe, card }
    let id = UUID()
    var kind: Kind = .shoe
    let title: String
    let brand: String
    var subtitle = ""
    let imageURL: URL?
    /// Precio de mercado conocido (cartas: TCGplayer).
    var marketPrice: Double?
    var snapshot: MarketSnapshot?

    static func shoe(name: String, brand: String, imageURL: URL?) -> SellItem {
        SellItem(title: name.firstUppercased, brand: brand, imageURL: imageURL, snapshot: .sample(for: name))
    }
    static func card(_ card: PokemonCardData) -> SellItem {
        SellItem(kind: .card, title: card.name, brand: card.setName, subtitle: card.setName, imageURL: card.imageURL,
                 marketPrice: CardSample.find(card)?.market ?? card.tcgMarketUSD, snapshot: CardSample.find(card)?.snapshot)
    }
}

private let sellGray = Color(red: 0.965, green: 0.965, blue: 0.975)
private let sellGreen = Color(red: 0.13, green: 0.55, blue: 0.30)

// MARK: - Botón de entrada

/// «Sell this item»: abre el flujo de venta a pantalla completa.
struct SellButton: View {
    let item: SellItem
    @State private var open = false
    @State private var showMarket = false

    var body: some View {
        VStack(spacing: 10) {
            Button { open = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                    Text("Sell this item")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: 56)
                .background(.black, in: .capsule)
            }
            .buttonStyle(.plain)
            .tourTarget("sell.open")

            if item.snapshot != nil, item.kind == .shoe {
                Button { showMarket = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                        Text("Market data")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: 50)
                    .background(.white, in: .capsule)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .tourTarget("market.open")
            }
        }
        .fullScreenCover(isPresented: $open) { SellFlowView(item: item) }
        .fullScreenCover(isPresented: $showMarket) { if let snapshot = item.snapshot { MarketDataView(item: item, snapshot: snapshot) } }
    }
}

// MARK: - Flujo de venta

struct SellFlowView: View {
    let item: SellItem
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0                 // 0 estado · 1 talla y precio · 2 revisión · 3 resultado
    @State private var condition: MarketplaceListing.Condition = .new
    @State private var size: String?
    @State private var sizesOpen = true
    @State private var priceText = ""
    /// Plataformas donde se publica: se pueden marcar varias.
    @State private var selected: Set<String> = ["StockX"]
    @State private var confirmCondition = false
    @State private var confirmShipping = false
    @State private var working = false
    @FocusState private var priceFocused: Bool

    private var sizes: [String] {
        if item.kind == .card { return ["Raw", "PSA 8", "PSA 9", "PSA 10"] }
        return item.snapshot?.sizes ?? ["7", "7.5", "8", "8.5", "9", "9.5", "10", "10.5", "11", "11.5", "12", "13"]
    }
    private var platforms: [String] { item.kind == .card ? ["eBay", "StockX"] : ["StockX", "GOAT", "eBay"] }
    private var price: Double { Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var chosen: [String] { platforms.filter { selected.contains($0) } }

    // Referencias del mercado para la talla elegida (solo si hay datos reales).
    private var sellNow: Double? { item.snapshot?.bid(size) }
    private var lastSale: Double? { item.snapshot?.lastSale ?? item.marketPrice }
    private var lowestAsk: Double? { item.snapshot?.ask(size) }
    private var earnMore: Double? { lowestAsk.map { max(1, $0 - 1) } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                    if step < 3 { productCard }
                    switch step {
                    case 0: conditionStep
                    case 1: priceStep
                    case 2: reviewStep
                    default: doneStep
                    }
                }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(sellGray.ignoresSafeArea())
        .preferredColorScheme(.light)
        .swipeBackToDismiss()
    }

    private var header: some View {
        HStack {
            Button { if step == 0 || step == 3 { dismiss() } else { withAnimation(.snappy) { step -= 1 } } } label: {
                TopBarGlassButton(systemImage: step == 0 || step == 3 ? "xmark" : "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer()
            if step < 3 {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i <= step ? Color.black : Color.black.opacity(0.12)).frame(width: i == step ? 26 : 10, height: 6)
                    }
                }
                .padding(.horizontal, 14).frame(height: 30)
                .background(.white, in: .capsule).glassEffect(.regular, in: .capsule)
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 14)
        .background { SellEdgeFade(edge: .top) }
    }

    private var productCard: some View {
        HStack(spacing: 12) {
            Group {
                if item.kind == .card { CardImage(url: item.imageURL) } else {
                    StockCachedRemoteImage(url: item.imageURL, maxPixelSide: 320, fillFrame: false).blendMode(.multiply)
                }
            }
            .frame(width: 92, height: 70)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.black).lineLimit(2)
                HStack(spacing: 6) {
                    if item.kind == .shoe { BrandLogoLabel(brand: item.brand, compact: true).frame(width: 26, height: 26).background(Color.black.opacity(0.05), in: .circle) }
                    else { Text(item.subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.5)).lineLimit(1) }
                    if step > 0 { chip(condition.rawValue) }
                    if step > 1, let size { chip(item.kind == .card ? size : "US \(size)") }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.black.opacity(0.65)).lineLimit(1)
            .padding(.horizontal, 8).frame(height: 24).background(Color.black.opacity(0.06), in: .capsule)
    }

    // Paso 1: estado
    private var conditionStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select the condition").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.black).padding(.top, 6)
            ForEach(MarketplaceListing.Condition.allCases) { option in
                let on = condition == option
                Button { condition = option } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option == .new ? "checkmark.seal" : option == .newNoBox ? "shippingbox" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(on ? .white : .black)
                            .frame(width: 40, height: 40).background(on ? Color.black : Color.black.opacity(0.05), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.rawValue).font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                            Text(option == .new ? (item.kind == .card ? "Sealed or mint, never played." : "Unworn, with original box and accessories.")
                                 : option == .newNoBox ? (item.kind == .card ? "Mint, without sleeve or case." : "Unworn. Damaged box, no box or missing accessories.")
                                 : (item.kind == .card ? "Played, with visible wear." : "Worn, with or without box."))
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.5)).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(on ? .black : .black.opacity(0.2))
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: .rect(cornerRadius: 20))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(on ? Color.black : .clear, lineWidth: 1.5) }
                }
                .buttonStyle(.plain)
                .tourTarget(option == .new ? "sell.condition" : "")
            }
        }
    }

    // Paso 2: talla y precio
    private var priceStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Talla / gradación
            VStack(spacing: 0) {
                Button { withAnimation(.snappy(duration: 0.3)) { sizesOpen.toggle() } } label: {
                    HStack {
                        HStack(spacing: 8) {
                            if item.kind == .card { Image(systemName: "checkmark.seal") }
                            else { Image("IconTalla").renderingMode(.template).resizable().scaledToFit().frame(width: 22, height: 22) }
                            Text(item.kind == .card ? "Grade" : "Size (US)")
                        }
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.black)
                        Spacer()
                        Text(size.map { item.kind == .card ? $0 : "US \($0)" } ?? "Select").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.45))
                            .rotationEffect(.degrees(sizesOpen ? 180 : 0))
                    }
                    .padding(14).contentShape(.rect).background(.white)
                }
                .buttonStyle(.plain).zIndex(1)
                if sizesOpen {
                    Divider().padding(.horizontal, 14)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: item.kind == .card ? 2 : 3), spacing: 8) {
                        ForEach(sizes, id: \.self) { option in
                            let on = size == option
                            Button { size = option; withAnimation(.snappy(duration: 0.3)) { sizesOpen = false } } label: {
                                VStack(spacing: 2) {
                                    Text(item.kind == .card ? option : "US \(option)").font(.system(size: 14, weight: .bold, design: .rounded))
                                    // Mejor oferta de compra en esa talla, cuando hay datos.
                                    if let bid = item.snapshot?.highestBid[option] {
                                        Text(SaleReport.usd(bid)).font(.system(size: 12, weight: .semibold)).foregroundStyle(on ? .white.opacity(0.8) : sellGreen)
                                    }
                                }
                                .foregroundStyle(on ? .white : .black)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(on ? Color.black : Color.white, in: .rect(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(on ? 0 : 0.12)) }
                            }
                            .buttonStyle(.plain)
                            .tourTarget(option == sizes.dropFirst(3).first ? "sell.sizeOption" : "")
                        }
                    }
                    .padding(12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(.white).clipShape(.rect(cornerRadius: 20))
            .glassEffect(.regular, in: .rect(cornerRadius: 20))

            // Precio
            VStack(alignment: .leading, spacing: 12) {
                Text("Set your price").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("$").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.35))
                    TextField("0", text: $priceText).keyboardType(.decimalPad).focused($priceFocused)
                        .font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                    if priceFocused { Button("Done") { priceFocused = false }.font(.system(size: 15, weight: .bold)).foregroundStyle(.black) }
                }
                .padding(.horizontal, 14).frame(height: 68)
                .background(Color.black.opacity(0.04), in: .rect(cornerRadius: 16))

                if sellNow != nil || lastSale != nil || earnMore != nil {
                    HStack(spacing: 8) {
                        if let v = sellNow { suggestion("Sell now", v) }
                        if let v = lastSale { suggestion("Sell faster", v) }
                        if let v = earnMore { suggestion("Earn more", v) }
                    }
                    .tourTarget("sell.suggest")
                    PriceScale(low: sellNow ?? (lastSale ?? 0) * 0.6, mid: lastSale, high: lowestAsk ?? (lastSale ?? 0) * 1.4, value: price)
                    VStack(spacing: 0) {
                        if let v = lowestAsk { fact("Lowest ask", SaleReport.usd(v)) }
                        if let v = lastSale { fact(item.kind == .card && item.snapshot == nil ? "Market price (TCGplayer)" : "Last sale", SaleReport.usd(v)) }
                        if let v = sellNow { fact("Highest bid", SaleReport.usd(v), last: true) }
                    }
                    if let snapshot = item.snapshot {
                        Text("Sample market snapshot · \(snapshot.asOf)").font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.4))
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.xaxis").font(.system(size: 16, weight: .semibold)).foregroundStyle(.black.opacity(0.35))
                        Text("No market data for this item yet. Set the price you want.")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                    }
                    PriceScale(low: 0, mid: nil, high: 0, value: 0)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 22))
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }

    private func suggestion(_ title: String, _ value: Double) -> some View {
        let on = abs(price - value) < 0.5
        return Button { priceText = SaleReport.usd(value).replacingOccurrences(of: "$", with: ""); priceFocused = false } label: {
            VStack(spacing: 2) {
                Text(SaleReport.usd(value)).font(.system(size: 16, weight: .heavy, design: .rounded))
                Text(title).font(.system(size: 11, weight: .semibold)).opacity(0.75)
            }
            .foregroundStyle(on ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(on ? Color.black : Color.black.opacity(0.05), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func fact(_ title: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14)).foregroundStyle(.black.opacity(0.65))
                Spacer()
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.black)
            }
            .padding(.vertical, 10)
            if !last { Divider() }
        }
    }

    // Paso 3: revisión
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Where to sell").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                    Spacer()
                    Text(chosen.isEmpty ? "Pick at least one" : "\(chosen.count) selected")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.45))
                }
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(platforms, id: \.self) { name in
                            let on = selected.contains(name)
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { if on { selected.remove(name) } else { selected.insert(name) } }
                            } label: {
                                VStack(spacing: 8) {
                                    StylizedMarketplaceLogo(brand: name).frame(width: 46, height: 17)
                                        .frame(width: 68, height: 68)
                                        .background(.white, in: .circle)
                                        .glassEffect(.regular.interactive(), in: .circle)
                                        .padding(5)
                                        .overlay { Circle().strokeBorder(Color.black, lineWidth: 2.5).opacity(on ? 1 : 0) }
                                        .opacity(on ? 1 : 0.45)
                                        .scaleEffect(on ? 1 : 0.94)
                                    Text(SaleReport.usd(PlatformFees.net(price: price, platform: name)))
                                        .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(on ? .black : .black.opacity(0.4))
                                    Text("you keep").font(.system(size: 10, weight: .medium)).foregroundStyle(.black.opacity(0.4))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 22)).glassEffect(.regular, in: .rect(cornerRadius: 22))
            .tourTarget("sell.platforms")

            VStack(spacing: 0) {
                fact("Your sale price", SaleReport.usd(price), last: chosen.isEmpty)
                ForEach(Array(chosen.enumerated()), id: \.element) { index, name in
                    let net = PlatformFees.net(price: price, platform: name)
                    HStack(spacing: 10) {
                        StylizedMarketplaceLogo(brand: name).frame(width: 52, height: 15, alignment: .leading)
                        Text("fee \(PlatformFees.ratePercent(name))% · −\(SaleReport.usd(max(0, price - net)))")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                        Spacer()
                        Text(SaleReport.usd(net)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(sellGreen)
                    }
                    .padding(.vertical, 12)
                    if index < chosen.count - 1 { Divider() }
                }
            }
            .padding(16).background(.white, in: .rect(cornerRadius: 22)).glassEffect(.regular, in: .rect(cornerRadius: 22))
            .tourTarget("sell.fees")

            VStack(alignment: .leading, spacing: 12) {
                Text("Final checks").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                check($confirmCondition, "I described the condition accurately. If the buyer returns the item, I am responsible.")
                check($confirmShipping, "I will ship the item within two business days of the sale.")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 22)).glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }

    private func check(_ value: Binding<Bool>, _ text: String) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: value.wrappedValue ? "checkmark.square.fill" : "square").font(.system(size: 20)).foregroundStyle(.black)
                Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.65)).multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
    }

    // Resultado
    private var doneStep: some View {
        VStack(spacing: 18) {
            // Icono sobrio: una etiqueta en un círculo de cristal, con su marca de hecho.
            Image(systemName: "tag").font(.system(size: 44, weight: .semibold)).foregroundStyle(.black)
                .frame(width: 124, height: 124)
                .background(.white, in: .circle)
                .glassEffect(.regular, in: .circle)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(.black, in: .circle)
                        .overlay { Circle().strokeBorder(sellGray, lineWidth: 3) }
                }
                .padding(.top, 50)
            Text(chosen.count == 1 ? "Listing ready" : "\(chosen.count) listings ready").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            Text("\(item.title) is saved at \(SaleReport.usd(price)). Each listing publishes with one tap once that seller account is connected.")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(.black.opacity(0.6)).multilineTextAlignment(.center).padding(.horizontal, 20)
            VStack(spacing: 8) {
                ForEach(chosen, id: \.self) { name in
                    HStack(spacing: 10) {
                        StylizedMarketplaceLogo(brand: name).frame(width: 56, height: 16, alignment: .leading)
                        Spacer()
                        Label("Seller account needed", systemImage: "link").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.5))
                    }
                    .padding(.horizontal, 16).frame(height: 50)
                    .background(.white, in: .capsule).glassEffect(.regular, in: .capsule)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var canContinue: Bool {
        switch step {
        case 0: return true
        case 1: return size != nil && price > 0
        case 2: return confirmCondition && confirmShipping && !chosen.isEmpty
        default: return true
        }
    }

    private var footer: some View {
        Button {
            priceFocused = false
            if step == 3 { dismiss(); return }
            if step < 2 { withAnimation(.snappy) { step += 1 }; return }
            Task {
                working = true
                for name in chosen {
                    let listing = MarketplaceListing(platform: name, title: item.title, sku: item.subtitle, size: size ?? "", priceUSD: price,
                                                     condition: condition, imageURL: item.imageURL?.absoluteString)
                    _ = await ListingPublisher.publish(listing)
                }
                working = false
                withAnimation(.spring(duration: 0.45)) { step = 3 }
            }
        } label: {
            Group {
                if working { ProgressView().tint(.white) } else { Text(step == 0 ? "Next" : step == 1 ? "Review listing" : step == 2 ? (chosen.count > 1 ? "Submit \(chosen.count) listings" : "Submit listing") : "Done") }
            }
            .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(canContinue ? Color.black : Color.black.opacity(0.28), in: .capsule)
        }
        .buttonStyle(.plain).disabled(!canContinue || working)
        .tourTarget("sell.next")
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
        .background { SellEdgeFade(edge: .bottom) }
    }
}

/// Difuminado del borde: el contenido pasa por debajo de la cabecera (o del botón de abajo) y se
/// desvanece, en vez de cortarse contra una franja opaca.
struct SellEdgeFade: View {
    let edge: VerticalEdge
    var body: some View {
        let stops: [Gradient.Stop] = [.init(color: sellGray.opacity(0.96), location: 0), .init(color: sellGray.opacity(0.8), location: 0.55), .init(color: sellGray.opacity(0), location: 1)]
        LinearGradient(stops: stops, startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
            .padding(edge == .top ? .bottom : .top, -22)
            .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
            .allowsHitTesting(false)
    }
}

/// Escala de precios: de la mejor oferta de compra (verde, se vende ya) al precio más bajo en venta
/// (rojo, cuesta vender), con una marca en el precio escrito.
struct PriceScale: View {
    let low: Double
    let mid: Double?
    let high: Double
    let value: Double

    var body: some View {
        let hasData = high > low
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let t = hasData ? min(1, max(0, (value - low) / (high - low))) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(hasData
                        ? AnyShapeStyle(LinearGradient(colors: [sellGreen, Color(red: 0.55, green: 0.75, blue: 0.25), Color(red: 0.95, green: 0.75, blue: 0.15), Color(red: 0.90, green: 0.20, blue: 0.15)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.black.opacity(0.08)))
                        .frame(height: 8)
                    if hasData, value > 0 {
                        VStack(spacing: 2) {
                            Text(SaleReport.usd(value)).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 7).frame(height: 20).background(.black, in: .rect(cornerRadius: 6))
                            Rectangle().fill(.black).frame(width: 2, height: 16)
                        }
                        .offset(x: min(max(0, t * w - 22), w - 46), y: -14)
                    }
                }
                .frame(height: 8).frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 44)
            HStack {
                Text(hasData ? "Sells now · \(SaleReport.usd(low))" : "Sells now").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black.opacity(0.5))
                Spacer()
                Text(hasData ? "Lowest ask · \(SaleReport.usd(high))" : "Lowest ask").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black.opacity(0.5))
            }
        }
    }
}

// MARK: - Datos del mercado

struct MarketDataView: View {
    let item: SellItem
    let snapshot: MarketSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0          // 0 en venta · 1 ofertas de compra · 2 ventas
    @State private var size: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                switch tab {
                case 0:
                    ForEach(snapshot.asks.filter { size == nil || $0.size == size }) { row in
                        line(SaleReport.usd(row.price), "US \(row.size)", "Qty \(row.quantity)")
                    }
                case 1:
                    ForEach(snapshot.sizes.filter { size == nil || $0 == size }.compactMap { s in snapshot.highestBid[s].map { (s, $0) } }.sorted { $0.1 > $1.1 }, id: \.0) { s, bid in
                        line(SaleReport.usd(bid), "US \(s)", "Highest bid")
                    }
                default:
                    ForEach(snapshot.sales.filter { size == nil || $0.size == size }) { row in
                        line(SaleReport.usd(row.price), "US \(row.size)", row.date ?? "")
                    }
                }
                Text("Sample market snapshot · \(snapshot.asOf). Prices do not include fees.")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.4)).padding(.top, 8)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 60)
        }
        .safeAreaInset(edge: .top, spacing: 0) { top }
        .overlay(alignment: .bottom) { SellEdgeFade(edge: .bottom).frame(height: 70) }
        .background(sellGray.ignoresSafeArea())
        .preferredColorScheme(.light)
        .swipeBackToDismiss()
    }

    private var top: some View {
        VStack(spacing: 10) {
            HStack {
                Button { dismiss() } label: { TopBarGlassButton(systemImage: "xmark") }.buttonStyle(.plain).tourTarget("market.close")
                Spacer()
                Text("Market data").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Array(["Asks", "Bids", "Sales"].enumerated()), id: \.offset) { index, name in
                        Button { withAnimation(.snappy(duration: 0.2)) { tab = index } } label: {
                            Text(name).font(.system(size: 14, weight: .bold)).foregroundStyle(tab == index ? .white : .black)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(tab == index ? Color.black : Color.white, in: .capsule)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .tourTarget("market.tabs")
            .padding(.horizontal, 16)

            // Tallas: el icono deja claro qué se está filtrando.
            HStack(spacing: 8) {
                Image("IconTalla").renderingMode(.template).resizable().scaledToFit().foregroundStyle(.black)
                    .frame(width: 24, height: 24).frame(width: 40, height: 40)
                    .background(.white, in: .circle).glassEffect(.regular, in: .circle)
                    .accessibilityLabel("Sizes")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        pill("All", on: size == nil) { size = nil }
                        ForEach(snapshot.sizes, id: \.self) { s in pill("US \(s)", on: size == s) { size = s } }
                    }
                    .padding(.leading, 12).padding(.trailing, 24).padding(.vertical, 2)
                }
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 12)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                    }
                }
            }
            .tourTarget("market.sizes")
            .padding(.leading, 16)
        }
        .padding(.top, 4).padding(.bottom, 14)
        .background { SellEdgeFade(edge: .top) }
    }

    private func pill(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(on ? .white : .black)
                .padding(.horizontal, 14).frame(height: 38)
                .background(on ? Color.black : Color.white, in: .capsule)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func line(_ price: String, _ detail: String, _ trailing: String) -> some View {
        HStack(spacing: 10) {
            Text(price).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                .frame(minWidth: 48, alignment: .leading)
            HStack(spacing: 5) {
                Image("IconTalla").renderingMode(.template).resizable().scaledToFit().frame(width: 16, height: 16)
                Text(detail).font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.black.opacity(0.7))
            .padding(.horizontal, 9).frame(height: 28).background(Color.black.opacity(0.05), in: .capsule)
            Spacer()
            Text(trailing).font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.55))
        }
        .padding(.horizontal, 14).frame(height: 52)
        .background(.white, in: .rect(cornerRadius: 16))
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}


// MARK: - Zapato de ejemplo con todos sus datos

/// Anuncio de un par usado, con sus fotos.
struct UsedListing: Identifiable {
    let id = UUID()
    let size: String
    let price: Double
    let priceWithFees: Double
    let photos: [URL]
    let url: URL?
}

/// Ficha completa del zapato de ejemplo (Jordan 1 Low Green Toe GS, 553560-371). Todas las cifras se
/// leyeron de las páginas públicas de cada plataforma el 19 nov 2026; no hay nada estimado.
struct ShoeSample {
    var asOf = "Nov 19, 2026"
    var colorway = "Noble Green/White/Black/Pollen"
    var retail: Double? = 85.0
    var buyNow = 49.0
    var lastSale = 74.0
    var highestOffer = 67.0
    var sizes = ["3.5Y", "4Y", "4.5Y", "5Y", "5.5Y", "6Y", "6.5Y", "7Y"]
    var platforms = ["StockX", "GOAT", "eBay", "Flight Club"]
    /// Filas extra de «Product details».
    var details: [(icon: String, title: String, value: String)] = [
        (icon: "number", title: "Style", value: "553560-371"),
        (icon: "dollarsign.circle", title: "Retail price", value: "$85"),
        (icon: "calendar", title: "Release date", value: "Oct 12, 2021"),
    ]
    var hasSales = true
    /// talla → plataforma → precio más bajo en venta
    var asks: [String: [String: Double]] = [
        "3.5Y": ["StockX": 57, "GOAT": 98, "Flight Club": 98],
        "4Y": ["StockX": 88, "GOAT": 65, "eBay": 67, "Flight Club": 65],
        "4.5Y": ["StockX": 69, "GOAT": 45, "eBay": 139.49, "Flight Club": 45],
        "5Y": ["StockX": 49, "GOAT": 43, "eBay": 189.95, "Flight Club": 43],
        "5.5Y": ["StockX": 75, "GOAT": 92, "eBay": 120, "Flight Club": 92],
        "6Y": ["GOAT": 92, "eBay": 150, "Flight Club": 92],
        "6.5Y": ["GOAT": 109, "eBay": 120, "Flight Club": 111],
        "7Y": ["StockX": 77, "GOAT": 86, "eBay": 100, "Flight Club": 94],
    ]
    /// Datos históricos tal como los da StockX.
    var stats: [(String, String)] = [
        ("Price range · 12 months", "$20 – $158"),
        ("Price range · 3 months", "$29 – $145"),
        ("Volatility", "19%"),
        ("Number of sales · 3 months", "35"),
        ("Price premium · last sale", "−13%"),
        ("Average sale price · 3 months", "$73"),
    ]
    var used: [UsedListing] = {
        let base = "https://listing-images.stockx.com/users/9b8a22b4-8ef1-11ec-b819-124738b50e12/listings/75e79d5b-6909-4c22-b619-36037ca74ca8/"
        let photos = ["01a1cad1-d2ea-7136-b10f-2d7a77c11de3", "01a1cad1-d2ea-7637-9f71-4af1fb976e0a", "01a1cad1-d2ea-77ac-80d9-24c4492c821f", "01a1cad1-d2ea-78fa-a338-8a259a5ae7be"]
            .compactMap { URL(string: base + $0 + "?w=900") }
        return [UsedListing(size: "7Y", price: 78, priceWithFees: 82, photos: photos,
                            url: URL(string: "https://stockx.com/air-jordan-1-low-noble-green-gs/listings/75e79d5b-6909-4c22-b619-36037ca74ca8"))]
    }()

    static func find(_ name: String) -> ShoeSample? {
        if name.localizedCaseInsensitiveContains("Jordan 1 Low Green Toe") { return ShoeSample() }
        if name.localizedCaseInsensitiveContains("Polartec Face Mask Half Zip") {
            return apparel(color: "Hearts", buyNow: 209, lastSale: 287, offer: 260, release: "Nov 12, 2026",
                           range: "$172 – $388", volatility: "19%", sales: "80", premium: "0%", average: "$245")
        }
        if name.localizedCaseInsensitiveContains("Applique Flannel Backpack") {
            return apparel(color: "Red", buyNow: 248, lastSale: 248, offer: 235, release: "Nov 19, 2026",
                           range: "$200 – $402", volatility: "5%", sales: "113", premium: "0%", average: "$240")
        }
        return nil
    }

    /// Ropa y bolsos de ejemplo: datos leídos de su página de StockX (solo esa plataforma los vende).
    private static func apparel(color: String, buyNow: Double, lastSale: Double, offer: Double, release: String,
                                range: String, volatility: String, sales: String, premium: String, average: String) -> ShoeSample {
        var sample = ShoeSample()
        sample.colorway = color; sample.retail = nil
        sample.buyNow = buyNow; sample.lastSale = lastSale; sample.highestOffer = offer
        sample.sizes = []; sample.platforms = ["StockX"]
        sample.asks = ["All": ["StockX": buyNow]]
        sample.details = [(icon: "leaf", title: "Season", value: "FW26"), (icon: "calendar", title: "Release date", value: release)]
        sample.stats = [("Price range · 12 months", range), ("Price range · 3 months", range), ("Volatility", volatility),
                        ("Number of sales · 3 months", sales), ("Price premium · last sale", premium), ("Average sale price · 3 months", average)]
        sample.used = []; sample.hasSales = false
        return sample
    }

    func lowest(_ size: String?) -> (platform: String, price: Double)? {
        let pool: [(String, Double)] = size.map { (asks[$0] ?? [:]).map { ($0.key, $0.value) } } ?? asks.values.flatMap { $0.map { ($0.key, $0.value) } }
        return pool.min { $0.1 < $1.1 }.map { (platform: $0.0, price: $0.1) }
    }

    /// Ventas reales con fecha (talla 3.5Y), para la gráfica.
    var sales: [DailySalePoint] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d, yyyy"
        guard hasSales else { return [] }
        return (MarketSnapshot.sample(for: "Jordan 1 Low Green Toe")?.sales ?? [])
            .compactMap { row in row.date.flatMap(f.date(from:)).map { DailySalePoint(date: $0, avg: row.price, orders: 1) } }
            .sorted { $0.date < $1.date }
    }

    /// La misma comparativa que usa la tabla de precios por talla y plataforma.
    var comparison: MarketComparison? {
        guard !sizes.isEmpty else { return nil }
        func key(_ s: String) -> String { s.replacingOccurrences(of: "Y", with: "") }
        let names = platforms
        let quotes = names.map { name -> MarketPlatformQuote in
            var bySize: [String: Double] = [:]
            for (size, row) in asks { if let v = row[name] { bySize[key(size)] = v } }
            let values = Array(bySize.values)
            return MarketPlatformQuote(platform: name, color: .black, matchedTitle: "Jordan 1 Low Green Toe (GS)", matchedSKU: details.first?.value, productURL: nil,
                                       asksBySize: bySize, avg: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                                       lowestAsk: values.min(), highestAsk: values.max())
        }
        let rows = sizes.map { MarketSizeRow(size: key($0), asks: asks[$0] ?? [:]) }
        return MarketComparison(query: "Jordan 1 Low Green Toe (GS)", platforms: quotes, sizes: rows.map(\.size), rows: rows, fetchedAt: Date(), skuAligned: true)
    }
}

/// Precio del zapato de ejemplo: el más bajo para la talla elegida, las referencias del mercado y el
/// precio en cada plataforma.
struct ShoeSamplePriceCard: View {
    let sample: ShoeSample
    let size: String?

    var body: some View {
        let best = sample.lowest(size)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(size == nil ? "Buy now from" : "Buy now · US \(size ?? "")").font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                    Text(best.map { SaleReport.usd($0.price) } ?? "—").font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                }
                Spacer()
                if let best {
                    VStack(alignment: .trailing, spacing: 6) {
                        StylizedMarketplaceLogo(brand: best.platform).frame(width: 62, height: 18, alignment: .trailing)
                        if let retail = sample.retail {
                            let diff = retail - best.price
                            Text(diff >= 0 ? "\(SaleReport.usd(diff)) below retail" : "\(SaleReport.usd(-diff)) above retail")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(diff >= 0 ? sellGreen : .black.opacity(0.6))
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                stat("Last sale", sample.lastSale)
                stat("Highest offer", sample.highestOffer)
                if let retail = sample.retail { stat("Retail", retail) }
            }
            VStack(spacing: 0) {
                let names = sample.platforms
                ForEach(Array(names.enumerated()), id: \.element) { index, name in
                    let price = size.flatMap { sample.asks[$0]?[name] } ?? (size == nil ? sample.asks.values.compactMap { $0[name] }.min() : nil)
                    HStack {
                        StylizedMarketplaceLogo(brand: name).frame(width: 60, height: 17, alignment: .leading)
                        Spacer()
                        Text(price.map { (size == nil ? "from " : "") + SaleReport.usd($0) } ?? "No listing")
                            .font(.system(size: 15, weight: price == nil ? .medium : .heavy, design: .rounded))
                            .foregroundStyle(price == nil ? .black.opacity(0.35) : (best?.platform == name ? sellGreen : .black))
                    }
                    .padding(.vertical, 11)
                    if index < names.count - 1 { Divider() }
                }
            }
            Text("Prices read from each marketplace · \(sample.asOf)").font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.4))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 22)).glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(SaleReport.usd(value)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 54).background(Color.black.opacity(0.04), in: .rect(cornerRadius: 14))
    }
}

/// Fotos de un anuncio usado, a pantalla completa.
struct UsedListingView: View {
    let listing: UsedListing
    let title: String
    @State var page: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $page) {
                ForEach(Array(listing.photos.enumerated()), id: \.offset) { index, url in
                    StockCachedRemoteImage(url: url, maxPixelSide: 1200, fillFrame: false)
                        .clipShape(.rect(cornerRadius: 24)).padding(.horizontal, 16).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 6) {
                ForEach(listing.photos.indices, id: \.self) { i in
                    Capsule().fill(i == page ? Color.black : Color.black.opacity(0.15)).frame(width: i == page ? 22 : 8, height: 6)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                HStack {
                    HStack(spacing: 5) {
                        Image("IconTalla").renderingMode(.template).resizable().scaledToFit().frame(width: 16, height: 16)
                        Text("US \(listing.size) · Used").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.black.opacity(0.7)).padding(.horizontal, 9).frame(height: 28).background(Color.black.opacity(0.05), in: .capsule)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(SaleReport.usd(listing.price)).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        Text("\(SaleReport.usd(listing.priceWithFees)) incl. fees").font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                    }
                }
            }
            .padding(16).background(.white, in: .rect(cornerRadius: 22)).glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 16)
            if let url = listing.url {
                Button { openURL(url) } label: {
                    HStack { Text("View on"); StylizedMarketplaceLogo(brand: "StockX").frame(width: 60, height: 17).colorInvert().brightness(1) }
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56).background(.black, in: .capsule)
                }
                .buttonStyle(.plain).padding(.horizontal, 20).padding(.bottom, 8)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: { TopBarGlassButton(systemImage: "xmark") }.buttonStyle(.plain)
                Spacer()
                Text("Used listing").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
        }
        .background(sellGray.ignoresSafeArea())
        .preferredColorScheme(.light)
        .swipeBackToDismiss()
    }
}


// MARK: - Carta de ejemplo con todos sus datos

/// Ficha completa de la carta de ejemplo: Umbreon VMAX (Alternate Art Secret) 215/203, Evolving Skies.
/// Cifras leídas el 19 nov 2026 de TCGplayer (precio de mercado e historial semanal), Collectr
/// (sin gradar y gradadas) y eBay (anuncio más barato a la venta por gradación).
struct CardSample {
    let asOf = "Nov 19, 2026"
    let market = 2195.10
    let lastSale = 1998.99
    let changePercent = -6.77
    /// gradación → plataforma → precio
    let grades: [String: [String: Double]] = [
        "Raw": ["Collectr": 2211.14, "TCGplayer": 2195.10],
        "8": ["Collectr": 1752],
        "9": ["Collectr": 1920, "eBay": 2025],
        "10": ["Collectr": 3478, "eBay": 3550],
    ]
    let stats: [(String, String)] = [
        ("Market price", "$2,195.10"),
        ("Most recent sale", "$1,998.99"),
        ("High sale · 12 months", "$2,799.99"),
        ("Copies sold · 12 months", "117"),
        ("Volatility · 30 days", "Low"),
        ("Listings · sellers", "76 · 62"),
    ]
    /// Precio de mercado semanal de TCGplayer (fin de semana : precio : copias vendidas), nov 2025 → nov 2026.
    private let weekly = "11/23:2133:2 11/30:2006:4 12/7:1924:1 12/14:1924:0 12/21:1775:8 12/28:1784:0 1/4:1776:6 1/11:1791:3 1/18:1789:2 1/25:1789:0 2/1:1784:3 2/8:1730:0 2/15:1680:1 2/22:1679:6 3/1:1743:6 3/8:1743:4 3/15:1853:11 3/22:1878:1 3/29:1878:0 4/5:1888:1 4/12:1995:7 4/19:2031:2 4/26:2136:5 5/3:2160:2 5/10:2080:3 5/17:2094:0 5/24:1954:2 5/31:2261:1 6/7:2292:2 6/14:2206:1 6/21:2210:0 6/28:2242:2 7/5:2351:4 7/12:2321:5 7/19:2396:0 7/26:2319:2 8/2:2327:0 8/9:2244:2 8/16:2410:2 8/23:2310:2 8/30:2368:1 9/6:2300:0 9/13:2283:0 9/20:2214:0 9/27:2292:0 10/4:2264:3 10/11:2324:2 10/18:2298:2 10/25:2298:0 11/1:2324:3 11/8:2324:0 11/15:2195:3"

    /// La carta de ejemplo, lista para enseñarla la primera en el catálogo.
    static let card = PokemonCardData(id: "swsh7-215", name: "Umbreon VMAX", setName: "Evolving Skies", rarity: "Rare Secret",
                                      tcgMarketUSD: 2195.10, cardmarketEUR: nil, changePercent: -6.77,
                                      imageURL: URL(string: "https://images.pokemontcg.io/swsh7/215_hires.png"))

    static func find(_ card: PokemonCardData) -> CardSample? {
        card.id == "swsh7-215" || (card.name.localizedCaseInsensitiveContains("Umbreon VMAX") && card.id.hasSuffix("-215")) ? CardSample() : nil
    }

    var history: [DailySalePoint] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return weekly.split(separator: " ").compactMap { item in
            let parts = item.split(separator: ":"); let md = parts[0].split(separator: "/")
            guard parts.count == 3, md.count == 2, let m = Int(md[0]), let d = Int(md[1]), let price = Double(parts[1]) else { return nil }
            let year = m >= 11 && !(m == 11 && d < 20) ? 2025 : 2026
            return calendar.date(from: DateComponents(year: year, month: m, day: d)).map { DailySalePoint(date: $0, avg: price, orders: Int(parts[2]) ?? 0) }
        }
        .sorted { $0.date < $1.date }
    }

    /// Referencias para vender: lo más barato a la venta por gradación y la última venta.
    var snapshot: MarketSnapshot {
        MarketSnapshot(asOf: asOf, sizes: ["Raw", "PSA 8", "PSA 9", "PSA 10"],
                       lowestAsk: ["Raw": 2195.10, "PSA 8": 1752, "PSA 9": 1920, "PSA 10": 3478],
                       highestBid: [:], lastSale: lastSale, asks: [], sales: [])
    }
}
