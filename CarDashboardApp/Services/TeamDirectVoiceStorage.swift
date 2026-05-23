import Foundation
import Supabase

/// Notas de voz en DMs de equipo: el archivo vive en Storage; `team_direct_messages.body` guarda el prefijo + ruta relativa.
enum TeamDirectVoiceStorage {
    static let bodyPrefix = "UPSOLED_VOICE_V1:"
    private static let legacyBodyPrefix = "CARHUB_VOICE_V1:"

    static var bucket: String { SupabaseClientProvider.teamDirectVoiceBucket }

    static func isVoiceMessageBody(_ body: String) -> Bool {
        body.hasPrefix(bodyPrefix) || body.hasPrefix(legacyBodyPrefix)
    }

    static func storagePath(fromMessageBody body: String) -> String? {
        let prefix: String
        if body.hasPrefix(bodyPrefix) {
            prefix = bodyPrefix
        } else if body.hasPrefix(legacyBodyPrefix) {
            prefix = legacyBodyPrefix
        } else {
            return nil
        }
        let path = String(body.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Texto amigable para filas de la bandeja de chat.
    static func inboxPreviewBody(for messageBody: String) -> String {
        isVoiceMessageBody(messageBody) ? "Nota de voz" : messageBody
    }

    static func makeObjectPath(senderId: UUID, recipientId: UUID, fileId: UUID = UUID()) -> String {
        let a = senderId.uuidString.lowercased()
        let b = recipientId.uuidString.lowercased()
        return "\(a)/\(b)/\(fileId.uuidString.lowercased()).m4a"
    }

    static func messageBody(forStoragePath path: String) -> String {
        bodyPrefix + path
    }

    static func upload(fileURL: URL, path: String, client: SupabaseClient) async throws {
        let data = try Data(contentsOf: fileURL)
        _ = try await client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "audio/m4a", upsert: true)
            )
    }

    static func download(path: String, client: SupabaseClient) async throws -> Data {
        try await client.storage.from(bucket).download(path: path)
    }
}
