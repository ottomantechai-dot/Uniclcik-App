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
            .sheet(item: $publishing) { line in
                PublishListingSheet(report: report, line: line)
                    .presentationDetents([.medium, .large])
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
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: report.imageURL.flatMap(URL.init(string:))) { phase in
                if let image = phase.image { image.resizable().scaledToFit() } else {
                    Image(systemName: report.kind == .card ? "rectangle.portrait.on.rectangle.portrait" : "shoe.2")
                        .font(.system(size: 26)).foregroundStyle(ink.opacity(0.3))
                }
            }
            .frame(width: 86, height: 86)
            .background(Color.white, in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(report.title).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(ink).lineLimit(3)
                if !report.sku.isEmpty {
                    Text(report.kind == .card ? report.sku : "SKU \(report.sku)")
                        .font(.system(size: 12, weight: .semibold, design: report.kind == .card ? .rounded : .monospaced))
                        .foregroundStyle(ink.opacity(0.55))
                }
                if let size = report.size, !size.isEmpty {
                    Text(report.kind == .card ? size : "Talla \(size)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var emptyCard: some View {
        card {
            Label("Sin precios de mercado", systemImage: "exclamationmark.magnifyingglass")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
            Text("No encontramos precios para este código. Prueba a buscarlo por nombre o por su código de estilo en el comparador.")
                .font(.system(size: 13)).foregroundStyle(ink.opacity(0.6))
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
        Text((report.priceIsEstimate ? "Precio estimado de mercado. " : "Precios de venta más bajos publicados ahora mismo. ") + "Las comisiones son aproximadas y no incluyen envío.")
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

// MARK: - Preparar anuncio

struct PublishListingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let report: SaleReport
    let line: SaleReport.Line

    @State private var priceText = ""
    @State private var size = ""
    @State private var condition: MarketplaceListing.Condition = .new
    @State private var message: String?
    @State private var working = false

    private var price: Double { Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Producto", value: report.title)
                    if !report.sku.isEmpty { LabeledContent(report.kind == .card ? "Colección" : "SKU", value: report.sku) }
                    if report.kind == .shoe { TextField("Talla (US)", text: $size) }
                    if report.kind == .shoe {
                        Picker("Estado", selection: $condition) {
                            ForEach(MarketplaceListing.Condition.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                } header: { Text("Anuncio en \(line.platform)") }

                Section {
                    HStack {
                        Text("Precio")
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                        TextField("0", text: $priceText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    LabeledContent("Comisión de \(line.platform)", value: "−" + SaleReport.usd(max(0, price - PlatformFees.net(price: price, platform: line.platform))))
                    LabeledContent("Te quedan") {
                        Text(SaleReport.usd(PlatformFees.net(price: price, platform: line.platform))).fontWeight(.bold)
                    }
                    if let cost = report.costUSD {
                        let gain = PlatformFees.net(price: price, platform: line.platform) - cost
                        LabeledContent("Ganancia") {
                            Text((gain >= 0 ? "+" : "−") + SaleReport.usd(abs(gain))).fontWeight(.bold).foregroundStyle(gain >= 0 ? .green : .red)
                        }
                    }
                } footer: {
                    Text("El precio más bajo publicado ahora en \(line.platform) es \(SaleReport.usd(line.priceUSD)).")
                }

                if let message {
                    Section { Label(message, systemImage: "info.circle").font(.footnote) }
                }

                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack { Spacer(); if working { ProgressView() } else { Text("Publicar en \(line.platform)").fontWeight(.semibold) }; Spacer() }
                    }
                    .disabled(price <= 0 || working)
                }
            }
            .navigationTitle("Preparar anuncio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .onAppear {
                priceText = SaleReport.usd(line.priceUSD).replacingOccurrences(of: "$", with: "")
                size = report.kind == .shoe ? (report.size ?? "") : (report.size ?? "")
            }
        }
    }

    private func publish() async {
        working = true
        let listing = MarketplaceListing(platform: line.platform, title: report.title, sku: report.sku, size: size,
                                         priceUSD: price, condition: condition, imageURL: report.imageURL)
        let outcome = await ListingPublisher.publish(listing)
        working = false
        switch outcome {
        case .published: dismiss()
        case .needsSellerAccount(let text): message = text
        }
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
