import Foundation

// MARK: - Ordenación

enum CarSortOption: String, CaseIterable, Identifiable {
    case relevance
    case priceAsc
    case priceDesc
    case monthlyAsc
    case monthlyDesc
    case kmAsc
    case kmDesc
    case yearDesc
    case yearAsc

    var id: String { rawValue }

    /// Opciones mostradas al usuario (catálogo zapatillas / ropa; sin ordenar por «km» de coche).
    static let browseSortCases: [CarSortOption] = [
        .relevance, .priceAsc, .priceDesc, .monthlyAsc, .monthlyDesc, .yearDesc, .yearAsc,
    ]

    var title: String {
        switch self {
        case .relevance: return "Recomendados"
        case .priceAsc: return "Precio: más baratos primero"
        case .priceDesc: return "Precio: más caros primero"
        case .monthlyAsc: return "Cuota o pago fraccionado: más bajo"
        case .monthlyDesc: return "Cuota o pago fraccionado: más alto"
        case .kmAsc: return "Campo numérico (talla-stock): menor primero"
        case .kmDesc: return "Campo numérico (talla-stock): mayor primero"
        case .yearDesc: return "Año / temporada: más reciente"
        case .yearAsc: return "Año / temporada: más antiguo"
        }
    }
}

// MARK: - Filtros

struct CarListFilters: Equatable {
    var bodyTypes: Set<String> = []
    var brands: Set<String> = []
    var fuelTypes: Set<String> = []
    var sellerKinds: Set<String> = []
    var dgtLabels: Set<String> = []
    var colors: Set<String> = []
    var locations: Set<String> = []

    var minPriceUSD: Double?
    var maxPriceUSD: Double?
    var minYear: Int?
    var maxYear: Int?
    var minKm: Int?
    var maxKm: Int?

    var electricOnly: Bool = false
    var onlineServicesOnly: Bool = false
    var equipmentQuery: String = ""

    var hasActiveFilters: Bool {
        !bodyTypes.isEmpty
            || !brands.isEmpty
            || !fuelTypes.isEmpty
            || !sellerKinds.isEmpty
            || !dgtLabels.isEmpty
            || !colors.isEmpty
            || !locations.isEmpty
            || minPriceUSD != nil
            || maxPriceUSD != nil
            || minYear != nil
            || maxYear != nil
            || minKm != nil
            || maxKm != nil
            || electricOnly
            || onlineServicesOnly
            || !equipmentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
