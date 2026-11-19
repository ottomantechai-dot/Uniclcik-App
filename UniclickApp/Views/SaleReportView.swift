import SwiftUI

// MARK: - Informe de venta (pantalla)
// Se abre al escanear una caja, desde el comparador o desde una carta. Enseña cuánto queda en
// cada plataforma, recomienda dónde vender y deja preparar el anuncio.

struct SaleReportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SaleReportStore.shared
    @ObservedObject private var listings = ListingStore.shared

    @State var report: SaleReport
    /// Tallas disponibles (del comparador) para recalcular el informe por talla.
    var sizes: [String] = []
    var rebuild: ((String?, Double?) -> SaleReport)?

    @State private var costText = ""
    @State private var publishing: SaleReport.Line?
    @State private var saved = false
    @FocusState private var costFocused: Bool

    private let ink = Color.black
    private let green = Color(red: 0.13, green: 0.55, blue: 0.30)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if report.lines.isEmpty { emptyCard } else {
                        recommendationCard
                        platformsCard
                    }
                    costCard
                    if !sizes.isEmpty { sizeCard }
                    listingsCard
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.97))
            .navigationTitle("Informe de venta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: report.shareText) { Image(systemName: "square.and.arrow.up") }
                }
            }
            .fullScreenCover(item: $publishing) { line in
                PublishListingSheet(report: report, line: line)
            }
            .onAppear {
                if let cost = report.costUSD { costText = SaleReport.usd(cost).replacingOccurrences(of: "$", with: "") }
                guard !saved, !report.lines.isEmpty else { return }
                saved = true
                // Cada caja escaneada con informe regala un sobre de cartas.
                if store.save(report) { CardPackStore.shared.earnPack() }
            }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                if report.kind == .shoe {
                    Shoe360View(title: report.title, fallbackURL: report.imageURL.flatMap(URL.init(string:)))
                } else {
                    AsyncImage(url: report.imageURL.flatMap(URL.init(string:))) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else {
                            Image(systemName: "rectangle.portrait.on.rectangle.portrait").font(.system(size: 30)).foregroundStyle(ink.opacity(0.25))
                        }
                    }
                }
            }
            .frame(height: 200).frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white, in: .rect(cornerRadius: 24))

            VStack(spacing: 4) {
                Text(report.title).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(ink)
                    .multilineTextAlignment(.center).lineLimit(3)
                HStack(spacing: 8) {
                    if !report.sku.isEmpty { chip(report.kind == .card ? report.sku : "SKU \(report.sku)") }
                    if let size = report.size, !size.isEmpty { chip(report.kind == .card ? size : "Talla \(size)") }
                }
            }
        }
        .padding(.top, 8)
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.6))
            .padding(.horizontal, 10).frame(height: 26).background(Color.black.opacity(0.06), in: .capsule)
    }

    private var emptyCard: some View {
        card {
            Image("IconInforme").resizable().scaledToFit().frame(height: 120).frame(maxWidth: .infinity)
            Text("Sin precios confirmados").font(.system(size: 17, weight: .bold)).foregroundStyle(ink).frame(maxWidth: .infinity)
            Text("Ninguna plataforma ha dado precio para este producto ahora mismo, y aquí no se inventan cifras. Búscalo por su nombre o su código de estilo en el comparador.")
                .font(.system(size: 13)).foregroundStyle(ink.opacity(0.6)).multilineTextAlignment(.center)
        }
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DÓNDE VENDER").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.7))
            if let best = report.best {
                HStack(alignment: .firstTextBaseline) {
                    Text(best.platform).font(.system(size: 26, weight: .heavy, design: .rounded))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(SaleReport.usd(best.netUSD)).font(.system(size: 26, weight: .heavy, design: .rounded))
                        Text("te quedan").font(.system(size: 11, weight: .semibold)).opacity(0.7)
                    }
                }
            }
            Text(report.recommendation).font(.system(size: 13, weight: .medium)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(green, in: .rect(cornerRadius: 22))
    }

    private var platformsCard: some View {
        card {
            Text("Plataforma por plataforma").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
            ForEach(report.lines.sorted { $0.netUSD > $1.netUSD }) { line in
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Circle().fill(PlatformPrice.brandColor(for: line.platform)).frame(width: 10, height: 10)
                        Text(line.platform).font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                        if line.platform == report.best?.platform {
                            Text("MEJOR").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3).background(green, in: .capsule)
                        }
                        Spacer()
                        Text(SaleReport.usd(line.netUSD)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(ink)
                    }
                    HStack {
                        fact("Precio", SaleReport.usd(line.priceUSD))
                        fact("Comisión \(line.feePercent)%" + (line.feeFixedUSD > 0 ? " + \(SaleReport.usd(line.feeFixedUSD))" : ""), "−" + SaleReport.usd(line.feeUSD))
                        if let gain = report.profit(line) {
                            fact("Ganancia", (gain >= 0 ? "+" : "−") + SaleReport.usd(abs(gain)), color: gain >= 0 ? green : .red)
                        }
                        Spacer(minLength: 0)
                    }
                    Button { publishing = line } label: {
                        let done = listings.listings.contains { $0.platform == line.platform && $0.title == report.title && $0.sku == report.sku }
                        Label(done ? "Anuncio preparado · editar" : "Preparar anuncio en \(line.platform)", systemImage: done ? "checkmark.circle.fill" : "tag")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(done ? green : ink)
                            .background(Color.black.opacity(0.05), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                if line.id != report.lines.sorted(by: { $0.netUSD > $1.netUSD }).last?.id { Divider() }
            }
        }
    }

    private func fact(_ title: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.5))
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(color ?? ink)
        }
        .padding(.trailing, 14)
    }

    private var costCard: some View {
        card {
            Text("Lo que te costó").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
            HStack {
                Text("$").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(ink.opacity(0.4))
                TextField("0", text: $costText)
                    .keyboardType(.decimalPad).focused($costFocused)
                    .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(ink)
                Button("Calcular") { applyCost() }
                    .font(.system(size: 14, weight: .semibold)).buttonStyle(.borderedProminent).tint(ink)
            }
            Text("Con el coste, el informe te dice la ganancia real en cada plataforma.")
                .font(.system(size: 12)).foregroundStyle(ink.opacity(0.55))
        }
    }

    private var sizeCard: some View {
        card {
            Text("Talla").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sizes, id: \.self) { size in
                        let on = report.size == size
                        Button { regenerate(size: size) } label: {
                            Text(size).font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(on ? .white : ink)
                                .frame(minWidth: 44, minHeight: 38).padding(.horizontal, 4)
                                .background(on ? ink : Color.black.opacity(0.06), in: .rect(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var listingsCard: some View {
        let mine = listings.listings.filter { $0.title == report.title && $0.sku == report.sku }
        if !mine.isEmpty {
            card {
                Text("Anuncios de este producto").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                ForEach(mine) { listing in ListingRow(listing: listing) }
            }
        }
    }

    private var footnote: some View {
        Text((report.kind == .card ? "Precio de mercado real de TCGplayer; lo que te queda se calcula vendiendo a ese precio en cada plataforma. " : "Precios más bajos publicados ahora mismo en cada plataforma. ") + "Las comisiones son aproximadas y no incluyen envío.")
            .font(.system(size: 11)).foregroundStyle(ink.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: .rect(cornerRadius: 20))
    }

    private var typedCost: Double? {
        Double(costText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
    }

    private func applyCost() {
        costFocused = false
        report.costUSD = typedCost
        store.save(report)
    }

    private func regenerate(size: String) {
        guard let rebuild else { return }
        var next = rebuild(size, typedCost ?? report.costUSD)
        next.id = report.id
        next.createdAt = report.createdAt
        report = next
        store.save(report)
    }
}

// MARK: - Preparar anuncio (pantalla completa)

struct PublishListingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let report: SaleReport
    let line: SaleReport.Line

    @State private var priceText = ""
    @State private var size = ""
    @State private var condition: MarketplaceListing.Condition = .new
    @State private var outcome: ListingPublisher.Outcome?
    @State private var working = false
    @FocusState private var focused: Bool

    private var price: Double { Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var net: Double { PlatformFees.net(price: price, platform: line.platform) }
    private var brand: Color { PlatformPrice.brandColor(for: line.platform) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [brand.opacity(0.16), Color(red: 0.96, green: 0.96, blue: 0.98)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            if let outcome { done(outcome) } else { form }
        }
        .preferredColorScheme(.light)
        .onAppear {
            priceText = SaleReport.usd(line.priceUSD).replacingOccurrences(of: "$", with: "")
            size = report.size ?? ""
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button { dismiss() } label: { TopBarGlassButton(systemImage: "xmark") }.buttonStyle(.plain)
                    Spacer()
                    HStack(spacing: 7) {
                        Circle().fill(brand).frame(width: 9, height: 9)
                        Text("Anuncio en \(line.platform)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.black)
                    }
                    .padding(.horizontal, 14).frame(height: 44).glassEffect(.regular, in: .capsule)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }

                Group {
                    if report.kind == .shoe {
                        Shoe360View(title: report.title, fallbackURL: report.imageURL.flatMap(URL.init(string:)))
                    } else {
                        AsyncImage(url: report.imageURL.flatMap(URL.init(string:))) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() } else { Color.clear }
                        }
                    }
                }
                .frame(height: 220)

                VStack(spacing: 4) {
                    Text(report.title).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.black).multilineTextAlignment(.center)
                    if !report.sku.isEmpty {
                        Text(report.kind == .card ? report.sku : "SKU \(report.sku)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.5))
                    }
                }

                VStack(spacing: 2) {
                    Text("TU PRECIO").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black.opacity(0.45))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("$").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.35))
                        TextField("0", text: $priceText).keyboardType(.decimalPad).focused($focused)
                            .font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                            .multilineTextAlignment(.center).fixedSize()
                    }
                    Text(report.kind == .card ? "Precio de mercado ahora: \(SaleReport.usd(line.priceUSD))" : "Más bajo publicado ahora en \(line.platform): \(SaleReport.usd(line.priceUSD))")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                }
                .padding(.vertical, 16).frame(maxWidth: .infinity)
                .background(.white, in: .rect(cornerRadius: 24))

                HStack(spacing: 10) {
                    stat("Comisión \(line.feePercent)%", "−" + SaleReport.usd(max(0, price - net)), color: .black)
                    stat("Te quedan", SaleReport.usd(net), color: Color(red: 0.13, green: 0.55, blue: 0.30))
                    if let cost = report.costUSD {
                        let gain = net - cost
                        stat("Ganancia", (gain >= 0 ? "+" : "−") + SaleReport.usd(abs(gain)), color: gain >= 0 ? Color(red: 0.13, green: 0.55, blue: 0.30) : .red)
                    }
                }

                if report.kind == .shoe {
                    VStack(spacing: 0) {
                        HStack {
                            Label("Talla (US)", systemImage: "ruler").font(.system(size: 15, weight: .medium)).foregroundStyle(.black)
                            Spacer()
                            TextField("9.5", text: $size).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .font(.system(size: 16, weight: .bold, design: .rounded)).frame(width: 80)
                        }
                        .padding(.horizontal, 16).frame(height: 54)
                        Divider().padding(.leading, 16)
                        HStack {
                            Label("Estado", systemImage: "shippingbox").font(.system(size: 15, weight: .medium)).foregroundStyle(.black)
                            Spacer()
                            Picker("", selection: $condition) {
                                ForEach(MarketplaceListing.Condition.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .tint(.black)
                        }
                        .padding(.leading, 16).padding(.trailing, 6).frame(height: 54)
                    }
                    .background(.white, in: .rect(cornerRadius: 22))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await publish() } } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(.white) } else {
                        Image(systemName: "paperplane.fill")
                        Text("Publicar en \(line.platform)")
                    }
                }
                .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(price > 0 ? Color.black : Color.black.opacity(0.3), in: .capsule)
            }
            .buttonStyle(.plain).disabled(price <= 0 || working)
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    private func stat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.black.opacity(0.5))
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(.white, in: .rect(cornerRadius: 20))
    }

    /// Pantalla de resultado: publicado, o preparado a la espera de la cuenta de vendedor.
    private func done(_ outcome: ListingPublisher.Outcome) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image("IconAnuncio").resizable().scaledToFit().frame(width: 190, height: 190)
            Text(outcome == .published ? "¡Publicado en \(line.platform)!" : "Anuncio listo")
                .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            Text(outcome == .published
                 ? "Tu anuncio ya está a la venta por \(SaleReport.usd(price))."
                 : "Quedó guardado a \(SaleReport.usd(price)). En cuanto se conecte la cuenta de vendedor de \(line.platform), se publica con un toque.")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.center).padding(.horizontal, 34)
            if outcome != .published {
                Label("Falta la cuenta de vendedor de \(line.platform)", systemImage: "link.badge.plus")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 14).frame(height: 38).glassEffect(.regular, in: .capsule)
            }
            Spacer()
            Button { dismiss() } label: {
                Text("Entendido").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56).background(.black, in: .capsule)
            }
            .buttonStyle(.plain).padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    private func publish() async {
        focused = false
        working = true
        let listing = MarketplaceListing(platform: line.platform, title: report.title, sku: report.sku, size: size,
                                         priceUSD: price, condition: condition, imageURL: report.imageURL)
        let result = await ListingPublisher.publish(listing)
        working = false
        withAnimation(.spring(duration: 0.45)) { outcome = result }
    }
}

struct ListingRow: View {
    let listing: MarketplaceListing

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(PlatformPrice.brandColor(for: listing.platform)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(listing.platform + (listing.size.isEmpty ? "" : " · \(listing.size)"))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                Text(listing.status == .published ? "Publicado" : "Listo para publicar · falta la cuenta de vendedor")
                    .font(.system(size: 11)).foregroundStyle(listing.status == .published ? .green : .orange)
            }
            Spacer()
            Text(SaleReport.usd(listing.priceUSD)).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.black)
        }
    }
}

// MARK: - Historial de informes y anuncios

struct SaleReportsHistoryView: View {
    @ObservedObject private var store = SaleReportStore.shared
    @ObservedObject private var listings = ListingStore.shared
    @State private var open: SaleReport?

    var body: some View {
        List {
            if !listings.listings.isEmpty {
                Section("Anuncios preparados") {
                    ForEach(listings.listings) { listing in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(listing.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            ListingRow(listing: listing)
                        }
                    }
                    .onDelete { offsets in offsets.map { listings.listings[$0] }.forEach(listings.delete) }
                }
            }
            Section("Informes") {
                if store.reports.isEmpty {
                    Text("Escanea una caja y aquí se guarda su informe.").foregroundStyle(.secondary)
                }
                ForEach(store.reports) { report in
                    Button { open = report } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let best = report.best {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(SaleReport.usd(best.netUSD)).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.primary)
                                    Text(best.platform).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in offsets.map { store.reports[$0] }.forEach(store.delete) }
            }
        }
        .navigationTitle("Informes")
        .sheet(item: $open) { SaleReportView(report: $0) }
    }
}
