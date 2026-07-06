import Foundation
import SwiftData

/// Combinación de prendas locales (tipo Pinterest); avatar opcional en `look_avatars/` o `avatars/`.
@Model
final class Look {
    @Attribute(.unique) var id: UUID
    var name: String
    var occasion: String?
    var weatherText: String?
    var avatarRelativePath: String?
    /// `Ribbon` sobre la cinta horizontal de looks: ruta opcional preferida cuando el usuario la elige manualmente (`ImageStore`). Si falta → avatar → primera miniatura válida de prenda.
    var ribbonCoverRelativePath: String?
    /// `male` | `female` (coincide con prompt avatar).
    var avatarGenderRaw: String?
    var createdAt: Date
    var scheduledDate: Date?

    @Relationship(deleteRule: .nullify)
    var items: [ClosetItem] = []

    init(
        id: UUID = UUID(),
        name: String,
        items: [ClosetItem] = [],
        occasion: String? = nil,
        weatherText: String? = nil,
        avatarRelativePath: String? = nil,
        ribbonCoverRelativePath: String? = nil,
        avatarGenderRaw: String? = nil,
        scheduledDate: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.occasion = occasion
        self.weatherText = weatherText
        self.avatarRelativePath = avatarRelativePath
        self.ribbonCoverRelativePath = ribbonCoverRelativePath
        self.avatarGenderRaw = avatarGenderRaw
        self.scheduledDate = scheduledDate
        self.createdAt = createdAt
    }

    var resolvedItemsOrdered: [ClosetItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Perfil local (avatar / rostro)

/// Preferencias locales para avatar (foto de rostro opcional). No confundir con `UserProfileService` (cuenta Upsoled).
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    /// Relativo a `ImageStore`, p. ej. `faces/me.jpg`.
    var faceImageFilename: String?
    /// `AvatarGender.rawValue`; default generación desde Ajustes.
    var preferredGenderRaw: String?
    /// Si debemos incluir la cara como primera imagen al generar avatares.
    var useFaceByDefault: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        faceImageFilename: String? = nil,
        preferredGenderRaw: String? = nil,
        useFaceByDefault: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.faceImageFilename = faceImageFilename
        self.preferredGenderRaw = preferredGenderRaw
        self.useFaceByDefault = useFaceByDefault
        self.createdAt = createdAt
    }

    /// Un solo perfil local por dispositivo (crea si falta).
    @MainActor
    static func current(in context: ModelContext) -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let neo = UserProfile()
        context.insert(neo)
        try? context.save()
        return neo
    }
}
