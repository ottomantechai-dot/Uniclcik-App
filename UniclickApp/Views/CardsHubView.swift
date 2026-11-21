import SwiftUI

// MARK: - Sección de cartas
// Dos partes: «Mercado» (cartas coleccionables reales con su precio, para sacar el informe y
// preparar el anuncio) y «Sobres» (el juego de abrir sobres con las cartas propias de Uniclick).

struct CardsHubView: View {
    @State private var chromeHidden = false
    @StateObject private var market = CardsMarketModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        CardsMarketView(chromeHidden: $chromeHidden, market: market)
            .background(Color(red: 0.96, green: 0.96, blue: 0.97).ignoresSafeArea())
            .overlay(alignment: .top) { chrome }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $market.showFilter) { CardSetFilterSheet(market: market) }
            .preferredColorScheme(.light)
    }

    /// Barra flotante: las cartas pasan por detrás.
    private var chrome: some View {
        VStack(spacing: 8) {
            AppTopBar(title: "Cards") {
                Button {
                    withAnimation(.snappy(duration: 0.28)) { market.searchOpen.toggle() }
                    searchFocused = market.searchOpen
                    if !market.searchOpen, !market.query.isEmpty { market.query = ""; market.reloadToken += 1 }
                } label: { TopBarGlassButton(systemImage: market.searchOpen ? "xmark" : "magnifyingglass") }
                    .buttonStyle(.plain).accessibilityLabel("Search cards").tourTarget("cards.search")
                Button { market.showFilter = true } label: { TopBarGlassButton(systemImage: "slider.horizontal.3") }
                    .buttonStyle(.plain).accessibilityLabel("Filter by set").tourTarget("cards.filter")
            }
            if market.searchOpen {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search a card by name", text: $market.query)
                        .submitLabel(.search).autocorrectionDisabled().focused($searchFocused)
                        .onSubmit { market.reloadToken += 1 }
                }
                .padding(.horizontal, 14).frame(height: 46)
                .glassEffect(.regular, in: .capsule)
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
    @Published var sets: [PokemonSetData] = PokemonTCGClient.storedSets()
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
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool

    private var groups: [(series: String, sets: [PokemonSetData])] {
        let shown = text.isEmpty ? market.sets : market.sets.filter { $0.name.localizedCaseInsensitiveContains(text) || $0.series.localizedCaseInsensitiveContains(text) }
        var order: [String] = []
        var bySeries: [String: [PokemonSetData]] = [:]
        for set in shown {
            let key = set.series.isEmpty ? "Other" : set.series
            if bySeries[key] == nil { order.append(key) }
            bySeries[key, default: []].append(set)
        }
        return order.map { ($0, bySeries[$0] ?? []) }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 10) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.series) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.series.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(0.6)
                                    .foregroundStyle(.black.opacity(0.5)).padding(.leading, 4)
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(group.sets) { set in cell(set) }
                                }
                            }
                        }

                        if market.sets.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(red: 0.965, green: 0.965, blue: 0.975).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                // Misma cabecera que fuera: cerrar a la izquierda y la lupa redonda a la derecha.
                VStack(spacing: 8) {
                    HStack {
                        Button { dismiss() } label: { TopBarGlassButton(systemImage: "xmark") }.buttonStyle(.plain)
                        Spacer()
                        Text("Sets").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                        Spacer()
                        Button {
                            withAnimation(.snappy(duration: 0.28)) { searchOpen.toggle() }
                            searchFocused = searchOpen
                            if !searchOpen { text = "" }
                        } label: { TopBarGlassButton(systemImage: searchOpen ? "xmark.circle" : "magnifyingglass") }
                            .buttonStyle(.plain).accessibilityLabel("Search sets")
                    }
                    if searchOpen {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search sets", text: $text).autocorrectionDisabled().focused($searchFocused)
                        }
                        .padding(.horizontal, 14).frame(height: 46)
                        .background(.white, in: .capsule)
                        .glassEffect(.regular, in: .capsule)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
                .background {
                    LinearGradient(colors: [Color(red: 0.965, green: 0.965, blue: 0.975), Color(red: 0.965, green: 0.965, blue: 0.975).opacity(0)], startPoint: .center, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top)
                }
            }
            .task { if market.sets.isEmpty { market.sets = await PokemonTCGClient.fetchSets() } }
        }
        .preferredColorScheme(.light)
        .swipeBackToDismiss()
    }

    /// Ficha de cristal de una colección: logo arriba, nombre y año debajo.
    private func cell(_ set: PokemonSetData) -> some View {
        let on = market.selectedSet?.id == set.id
        return Button { market.choose(set); dismiss() } label: {
            VStack(spacing: 6) {
                AsyncImage(url: set.logoURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else { Skeleton(corner: 8) }
                }
                .frame(height: 40).frame(maxWidth: .infinity)
                Text(set.name).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.black)
                    .lineLimit(2).multilineTextAlignment(.center).frame(height: 28, alignment: .top)
                Text("\(set.total) · \(set.year)").font(.system(size: 10, weight: .medium)).foregroundStyle(.black.opacity(0.45))
            }
            .padding(.horizontal, 8).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.white, in: .rect(cornerRadius: 20))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(on ? Color.black : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
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
    @State private var openedCard: PokemonCardData?
    @State private var loadToken = 0
    @State private var failed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

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
                Color.clear.frame(height: market.searchOpen ? 108 : 54)

                if !sets.isEmpty { setsStrip }

                LazyVGrid(columns: columns, spacing: 8) {
                    // La carta de ejemplo (con todos sus datos de mercado) va siempre la primera.
                    ForEach([CardSample.card] + cards.filter { $0.id != CardSample.card.id }) { card in
                        Button { openedCard = card } label: { tile(card) }.tourTarget("cards.tile")
                            .buttonStyle(.plain)
                            .onAppear { if card.id == cards.last?.id { Task { await loadMore() } } }
                    }
                }

                if loading {
                    // Mientras llegan las cartas: la misma rejilla, en esqueleto.
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(0..<(cards.isEmpty ? 12 : 3), id: \.self) { _ in CardTileSkeleton() }
                    }
                } else if failed {
                    VStack(spacing: 10) {
                        Text("The card catalog did not respond.").font(.system(size: 14)).foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadMore() } }
                            .font(.system(size: 14, weight: .semibold)).buttonStyle(.borderedProminent).tint(.black)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if cards.isEmpty {
                    Text("No cards found with that name.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .modifier(HidesChromeOnScroll(hidden: $chromeHidden))
        .task {
            if cards.isEmpty { await reload() }
            let fresh = await PokemonTCGClient.fetchSets()
            if !fresh.isEmpty { market.sets = fresh }
        }
        .onChange(of: market.reloadToken) { _, _ in Task { await reload() } }
        .fullScreenCover(item: $report) { SaleReportView(report: $0) }
        .navigationDestination(item: $openedCard) { CardDetailView(card: $0) }
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
            if let set {
                AsyncImage(url: set.logoURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else { Skeleton(corner: 8) }
                }
                .frame(width: 78, height: 32)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(on ? Color.white : Color.clear, in: .rect(cornerRadius: 16))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(on ? Color.black : .clear, lineWidth: 1.5) }
            } else {
                // «Todas»: un círculo pequeño, del tamaño del icono.
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(on ? Color.white : Color.clear, in: .circle)
                .glassEffect(.regular.interactive(), in: .circle)
                    .overlay { Circle().strokeBorder(on ? Color.black : .clear, lineWidth: 1.5) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(set?.name ?? "All cards")
    }

    private func tile(_ card: PokemonCardData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardImage(url: card.thumbURL)
            .aspectRatio(0.72, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) { CardSourceDots(size: 20).padding(4) }
            Text(card.name).font(.system(size: 11, weight: .bold)).foregroundStyle(.black).lineLimit(1)
            Text(card.rarity)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(6)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) { CardEditionBadge(card: card).scaleEffect(0.8, anchor: .topTrailing).padding(3) }
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
        CardImage.prefetch(next.compactMap(\.thumbURL))
    }
}
