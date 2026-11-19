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
            lastSale: 49,
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
        SellItem(kind: .card, title: card.name, brand: card.setName, subtitle: card.setName, imageURL: card.imageURL, marketPrice: card.tcgMarketUSD)
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

            if item.snapshot != nil {
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
    @State private var platform = "StockX"
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
    private var net: Double { PlatformFees.net(price: price, platform: platform) }

    // Referencias del mercado para la talla elegida (solo si hay datos reales).
    private var sellNow: Double? { item.snapshot?.bid(size) }
    private var lastSale: Double? { item.snapshot?.lastSale ?? item.marketPrice }
    private var lowestAsk: Double? { item.snapshot?.ask(size) }
    private var earnMore: Double? { lowestAsk.map { max(1, $0 - 1) } }

    var body: some View {
        VStack(spacing: 0) {
            header
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
                .padding(.horizontal, 16).padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(sellGray.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
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
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
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
                        Label(item.kind == .card ? "Grade" : "Size (US)", systemImage: item.kind == .card ? "checkmark.seal" : "ruler")
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
                Text("Where to sell").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                HStack(spacing: 10) {
                    ForEach(platforms, id: \.self) { name in
                        let on = platform == name
                        Button { platform = name } label: {
                            VStack(spacing: 6) {
                                StylizedMarketplaceLogo(brand: name).frame(width: 44, height: 16)
                                    .frame(width: 62, height: 62).background(.white, in: .circle)
                                    .overlay { Circle().strokeBorder(on ? Color.black : Color.black.opacity(0.1), lineWidth: on ? 2 : 1) }
                                Text(SaleReport.usd(PlatformFees.net(price: price, platform: name)))
                                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(on ? .black : .black.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Under each platform: what you keep after its fee.").font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.4))
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 22)).glassEffect(.regular, in: .rect(cornerRadius: 22))

            VStack(spacing: 0) {
                fact("Your sale price", SaleReport.usd(price))
                fact("\(platform) fee (\(PlatformFees.ratePercent(platform))%)", "−" + SaleReport.usd(max(0, price - net)))
                HStack {
                    Text("You keep").font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                    Spacer()
                    Text(SaleReport.usd(net)).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(sellGreen)
                }
                .padding(.top, 12)
            }
            .padding(16).background(.white, in: .rect(cornerRadius: 22)).glassEffect(.regular, in: .rect(cornerRadius: 22))

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
        VStack(spacing: 16) {
            Image("IconAnuncio").resizable().scaledToFit().frame(width: 170, height: 170).padding(.top, 40)
            Text("Listing ready").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            Text("\(item.title) is saved at \(SaleReport.usd(price)) for \(platform). It publishes with one tap once the \(platform) seller account is connected.")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(.black.opacity(0.6)).multilineTextAlignment(.center).padding(.horizontal, 20)
            Label("\(platform) seller account needed", systemImage: "link.badge.plus")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                .padding(.horizontal, 14).frame(height: 38).background(.white, in: .capsule).glassEffect(.regular, in: .capsule)
        }
        .frame(maxWidth: .infinity)
    }

    private var canContinue: Bool {
        switch step {
        case 0: return true
        case 1: return size != nil && price > 0
        case 2: return confirmCondition && confirmShipping
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
                let listing = MarketplaceListing(platform: platform, title: item.title, sku: item.subtitle, size: size ?? "", priceUSD: price,
                                                 condition: condition, imageURL: item.imageURL?.absoluteString)
                _ = await ListingPublisher.publish(listing)
                working = false
                withAnimation(.spring(duration: 0.45)) { step = 3 }
            }
        } label: {
            Group {
                if working { ProgressView().tint(.white) } else { Text(step == 0 ? "Next" : step == 1 ? "Review listing" : step == 2 ? "Submit listing" : "Done") }
            }
            .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(canContinue ? Color.black : Color.black.opacity(0.28), in: .capsule)
        }
        .buttonStyle(.plain).disabled(!canContinue || working)
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
        .background { LinearGradient(colors: [sellGray.opacity(0), sellGray], startPoint: .top, endPoint: .center).ignoresSafeArea(edges: .bottom) }
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
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { TopBarGlassButton(systemImage: "xmark") }.buttonStyle(.plain)
                Spacer()
                Text("Market data").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)

            Picker("", selection: $tab) {
                Text("Asks").tag(0); Text("Bids").tag(1); Text("Sales").tag(2)
            }
            .pickerStyle(.segmented).padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill("All sizes", on: size == nil) { size = nil }
                    ForEach(snapshot.sizes, id: \.self) { s in pill("US \(s)", on: size == s) { size = s } }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }

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
                            line(SaleReport.usd(row.price), "New · US \(row.size)", row.date ?? "")
                        }
                    }
                    Text("Sample market snapshot · \(snapshot.asOf). Prices do not include fees.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.4)).padding(.top, 8)
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .background(sellGray.ignoresSafeArea())
        .preferredColorScheme(.light)
        .swipeBackToDismiss()
    }

    private func pill(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(on ? .white : .black)
                .padding(.horizontal, 14).frame(height: 36)
                .background(on ? Color.black : Color.white, in: .capsule)
                .overlay { Capsule().strokeBorder(Color.black.opacity(on ? 0 : 0.1)) }
        }
        .buttonStyle(.plain)
    }

    private func line(_ price: String, _ detail: String, _ trailing: String) -> some View {
        HStack {
            Text(price).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            Text(detail).font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.55))
            Spacer()
            Text(trailing).font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.55))
        }
        .padding(.horizontal, 14).frame(height: 52)
        .background(.white, in: .rect(cornerRadius: 16))
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
