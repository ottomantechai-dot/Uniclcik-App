import Foundation
import SwiftData

/// Prenda persistida en dispositivo (SwiftData). La imagen vive en `ImageStore` vía `imageFilename`.
@Model
final class ClosetItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String?

    /// Texto libre (moneda símbolo + importe).
    var priceText: String?

    /// JSON `["#RRGGBB", …]` desde `ColorPaletteExtractor` local.
    var colorPaletteJSON: String?

    /// CSV raw values `DressCode` (legacy Gemini chips eliminados).
    var dressCodesRaw: String?
    /// CSV raw values `Season`.
    var seasonsRaw: String?

    /// Histórico: paleta Gemini en JSON con labels; mantener por migración liviana — no escribimos aquí nuevos datos.
    var aiColorsJSON: String?

    /// JSON `["shoe360/uuid.jpg", …]` — rutas en orden `ShoeAngle.allCases` (4 vistas; algunos vínculos antiguos guardaron 5 con cenital).
    var multiAngleFilenamesJSON: String?

    /// JSON hasta 36 rutas `shoe360_pro/<sesión>/imgNN.jpg` — giro desde video local (opcional).
    var spin360FilenamesJSON: String?

    /// JSON array de rutas relativas (`lookbook_studio/`), orden `LookbookStudioShot.allCases`.
    var lookbookStudioJSON: String?
    /// JSON array de rutas (`lookbook_lifestyle/`), orden `LookbookLifestyleShot.allCases`.
    var lookbookLifestyleJSON: String?

    /// Portada opcional en rejilla y ficha (`ImageStore`); debe existir como fichero cuando se define.
    var galleryCoverRelativePath: String?

    /// `ClothingCategory.rawValue`
    var categoryRaw: String
    var imageFilename: String
    var originalCropFilename: String?
    var sourceOutfitFilename: String?
    var boundingBoxJSON: String?
    var isDraft: Bool
    var createdAt: Date

    @Relationship(inverse: \Look.items)
    var looks: [Look] = []

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        priceText: String? = nil,
        colorPaletteJSON: String? = nil,
        dressCodesRaw: String? = nil,
        seasonsRaw: String? = nil,
        aiColorsJSON: String? = nil,
        multiAngleFilenamesJSON: String? = nil,
        spin360FilenamesJSON: String? = nil,
        lookbookStudioJSON: String? = nil,
        lookbookLifestyleJSON: String? = nil,
        galleryCoverRelativePath: String? = nil,
        category: ClothingCategory,
        imageFilename: String,
        originalCropFilename: String? = nil,
        sourceOutfitFilename: String? = nil,
        boundingBox: NormalizedRect? = nil,
        isDraft: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.priceText = priceText
        self.colorPaletteJSON = colorPaletteJSON
        self.dressCodesRaw = dressCodesRaw
        self.seasonsRaw = seasonsRaw
        self.aiColorsJSON = aiColorsJSON
        self.multiAngleFilenamesJSON = multiAngleFilenamesJSON
        self.spin360FilenamesJSON = spin360FilenamesJSON
        self.lookbookStudioJSON = lookbookStudioJSON
        self.lookbookLifestyleJSON = lookbookLifestyleJSON
        self.galleryCoverRelativePath = galleryCoverRelativePath
        self.categoryRaw = category.rawValue
        self.imageFilename = imageFilename
        self.originalCropFilename = originalCropFilename
        self.sourceOutfitFilename = sourceOutfitFilename
        if let b = boundingBox,
           let data = try? JSONEncoder().encode(b),
           let s = String(data: data, encoding: .utf8) {
            self.boundingBoxJSON = s
        } else {
            self.boundingBoxJSON = nil
        }
        self.isDraft = isDraft
        self.createdAt = createdAt
    }

    var category: ClothingCategory {
        ClothingCategory(rawValue: categoryRaw) ?? .accessories
    }

    /// Rutas relativas `shoe360/…` en orden fijo de ángulo.
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

    var hasShoeMultiAngle: Bool {
        let c = multiAngleFilenames.count
        return c == ShoeAngle.allCases.count || c == ShoeAngle.legacyMultiAngleCount
    }

    /// Secuencia densa desde video (~36 fotogramas en `shoe360_pro/`). ≥24 válidos como “spin completo usable”.
    var spin360Filenames: [String] {
        get {
            guard let s = spin360FilenamesJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty,
                  let data = s.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }
        set {
            if newValue.isEmpty {
                spin360FilenamesJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let str = String(data: data, encoding: .utf8) {
                spin360FilenamesJSON = str
            }
        }
    }

    var hasFullShoeSpinFromVideo: Bool { spin360Filenames.count >= 24 }

    /// Rutas en orden estable `LookbookStudioShot.allCases` (huecos si falló alguna variante).
    var lookbookStudio: [String] {
        get {
            guard let s = lookbookStudioJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty,
                  let data = s.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }
        set {
            if newValue.isEmpty {
                lookbookStudioJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let str = String(data: data, encoding: .utf8) {
                lookbookStudioJSON = str
            }
        }
    }

    /// Rutas en orden `LookbookLifestyleShot.allCases`.
    var lookbookLifestyle: [String] {
        get {
            guard let s = lookbookLifestyleJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty,
                  let data = s.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }
        set {
            if newValue.isEmpty {
                lookbookLifestyleJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let str = String(data: data, encoding: .utf8) {
                lookbookLifestyleJSON = str
            }
        }
    }

    var hasLookbook: Bool { !lookbookStudio.isEmpty || !lookbookLifestyle.isEmpty }

    /// Para galerías: studio primero y luego lifestyle (mismo orden que los enums).
    var lookbookAllFilenamesInOrder: [String] {
        lookbookStudio + lookbookLifestyle
    }

    var colorPaletteHexes: [String] {
        if let s = colorPaletteJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty,
           let data = s.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data),
           !arr.isEmpty {
            return arr
        }
        if !decodedLegacyColorChips.isEmpty {
            return decodedLegacyColorChips.map(\.hex)
        }
        return []
    }

    var dressCodesStored: [DressCode] {
        get {
            (dressCodesRaw ?? "")
                .split(separator: ",")
                .compactMap { DressCode(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
        }
        set {
            dressCodesRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    var seasonsStored: [Season] {
        get {
            (seasonsRaw ?? "")
                .split(separator: ",")
                .compactMap { Season(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
        }
        set {
            seasonsRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    private var decodedLegacyColorChips: [ClosetGarmentColorChip] {
        guard let s = aiColorsJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty,
              let data = s.data(using: .utf8),
              let arr = try? JSONDecoder().decode([ClosetGarmentColorChip].self, from: data)
        else { return [] }
        return arr
    }
}
