import SwiftUI

// MARK: - Sección de cartas
// Dos partes: «Mercado» (cartas coleccionables reales con su precio, para sacar el informe y
// preparar el anuncio) y «Sobres» (el juego de abrir sobres con las cartas propias de Uniclick).

struct CardsHubView: View {
    enum Mode: String, CaseIterable { case packs = "Sobres", market = "Mercado" }
    @State private var mode: Mode = .packs
    @State private var chromeHidden = false
    @StateObject private var market = CardsMarketModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            switch mode {
            case .packs: CardPacksView(chromeHidden: $chromeHidden)
            case .market: CardsMarketView(chromeHidden: $chromeHidden, market: market)
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.97).ignoresSafeArea())
        .overlay(alignment: .top) { chrome }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: mode) { _, _ in chromeHidden = false }
        .sheet(isPresented: $market.showFilter) { CardSetFilterSheet(market: market) }
        .preferredColorScheme(.light)
    }

    /// Barra flotante: las cartas pasan por detrás y el selector se esconde al bajar.
    private var chrome: some View {
        VStack(spacing: 8) {
            AppTopBar(title: "Cartas") {
                Button {
                    mode = .market
                    withAnimation(.snappy(duration: 0.28)) { market.searchOpen.toggle() }
                    searchFocused = market.searchOpen
                    if !market.searchOpen, !market.query.isEmpty { market.query = ""; market.reloadToken += 1 }
                } label: { TopBarGlassButton(systemImage: market.searchOpen ? "xmark" : "magnifyingglass") }
                    .buttonStyle(.plain).accessibilityLabel("Buscar cartas")
                Button {
                    mode = .market
                    market.showFilter = true
                } label: { TopBarGlassButton(systemImage: "line.3.horizontal.decrease") }
                    .buttonStyle(.plain).accessibilityLabel("Filtrar por colección")
            }
            if market.searchOpen {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar una carta por nombre", text: $market.query)
                        .submitLabel(.search).autocorrectionDisabled().focused($searchFocused)
                        .onSubmit { market.reloadToken += 1 }
                }
                .padding(.horizontal, 14).frame(height: 46)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !chromeHidden {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.bottom, 10)
        .background {
            LinearGradient(colors: [Color(red: 0.96, green: 0.96, blue: 0.97), Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.9), Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Lo que comparten la barra de arriba y el mercado de cartas: búsqueda, colección elegida y filtro.
@MainActor
final class CardsMarketModel: ObservableObject {
    @Published var query = ""
    @Published var searchOpen = false
    @Published var showFilter = false
    @Published var sets: [PokemonSetData] = []
    @Published var selectedSet: PokemonSetData?
    /// Sube cada vez que hay que volver a pedir las cartas.
    @Published var reloadToken = 0

    func choose(_ set: PokemonSetData?) {
        selectedSet = set
        reloadToken += 1
    }
}

/// Todas las colecciones, ordenadas por serie, con su logo y su nombre.
struct CardSetFilterSheet: View {
    @ObservedObject var market: CardsMarketModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var groups: [(series: String, sets: [PokemonSetData])] {
        let shown = text.isEmpty ? market.sets : market.sets.filter { $0.name.localizedCaseInsensitiveContains(text) || $0.series.localizedCaseInsensitiveContains(text) }
        var order: [String] = []
        var bySeries: [String: [PokemonSetData]] = [:]
        for set in shown {
            let key = set.series.isEmpty ? "Otras" : set.series
            if bySeries[key] == nil { order.append(key) }
            bySeries[key, default: []].append(set)
        }
        return order.map { ($0, bySeries[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button { market.choose(nil); dismiss() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.grid.2x2.fill").font(.system(size: 18, weight: .semibold)).frame(width: 84, height: 36)
                        Text("Todas las cartas").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if market.selectedSet == nil { Image(systemName: "checkmark").fontWeight(.bold) }
                    }
                    .foregroundStyle(.primary)
                }
                ForEach(groups, id: \.series) { group in
                    Section(group.series) {
                        ForEach(group.sets) { set in
                            Button { market.choose(set); dismiss() } label: {
                                HStack(spacing: 14) {
                                    AsyncImage(url: set.logoURL) { phase in
                                        if let image = phase.image { image.resizable().scaledToFit() } else { Color.clear }
                                    }
                                    .frame(width: 84, height: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(set.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                                        Text("\(set.total) cartas · \(set.year)").font(.system(size: 12)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if market.selectedSet?.id == set.id { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.primary) }
                                }
                            }
                        }
                    }
                }
                if market.sets.isEmpty {
                    Text("Cargando colecciones…").foregroundStyle(.secondary)
                }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar colección")
            .navigationTitle("Colecciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .task { if market.sets.isEmpty { market.sets = await PokemonTCGClient.fetchSets() } }
        }
    }
}

/// Esconde la parte de arriba al bajar por la lista y la devuelve al subir.
struct HidesChromeOnScroll: ViewModifier {
    @Binding var hidden: Bool

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, new in
            if new < 30 { if hidden { withAnimation(.snappy(duration: 0.28)) { hidden = false } } }
            else if new - old > 6, !hidden { withAnimation(.snappy(duration: 0.28)) { hidden = true } }
            else if old - new > 6, hidden { withAnimation(.snappy(duration: 0.28)) { hidden = false } }
        }
    }
}

// MARK: - Mercado de cartas reales

struct CardsMarketView: View {
    @Binding var chromeHidden: Bool
    @ObservedObject var market: CardsMarketModel
    private var query: String { market.query }
    private var sets: [PokemonSetData] { market.sets }
    private var selectedSet: PokemonSetData? { market.selectedSet }
    @State private var cards: [PokemonCardData] = []
    @State private var page = 0
    @State private var reachedEnd = false
    @State private var loading = false
    @State private var report: SaleReport?
    @State private var loadToken = 0
    @State private var failed = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// Lo que se pide al catálogo: nombre buscado, colección elegida, o todas las cartas.
    private var catalogQuery: String {
        var parts: [String] = []
        let name = query.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { parts.append("name:\"\(name)*\"") }
        if let selectedSet { parts.append("set.id:\(selectedSet.id)") }
        return parts.isEmpty ? "supertype:pokemon" : parts.joined(separator: " ")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Color.clear.frame(height: market.searchOpen ? 150 : 96)

                if !sets.isEmpty { setsStrip }

                HStack {
                    Text(selectedSet?.name ?? (query.isEmpty ? "Todas las cartas" : "Resultados"))
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                    Spacer()
                    if let selectedSet { Text("\(selectedSet.total) cartas · \(selectedSet.year)").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        Button { report = SaleReport.from(card: card) } label: { tile(card) }
                            .buttonStyle(.plain)
                            .onAppear { if card.id == cards.last?.id { Task { await loadMore() } } }
                    }
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if failed {
                    VStack(spacing: 10) {
                        Text("El catálogo de cartas no respondió.").font(.system(size: 14)).foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await loadMore() } }
                            .font(.system(size: 14, weight: .semibold)).buttonStyle(.borderedProminent).tint(.black)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if cards.isEmpty {
                    Text("No encontramos cartas con ese nombre.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .modifier(HidesChromeOnScroll(hidden: $chromeHidden))
        .task {
            if cards.isEmpty { await reload() }
            if market.sets.isEmpty { market.sets = await PokemonTCGClient.fetchSets() }
        }
        .onChange(of: market.reloadToken) { _, _ in Task { await reload() } }
        .sheet(item: $report) { SaleReportView(report: $0) }
    }

    private var setsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 10) {
                LazyHStack(spacing: 10) {
                    setChip(nil)
                    ForEach(sets) { setChip($0) }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }

    /// Ficha de cristal con solo el logo de la colección (el nombre sale debajo, en el título de la lista).
    private func setChip(_ set: PokemonSetData?) -> some View {
        let on = selectedSet?.id == set?.id
        return Button {
            market.choose(set)
        } label: {
            let blue = Color(red: 0.16, green: 0.44, blue: 0.98)
            if let set {
                AsyncImage(url: set.logoURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else {
                        Text(set.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).lineLimit(2).multilineTextAlignment(.center)
                    }
                }
                .frame(width: 78, height: 32)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(on ? .regular.tint(blue.opacity(0.28)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(on ? blue : .clear, lineWidth: 2) }
            } else {
                // «Todas»: un círculo pequeño, del tamaño del icono.
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .glassEffect(on ? .regular.tint(blue.opacity(0.28)).interactive() : .regular.interactive(), in: .circle)
                    .overlay { Circle().strokeBorder(on ? blue : .clear, lineWidth: 2) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(set?.name ?? "Todas las cartas")
    }

    private func tile(_ card: PokemonCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: card.thumbURL) { phase in
                if let image = phase.image { image.resizable().scaledToFit() } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06))
                }
            }
            .aspectRatio(0.72, contentMode: .fit)
            .frame(maxWidth: .infinity)
            Text(card.name).font(.system(size: 14, weight: .bold)).foregroundStyle(.black).lineLimit(1)
            Text(card.setName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Text(card.tcgMarketUSD.map(SaleReport.usd) ?? "Sin precio")
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(card.tcgMarketUSD == nil ? Color.secondary : .black)
                Spacer()
                if card.changePercent != 0 {
                    Text(String(format: "%+.0f%%", card.changePercent))
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(card.changePercent >= 0 ? .green : .red)
                }
            }
        }
        .padding(10)
        .background(Color.white, in: .rect(cornerRadius: 16))
    }

    private func reload() async {
        loadToken += 1
        cards = []
        page = 0
        reachedEnd = false
        failed = false
        await loadMore()
    }

    private func loadMore() async {
        guard !loading, !reachedEnd else { return }
        loading = true
        let token = loadToken
        let result = await PokemonTCGClient.fetchPage(query: catalogQuery, page: page + 1)
        loading = false
        guard token == loadToken else { await loadMore(); return }
        guard let next = result else { failed = true; return }
        failed = false
        page += 1
        if next.count < 30 { reachedEnd = true }
        let known = Set(cards.map(\.id))
        cards += next.filter { !known.contains($0.id) }
    }
}

// MARK: - Sobres

struct CardPacksView: View {
    @Binding var chromeHidden: Bool
    @ObservedObject private var store = CardPackStore.shared
    @State private var opened: [UniCard]?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: 96)
                packCard
                collection
            }
            .padding(16)
        }
        .modifier(HidesChromeOnScroll(hidden: $chromeHidden))
        .fullScreenCover(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened { PackOpeningView(cards: opened) { self.opened = nil } }
        }
    }

    private var packCard: some View {
        VStack(spacing: 14) {
            PackArt().frame(height: 250)
                .shadow(color: Color(red: 0.42, green: 0.20, blue: 0.95).opacity(0.35), radius: 22, y: 12)
            Text(store.packs == 1 ? "Tienes 1 sobre" : "Tienes \(store.packs) sobres")
                .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            Text("Cada sobre trae \(CardPackStore.packSize) cartas y la última es rara o mejor. Ganas un sobre al día y otro por cada caja que escaneas.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                let cards = store.openPack()
                if !cards.isEmpty { opened = cards }
            } label: {
                Text("Abrir un sobre").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(store.packs > 0 ? Color.black : Color.black.opacity(0.25), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain).disabled(store.packs == 0)
            if store.canClaimDaily {
                Button { store.claimDaily() } label: {
                    Label("Recoger el sobre de hoy", systemImage: "gift.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color.black.opacity(0.06), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color.white, in: .rect(cornerRadius: 24))
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tu colección").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                Spacer()
                Text("\(store.uniqueOwned) de \(UniCard.all.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(UniCard.all.sorted { $0.rarity > $1.rarity }) { card in
                    let count = store.owned[card.id] ?? 0
                    UniCardFace(card: card, compact: true)
                        .aspectRatio(0.72, contentMode: .fit)
                        .saturation(count > 0 ? 1 : 0).opacity(count > 0 ? 1 : 0.28)
                        .overlay(alignment: .topTrailing) {
                            if count > 1 {
                                Text("×\(count)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2).background(.black, in: .capsule).padding(5)
                            }
                        }
                }
            }
        }
        .padding(16)
        .background(Color.white, in: .rect(cornerRadius: 24))
    }
}

/// El sobre cerrado (arte propio de Uniclick).
struct PackArt: View {
    static let ratio: CGFloat = 688.0 / 1024.0
    var body: some View {
        Image("PackFront").resizable().scaledToFill()
            .aspectRatio(Self.ratio, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10))
    }
}

/// El reverso de las cartas.
struct CardBackArt: View {
    var body: some View {
        GeometryReader { geo in
            Image("CardBack").resizable().scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(.rect(cornerRadius: geo.size.width * 0.09))
        }
    }
}

/// La cara de una carta de Uniclick.
struct UniCardFace: View {
    let card: UniCard
    var compact = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            VStack(spacing: w * 0.05) {
                Text(card.rarity.name.uppercased()).font(.system(size: w * 0.075, weight: .heavy)).tracking(1).opacity(0.85)
                Spacer(minLength: 0)
                Image(systemName: card.symbol).font(.system(size: w * 0.34, weight: .bold))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                Spacer(minLength: 0)
                Text(card.name).font(.system(size: w * 0.105, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                if !compact {
                    Text(card.text).font(.system(size: w * 0.062, weight: .medium))
                        .multilineTextAlignment(.center).opacity(0.85).lineLimit(3)
                }
            }
            .foregroundStyle(.white)
            .padding(w * 0.08)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(LinearGradient(colors: card.rarity.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { RoundedRectangle(cornerRadius: w * 0.09).strokeBorder(.white.opacity(0.35), lineWidth: max(1, w * 0.015)) }
            .clipShape(.rect(cornerRadius: w * 0.09))
        }
    }
}

// MARK: - Abrir un sobre

struct PackOpeningView: View {
    let cards: [UniCard]
    var onDone: () -> Void

    @State private var stage = 0          // 0 sobre cerrado · 1 abriéndose · 2 cartas
    @State private var shake = false
    @State private var index = 0
    @State private var flipped: Set<Int> = []

    private var allSeen: Bool { flipped.count == cards.count }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12), Color(red: 0.12, green: 0.08, blue: 0.24)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if stage < 2 { pack } else { reveal }
        }
        .preferredColorScheme(.dark)
    }

    private var pack: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                // Destello que sale del sobre al rasgarlo.
                Circle().fill(.white).frame(width: 60, height: 60).blur(radius: 40)
                    .scaleEffect(stage == 1 ? 14 : 0.1).opacity(stage == 1 ? 0.95 : 0)
                // Cuerpo del sobre.
                PackArt().frame(height: 380)
                    .mask(alignment: .bottom) { Rectangle().frame(height: 380 * 0.88) }
                    .offset(y: stage == 1 ? 60 : 0).opacity(stage == 1 ? 0 : 1)
                // La tira de arriba, que se arranca.
                PackArt().frame(height: 380)
                    .mask(alignment: .top) { Rectangle().frame(height: 380 * 0.12) }
                    .rotationEffect(.degrees(stage == 1 ? 28 : 0), anchor: .topTrailing)
                    .offset(x: stage == 1 ? 150 : 0, y: stage == 1 ? -140 : 0)
                    .opacity(stage == 1 ? 0 : 1)
            }
            .rotationEffect(.degrees(stage == 0 ? (shake ? 2.5 : -2.5) : 0))
            .shadow(color: Color(red: 0.42, green: 0.20, blue: 0.95).opacity(0.7), radius: 40)
            .onAppear { withAnimation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true)) { shake = true } }
            .onTapGesture { open() }
            Text("Toca el sobre para abrirlo").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                .opacity(stage == 0 ? 1 : 0)
            Spacer()
        }
    }

    private func open() {
        guard stage == 0 else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.easeIn(duration: 0.55)) { stage = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.5)) { stage = 2 }
        }
    }

    private var reveal: some View {
        VStack(spacing: 18) {
            Text("Carta \(index + 1) de \(cards.count)").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                .padding(.top, 24)
            TabView(selection: $index) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                    FlipCard(card: card, shown: flipped.contains(i)) {
                        guard !flipped.contains(i) else { return }
                        UIImpactFeedbackGenerator(style: card.rarity >= .epic ? .heavy : .light).impactOccurred()
                        withAnimation(.spring(duration: 0.6)) { _ = flipped.insert(i) }
                    }
                    .padding(.horizontal, 54).padding(.vertical, 20)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Text(flipped.contains(index) ? "Carta \(cards[index].rarity.name.lowercased())" : "Toca la carta para girarla")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center).padding(.horizontal, 30).frame(height: 40)

            Button {
                if allSeen { onDone() } else if flipped.contains(index), index < cards.count - 1 {
                    withAnimation { index += 1 }
                } else {
                    withAnimation(.spring(duration: 0.6)) { _ = flipped.insert(index) }
                }
            } label: {
                Text(allSeen ? "Guardar en mi colección" : flipped.contains(index) ? "Siguiente" : "Girar")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(.white, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 20)
        }
    }
}

/// Carta que se gira: reverso con el dibujo del sobre, anverso con la carta y un brillo según su rareza.
private struct FlipCard: View {
    let card: UniCard
    let shown: Bool
    var onTap: () -> Void

    var body: some View {
        ZStack {
            UniCardFace(card: card)
                .opacity(shown ? 1 : 0)
                .rotation3DEffect(.degrees(shown ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            CardBackArt()
                .opacity(shown ? 0 : 1)
                .rotation3DEffect(.degrees(shown ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .aspectRatio(0.72, contentMode: .fit)
        .shadow(color: shown ? card.rarity.colors[0].opacity(card.rarity >= .rare ? 0.9 : 0.3) : .clear, radius: card.rarity >= .epic ? 26 : 16)
        .scaleEffect(shown && card.rarity >= .epic ? 1.04 : 1)
        .onTapGesture(perform: onTap)
    }
}
