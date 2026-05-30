import Foundation
import UIKit

/// Imágenes del clóset en sandbox (sin Supabase): `originals/`, `crops/`, `prettified/`, `avatars/`, `faces/`, `shoe360/`, `shoe360_pro/`, `shoe360_pro_studio/` (salida Gemini del spin vídeo), `lookbook_studio/`, `lookbook_lifestyle/`.
enum ImageStore {
    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("closet-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func subdirectory(_ name: String) -> URL {
        let dir = rootDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func save(_ data: Data, inFolder folder: String, filename: String) throws -> String {
        let url = subdirectory(folder).appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return "\(folder)/\(filename)"
    }

    /// Crea `root/a/b/c` y guarda `filename`; devuelve ruta `"a/b/c/filename"` (sin prefijo jerárquico extra).
    @discardableResult
    static func save(_ data: Data, nestedRelativeFolder nested: String, filename: String) throws -> String {
        let trimmed = nested.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let folderURL = try ensureNestedDirectory(relativePath: trimmed)
        let fileURL = folderURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return "\(trimmed)/\(filename)"
    }

    /// Garantiza `rootDirectory / segmentos...` y devuelve la URL del directorio hoja.
    static func ensureNestedDirectory(relativePath: String) throws -> URL {
        var dir = rootDirectory
        for part in relativePath.split(separator: "/") where !part.isEmpty {
            dir = dir.appendingPathComponent(String(part), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(forRelativePath relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath)
    }

    static func load(_ relativePath: String) -> UIImage? {
        let path = url(forRelativePath: relativePath).path
        return UIImage(contentsOfFile: path)
    }

    /// Comprueba si existe el fichero **sin decodificar la imagen** (mucho más barato que `load`).
    static func exists(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(forRelativePath: relativePath).path)
    }

    /// Borra un fichero del almacén local del clóset (ignora si no existe).
    static func deleteIfExists(_ relativePath: String) {
        let u = url(forRelativePath: relativePath)
        if FileManager.default.fileExists(atPath: u.path) {
            try? FileManager.default.removeItem(at: u)
        }
    }
}

extension ImageStore {
    /// Para rejilla y collage: zapatos → lateral izquierdo; portada manual; si no, `imageFilename`.
    static func displayRelativePath(for item: ClosetItem) -> String {
        preferredCatalogCoverPath(for: item)
    }

    /// Miniatura horizontal de looks: portada del look, avatar, o primera prenda con imagen válida.
    static func lookRibbonThumbnailRelativePath(look: Look) -> String? {
        let custom = look.ribbonCoverRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty, exists(custom) {
            return custom
        }
        if let av = look.avatarRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !av.isEmpty, exists(av) {
            return av
        }
        for piece in look.resolvedItemsOrdered {
            let p = displayRelativePath(for: piece)
            if exists(p) { return p }
        }
        return nil
    }
}
