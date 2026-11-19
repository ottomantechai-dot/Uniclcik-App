import Foundation
import SwiftUI

// MARK: - Sobres de cartas de Uniclick
// Cartas propias de la app (no de ninguna otra marca), con el mundo de la reventa como tema.
// Se consiguen abriendo sobres: uno gratis cada día y uno más por cada caja escaneada con informe.

struct UniCard: Identifiable, Hashable {
    enum Rarity: Int, CaseIterable, Comparable {
        case common, rare, epic, legendary
        static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }

        var name: String {
            switch self {
            case .common: return "Común"
            case .rare: return "Rara"
            case .epic: return "Épica"
            case .legendary: return "Legendaria"
            }
        }
        var colors: [Color] {
            switch self {
            case .common: return [Color(red: 0.55, green: 0.60, blue: 0.68), Color(red: 0.32, green: 0.36, blue: 0.44)]
            case .rare: return [Color(red: 0.20, green: 0.55, blue: 1.00), Color(red: 0.10, green: 0.25, blue: 0.75)]
            case .epic: return [Color(red: 0.72, green: 0.35, blue: 1.00), Color(red: 0.36, green: 0.12, blue: 0.70)]
            case .legendary: return [Color(red: 1.00, green: 0.80, blue: 0.25), Color(red: 0.95, green: 0.45, blue: 0.10)]
            }
        }
        /// Probabilidad de que salga en un hueco normal del sobre.
        var weight: Double {
            switch self {
            case .common: return 0.68
            case .rare: return 0.24
            case .epic: return 0.07
            case .legendary: return 0.01
            }
        }
    }

    let id: String
    let name: String
    let symbol: String
    let rarity: Rarity
    let text: String

    static let all: [UniCard] = [
        UniCard(id: "caja", name: "Caja Intacta", symbol: "shippingbox.fill", rarity: .common, text: "Sin abrir, con su papel y su etiqueta."),
        UniCard(id: "etiqueta", name: "Etiqueta Original", symbol: "tag.fill", rarity: .common, text: "El detalle que sube el precio."),
        UniCard(id: "cordones", name: "Cordones de Repuesto", symbol: "lasso", rarity: .common, text: "Siempre hacen falta."),
        UniCard(id: "escaner", name: "Escáner Rápido", symbol: "barcode.viewfinder", rarity: .common, text: "Un código y ya sabes cuánto vale."),
        UniCard(id: "talla", name: "Talla Fácil", symbol: "ruler.fill", rarity: .common, text: "La 9.5 que todo el mundo busca."),
        UniCard(id: "envio", name: "Envío Asegurado", symbol: "truck.box.fill", rarity: .common, text: "Llega a tiempo y de una pieza."),
        UniCard(id: "recibo", name: "Recibo Guardado", symbol: "doc.text.fill", rarity: .common, text: "Quien guarda el recibo, vende mejor."),
        UniCard(id: "limpieza", name: "Limpieza a Fondo", symbol: "sparkles", rarity: .common, text: "Como recién salidas de la tienda."),
        UniCard(id: "restock", name: "Aviso de Restock", symbol: "bell.badge.fill", rarity: .rare, text: "Llegaste antes que nadie."),
        UniCard(id: "arbitraje", name: "Arbitraje", symbol: "arrow.left.arrow.right.circle.fill", rarity: .rare, text: "Comprar aquí, vender allá."),
        UniCard(id: "autentico", name: "Sello de Autenticidad", symbol: "checkmark.seal.fill", rarity: .rare, text: "Verificadas y sin dudas."),
        UniCard(id: "grafica", name: "Gráfica al Alza", symbol: "chart.line.uptrend.xyaxis", rarity: .rare, text: "El precio no para de subir."),
        UniCard(id: "almacen", name: "Almacén Lleno", symbol: "archivebox.fill", rarity: .rare, text: "Stock de sobra para toda la temporada."),
        UniCard(id: "coleccion", name: "Colección Completa", symbol: "square.stack.3d.up.fill", rarity: .epic, text: "Todos los colores de un mismo modelo."),
        UniCard(id: "muestra", name: "Par de Muestra", symbol: "star.circle.fill", rarity: .epic, text: "Un par que nunca llegó a las tiendas."),
        UniCard(id: "rayo", name: "Venta Relámpago", symbol: "bolt.fill", rarity: .epic, text: "Publicado y vendido en un minuto."),
        UniCard(id: "grial", name: "El Grial", symbol: "crown.fill", rarity: .legendary, text: "El par que todos buscan y casi nadie tiene."),
        UniCard(id: "boleto", name: "Boleto Dorado", symbol: "ticket.fill", rarity: .legendary, text: "Ganaste el sorteo más difícil del año."),
    ]

    static func with(id: String) -> UniCard? { all.first { $0.id == id } }
}

@MainActor
final class CardPackStore: ObservableObject {
    static let shared = CardPackStore()
    static let packSize = 5

    @Published private(set) var packs: Int
    @Published private(set) var owned: [String: Int]

    private let defaults = UserDefaults.standard
    private let packsKey = "cards.packs", ownedKey = "cards.owned", dailyKey = "cards.lastDaily", startedKey = "cards.started"

    private init() {
        // La primera vez se regalan tres sobres de bienvenida.
        if !defaults.bool(forKey: startedKey) {
            defaults.set(true, forKey: startedKey)
            defaults.set(3, forKey: packsKey)
        }
        packs = defaults.integer(forKey: packsKey)
        owned = (defaults.dictionary(forKey: ownedKey) as? [String: Int]) ?? [:]
    }

    var uniqueOwned: Int { owned.count }
    var canClaimDaily: Bool { defaults.string(forKey: dailyKey) != Self.today }
    private static var today: String { Date().formatted(.iso8601.year().month().day()) }

    func claimDaily() {
        guard canClaimDaily else { return }
        defaults.set(Self.today, forKey: dailyKey)
        setPacks(packs + 1)
    }

    /// Un sobre por cada caja escaneada con informe.
    func earnPack() { setPacks(packs + 1) }

    /// Gasta un sobre y devuelve sus cartas. El último hueco es rara o mejor.
    func openPack() -> [UniCard] {
        guard packs > 0 else { return [] }
        setPacks(packs - 1)
        var cards = (0..<(Self.packSize - 1)).map { _ in draw(minimum: .common) }
        cards.append(draw(minimum: .rare))
        for card in cards { owned[card.id, default: 0] += 1 }
        defaults.set(owned, forKey: ownedKey)
        return cards
    }

    private func draw(minimum: UniCard.Rarity) -> UniCard {
        let pool = UniCard.Rarity.allCases.filter { $0 >= minimum }
        var roll = Double.random(in: 0..<pool.reduce(0) { $0 + $1.weight })
        var rarity = pool[0]
        for option in pool {
            if roll < option.weight { rarity = option; break }
            roll -= option.weight
        }
        return UniCard.all.filter { $0.rarity == rarity }.randomElement() ?? UniCard.all[0]
    }

    private func setPacks(_ value: Int) {
        packs = max(0, value)
        defaults.set(packs, forKey: packsKey)
    }
}
