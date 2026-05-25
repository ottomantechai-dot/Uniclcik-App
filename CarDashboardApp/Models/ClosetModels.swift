import Foundation

// MARK: - Paleta legada (Gemini JSON con label) — solo lectura en items antiguos

/// Chip de paleta histórica (`aiColorsJSON`).
struct ClosetGarmentColorChip: Codable, Hashable, Identifiable {
    var hex: String
    var label: String
    var id: String { "\(hex)|\(label)" }
}

// MARK: - Avatar en looks

enum AvatarGender: String, CaseIterable, Codable {
    case male
    case female

    var displayNameSpanish: String {
        switch self {
        case .male: return "Chico"
        case .female: return "Chica"
        }
    }
}

// MARK: - Detalle prenda: dress codes y estaciones

enum DressCode: String, CaseIterable, Codable {
    case nightParty = "night_party"
    case dressyCasual = "dressy_casual"
    case cocktail
    case blackTie = "black_tie"
    case businessFormal = "business_formal"
    case casual
    case streetwear
    case beach
    case sport

    var displayName: String {
        switch self {
        case .nightParty: return "Night-time party"
        case .dressyCasual: return "Dressy casual"
        case .cocktail: return "Cocktail"
        case .blackTie: return "Black tie"
        case .businessFormal: return "Business formal"
        case .casual: return "Casual"
        case .streetwear: return "Streetwear"
        case .beach: return "Playa"
        case .sport: return "Deportivo"
        }
    }
}

enum Season: String, CaseIterable, Codable {
    case spring, summer, fall, winter

    var displayName: String {
        switch self {
        case .spring: return "Primavera"
        case .summer: return "Verano"
        case .fall: return "Otoño"
        case .winter: return "Invierno"
        }
    }
}

// MARK: - Zapatos · captura multi-ángulo (360°)

/// Orden para vista 360° en plano horizontal (sin foto cenital / desde arriba).
enum ShoeAngle: Int, CaseIterable, Identifiable {
    case front = 0
    case right
    case back
    case left

    var id: Int { rawValue }

    /// Número esperado en JSON nuevo; pueden existir items antiguos con 5 rutas (incluía cenital).
    static var legacyMultiAngleCount: Int { 5 }

    var displayName: String {
        switch self {
        case .front: return "Frontal"
        case .right: return "Lateral derecho"
        case .back: return "Trasera"
        case .left: return "Lateral izquierdo"
        }
    }

    var instruction: String {
        switch self {
        case .front:
            return "Coloca el zapato apuntando hacia la cámara, mostrando la punta y los cordones."
        case .right:
            return "Gira el zapato 90° y captura el lateral exterior completo."
        case .back:
            return "Captura la parte trasera del zapato mostrando el talón."
        case .left:
            return "Gira al lateral interior del zapato y captura el costado completo."
        }
    }

    var icon: String {
        switch self {
        case .front: return "arrow.up.forward.circle"
        case .right: return "arrow.right.circle"
        case .back: return "arrow.up.backward.circle"
        case .left: return "arrow.left.circle"
        }
    }

    /// Leyenda corta en listas: qué encaja en cada foto / ángulo.
    var slotCue: String {
        switch self {
        case .front: return "→ Punta mirando a ti"
        case .right: return "→ Costado exterior"
        case .back: return "→ Talón / parte trasera"
        case .left: return "→ Costado interior"
        }
    }
}

// MARK: - Lookbook de prenda (no zapatos)

/// Fotos guiadas antes de lanzar las 10 generaciones IA (5 studio + 5 lifestyle).
enum GarmentAngle: Int, CaseIterable, Identifiable {
    case front = 0
    case back
    case detail1
    case detail2
    case detail3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .front: return "Frente completo"
        case .back: return "Espalda completa"
        case .detail1: return "Detalle (estampado principal)"
        case .detail2: return "Detalle (cuello / etiqueta)"
        case .detail3: return "Detalle (tela / textura)"
        }
    }

    var instruction: String {
        switch self {
        case .front: return "Extiende la prenda y captura toda la parte frontal."
        case .back: return "Voltea la prenda y captura la parte trasera completa."
        case .detail1: return "Acércate al estampado, logo o motivo principal."
        case .detail2: return "Primer plano de cuello, etiqueta interior o costuras finas."
        case .detail3: return "Textura de la tela o etiqueta volante con macro."
        }
    }

    var icon: String {
        switch self {
        case .front: return "tshirt"
        case .back: return "tshirt.fill"
        case .detail1: return "sparkles.rectangle.stack"
        case .detail2: return "tag"
        case .detail3: return "camera.macro"
        }
    }
}

enum LookbookStudioShot: String, CaseIterable, Identifiable {
    case frontWhite = "studio_front"
    case backWhite = "studio_back"
    case angledThreeQuarter = "studio_3quarter"
    case flatLay = "studio_flatlay"
    case detailMacro = "studio_detail"

    var id: String { rawValue }
}

enum LookbookLifestyleShot: String, CaseIterable, Identifiable {
    case urbanNeonFront = "lifestyle_neon_front"
    case urbanNeonBack = "lifestyle_neon_back"
    case industrialDay = "lifestyle_industrial"
    case interiorMirror = "lifestyle_interior"
    case portraitClose = "lifestyle_portrait"

    var id: String { rawValue }
}

// MARK: - Eventos locales

enum ClosetAnalytics {
    static func track(_ event: String) {
        #if DEBUG
            print("[ClosetAnalytics] \(event)")
        #endif
    }

    static func named(_ id: String, params: String = "") {
        track(params.isEmpty ? id : "\(id)(\(params))")
    }
}

// MARK: - Geometría (0–1 tras convertir desde Gemini box_2d 0–1000)

struct NormalizedRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

// MARK: - Categorías (snake_case en JSON de Gemini)

enum ClothingCategory: String, CaseIterable, Codable {
    case tops
    case dressesJumpsuits = "dresses_jumpsuits"
    case pantsSkirts = "pants_skirts"
    case coats, shoes, accessories, bags, underwear

    var displayName: String {
        switch self {
        case .tops: return "Tops"
        case .dressesJumpsuits: return "Vestidos / monos"
        case .pantsSkirts: return "Pantalones y faldas"
        case .coats: return "Abrigos"
        case .shoes: return "Zapatos"
        case .accessories: return "Complementos"
        case .bags: return "Bolsos"
        case .underwear: return "Ropa interior"
        }
    }

    var emoji: String {
        switch self {
        case .tops: return "👔"
        case .dressesJumpsuits: return "👗"
        case .pantsSkirts: return "👖"
        case .coats: return "🧥"
        case .shoes: return "👞"
        case .accessories: return "⌚"
        case .bags: return "👜"
        case .underwear: return "🩲"
        }
    }

    static func parsing(_ raw: String) -> ClothingCategory? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = ClothingCategory(rawValue: t) { return exact }
        switch t {
        case "shirt", "blouse", "top", "jacket": return .tops
        case "dress", "jumpsuit": return .dressesJumpsuits
        case "pants", "skirt", "jeans": return .pantsSkirts
        case "coat", "outerwear": return .coats
        case "sneakers", "boots", "sandals": return .shoes
        case "bag", "backpack": return .bags
        default:
            return nil
        }
    }
}

/// Modelo editable en pantalla de revisión (rutas relativas a `ImageStore.rootDirectory`).
struct ClosetDraftPiece: Identifiable, Equatable {
    let id: UUID
    var originalCropRelativePath: String
    var prettifiedRelativePath: String?
    /// JSON `["shoe360/uuid.jpg", …]` — rutas en orden `ShoeAngle.allCases` (4) tras generar 360°.
    var multiAngleFilenamesJSON: String?
    var sourceOutfitRelativePath: String?
    var boundingBox: NormalizedRect?
    var name: String
    var brand: String
    var category: ClothingCategory?
    /// Prettify falló en el último intento.
    var prettifyFailedBadge: Bool
}

// MARK: - Borradores (JSON en UserDefaults si el usuario cierra el flujo)

struct ClosetDraftPiecePersisted: Codable, Identifiable {
    let id: UUID
    var originalCropRelativePath: String
    var prettifiedRelativePath: String?
    var multiAngleFilenamesJSON: String?
    var sourceOutfitRelativePath: String?
    var boundingBox: NormalizedRect?
    var name: String
    var brand: String
    var categoryRaw: String?

    func toDraft() -> ClosetDraftPiece {
        ClosetDraftPiece(
            id: id,
            originalCropRelativePath: originalCropRelativePath,
            prettifiedRelativePath: prettifiedRelativePath,
            multiAngleFilenamesJSON: multiAngleFilenamesJSON,
            sourceOutfitRelativePath: sourceOutfitRelativePath,
            boundingBox: boundingBox,
            name: name,
            brand: brand,
            category: categoryRaw.flatMap { ClothingCategory(rawValue: $0) },
            prettifyFailedBadge: false
        )
    }
}

extension ClosetDraftPiece {
    func persistedSnapshot() -> ClosetDraftPiecePersisted {
        ClosetDraftPiecePersisted(
            id: id,
            originalCropRelativePath: originalCropRelativePath,
            prettifiedRelativePath: prettifiedRelativePath,
            multiAngleFilenamesJSON: multiAngleFilenamesJSON,
            sourceOutfitRelativePath: sourceOutfitRelativePath,
            boundingBox: boundingBox,
            name: name,
            brand: brand,
            categoryRaw: category?.rawValue
        )
    }

    /// Rutas `shoe360/…` en orden fijo de ángulo (misma semántica que `ClosetItem.multiAngleFilenames`).
    var multiAngleFilenames: [String] {
        get {
            guard let s = multiAngleFilenamesJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty,
                  let data = s.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }
        set {
            if newValue.isEmpty {
                multiAngleFilenamesJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let str = String(data: data, encoding: .utf8) {
                multiAngleFilenamesJSON = str
            }
        }
    }

    var shoe360Complete: Bool {
        let c = multiAngleFilenames.count
        return c == ShoeAngle.allCases.count || c == ShoeAngle.legacyMultiAngleCount
    }

    /// Listo para miniatura/catálogo: Prettify normal o vista 360° de zapatos completa.
    var isCatalogImageReady: Bool {
        guard let cat = category else { return false }
        if cat == .shoes { return shoe360Complete }
        return prettifiedRelativePath != nil
    }
}

/// Clave única en dispositivo (clóset ya no depende del `user_id`).
enum ClosetLocalDraftStore {
    static let userDefaultsKey = "closet_local_draft_flow_v2"

    static var pendingCount: Int {
        decoded().count
    }

    static func decoded() -> [ClosetDraftPiece] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let arr = try? JSONDecoder().decode([ClosetDraftPiecePersisted].self, from: data)
        else { return [] }
        return arr.map { $0.toDraft() }
    }

    static func save(_ pieces: [ClosetDraftPiece]) {
        guard !pieces.isEmpty else {
            clear()
            return
        }
        let enc = pieces.map { $0.persistedSnapshot() }
        if let d = try? JSONEncoder().encode(enc) {
            UserDefaults.standard.set(d, forKey: userDefaultsKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
