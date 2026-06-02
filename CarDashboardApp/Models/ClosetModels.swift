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

    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
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
        case .beach: return "Beach"
        case .sport: return "Sport"
        }
    }
}

enum Season: String, CaseIterable, Codable {
    case spring, summer, fall, winter

    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .fall: return "Fall"
        case .winter: return "Winter"
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
        case .front: return "Front"
        case .right: return "Right side"
        case .back: return "Back"
        case .left: return "Left side"
        }
    }

    /// Segundo del vídeo guía (`Vidos-zapatos.mp4`) donde debe pausarse cada ángulo.
    /// Para `.left` usa el último frame (`duration` − margen).
    func guideVideoSeconds(duration: Double) -> Double {
        switch self {
        case .front: return 0
        case .right: return 2
        case .back: return 3
        case .left: return max(0, duration - 0.04)
        }
    }

    var instruction: String {
        switch self {
        case .front:
            return "Place the shoe pointing at the camera, showing the toe and laces."
        case .right:
            return "Rotate the shoe 90° and capture the full outer side."
        case .back:
            return "Capture the back of the shoe showing the heel."
        case .left:
            return "Turn to the inner side of the shoe and capture the full side."
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
        case .front: return "→ Toe facing you"
        case .right: return "→ Outer side"
        case .back: return "→ Heel / back"
        case .left: return "→ Inner side"
        }
    }

    /// Instrucciones genéricas para cualquier producto (no solo calzado).
    func productInstruction(for category: ClothingCategory) -> String {
        if category == .shoes { return instruction }
        switch self {
        case .front:
            return "Place the product facing the camera, showing the front."
        case .right:
            return "Rotate 90° to the right and capture the full right side."
        case .back:
            return "Turn the product around and capture the back."
        case .left:
            return "Rotate to show the full left side."
        }
    }

    func productSlotCue(for category: ClothingCategory) -> String {
        if category == .shoes { return slotCue }
        switch self {
        case .front: return "→ Front view"
        case .right: return "→ Right side"
        case .back: return "→ Back view"
        case .left: return "→ Left side"
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
        case .front: return "Full front"
        case .back: return "Full back"
        case .detail1: return "Detail (main print)"
        case .detail2: return "Detail (collar / label)"
        case .detail3: return "Detail (fabric / texture)"
        }
    }

    var instruction: String {
        switch self {
        case .front: return "Lay the garment flat and capture the full front."
        case .back: return "Flip the garment and capture the full back."
        case .detail1: return "Move closer to the print, logo, or main motif."
        case .detail2: return "Close-up of collar, inner label, or fine seams."
        case .detail3: return "Fabric texture or hang tag with macro."
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
        case .dressesJumpsuits: return "Dresses / jumpsuits"
        case .pantsSkirts: return "Pants & skirts"
        case .coats: return "Coats"
        case .shoes: return "Shoes"
        case .accessories: return "Accessories"
        case .bags: return "Bags"
        case .underwear: return "Underwear"
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
    var skuText: String
    var sizeText: String
    var colorLabel: String
    var productDescription: String
    var purchasePriceText: String
    var priceText: String
    var marketPriceJSON: String?
    var listingPlatformsRaw: String?
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
    var skuText: String?
    var sizeText: String?
    var colorLabel: String?
    var productDescription: String?
    var purchasePriceText: String?
    var priceText: String?
    var marketPriceJSON: String?
    var listingPlatformsRaw: String?
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
            skuText: skuText ?? "",
            sizeText: sizeText ?? "",
            colorLabel: colorLabel ?? "",
            productDescription: productDescription ?? "",
            purchasePriceText: purchasePriceText ?? "",
            priceText: priceText ?? "",
            marketPriceJSON: marketPriceJSON,
            listingPlatformsRaw: listingPlatformsRaw,
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
            skuText: skuText.isEmpty ? nil : skuText,
            sizeText: sizeText,
            colorLabel: colorLabel,
            productDescription: productDescription,
            purchasePriceText: purchasePriceText.isEmpty ? nil : purchasePriceText,
            priceText: priceText,
            marketPriceJSON: marketPriceJSON,
            listingPlatformsRaw: listingPlatformsRaw,
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
