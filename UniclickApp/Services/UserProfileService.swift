import Foundation
import Supabase
import UIKit

/// Lectura de perfil Supabase (`profiles`) y descarga del avatar (Storage o URL).
enum UserProfileService {
    private struct NotifyTeamPushRow: Decodable {
        let notifyTeamPush: Bool?
        enum CodingKeys: String, CodingKey {
            case notifyTeamPush = "notify_team_push"
        }
    }

    private struct NotifyTeamPushUpdate: Encodable {
        let notifyTeamPush: Bool
        enum CodingKeys: String, CodingKey {
            case notifyTeamPush = "notify_team_push"
        }
    }

    /// Preferencia de push de equipo (mensajes/tareas). Si no hay fila o la columna es null, se asume activado.
    static func fetchNotifyTeamPush(userId: UUID, client: SupabaseClient) async -> Bool {
        for value in [userId.uuidString.lowercased(), userId.uuidString] {
            do {
                let rows: [NotifyTeamPushRow] = try await client
                    .from(SupabaseClientProvider.profilesTableName)
                    .select("notify_team_push")
                    .eq("user_id", value: value)
                    .limit(1)
                    .execute()
                    .value
                if let v = rows.first?.notifyTeamPush { return v }
            } catch {}
        }
        return true
    }

    static func setNotifyTeamPush(_ enabled: Bool, userId: UUID, client: SupabaseClient) async throws {
        let payload = NotifyTeamPushUpdate(notifyTeamPush: enabled)
        try await client
            .from(SupabaseClientProvider.profilesTableName)
            .update(payload)
            .eq("user_id", value: userId.uuidString.lowercased())
            .execute()
    }

    private struct ProfileAvatarRow: Decodable {
        let avatarUrl: String?
        enum CodingKeys: String, CodingKey {
            case avatarUrl = "avatar_url"
        }
    }

    /// Referencia a imagen: URL absoluta o ruta dentro del bucket de avatares.
    static func resolveAvatarRef(user: User, client: SupabaseClient) async -> String? {
        if let fromTable = await fetchAvatarURLFromProfiles(userId: user.id, client: client) {
            return fromTable
        }
        return avatarRefFromUserMetadata(user)
    }

    private static func fetchAvatarURLFromProfiles(userId: UUID, client: SupabaseClient) async -> String? {
        for value in [userId.uuidString.lowercased(), userId.uuidString] {
            do {
                let row: ProfileAvatarRow = try await client
                    .from(SupabaseClientProvider.profilesTableName)
                    .select("avatar_url")
                    .eq("user_id", value: value)
                    .single()
                    .execute()
                    .value
                let s = row.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let s, !s.isEmpty { return s }
            } catch {}
        }
        return nil
    }

    private static func avatarRefFromUserMetadata(_ user: User) -> String? {
        let keys = ["avatar_url", "picture", "photo_url", "avatarUrl"]
        for k in keys {
            if let s = user.userMetadata[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    @MainActor
    static func loadProfileAvatarImage(
        avatarRef: String?,
        userId: UUID,
        client: SupabaseClient,
        accessToken: String?
    ) async -> UIImage? {
        guard let ref = avatarRef?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else { return nil }

        let cacheKey = "profileAvatar:\(userId.uuidString.lowercased()):\(ref)"
        if let cached = ImageCacheService.shared.image(forKey: cacheKey) {
            return cached
        }

        let image: UIImage?
        let lower = ref.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            image = await downloadHTTP(urlString: ref, accessToken: accessToken)
        } else {
            var fromStorage = await downloadFromStorage(path: ref, client: client, accessToken: accessToken)
            if fromStorage == nil {
                fromStorage = await downloadHTTP(
                    urlString: SupabaseClientProvider.publicStorageObjectURL(
                        bucket: SupabaseClientProvider.userAvatarBucket,
                        path: ref
                    ),
                    accessToken: accessToken
                )
            }
            image = fromStorage
        }

        if let image {
            ImageCacheService.shared.store(image, forKey: cacheKey)
        }
        return image
    }

    @MainActor
    private static func downloadHTTP(urlString: String, accessToken: String?) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        let isSupabaseURL = url.host?.contains("supabase") == true
        if isSupabaseURL {
            request.setValue(SupabaseClientProvider.anonKey, forHTTPHeaderField: "apikey")
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("Bearer \(SupabaseClientProvider.anonKey)", forHTTPHeaderField: "Authorization")
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return nil }
            guard let ui = UIImage(data: data), ui.size.width > 0 else { return nil }
            return ui
        } catch {
            return nil
        }
    }

    @MainActor
    private static func downloadFromStorage(path: String, client: SupabaseClient, accessToken: String?) async -> UIImage? {
        let bucket = SupabaseClientProvider.userAvatarBucket
        do {
            let data = try await client.storage.from(bucket).download(path: path)
            if let ui = UIImage(data: data), ui.size.width > 0 { return ui }
        } catch {}

        do {
            let signed = try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 3600)
            return await downloadHTTP(urlString: signed.absoluteString, accessToken: accessToken)
        } catch {}

        return nil
    }
}

// MARK: - Avatar upload

extension UserProfileService {
    enum AvatarUploadError: LocalizedError {
        case notAuthenticated
        case invalidImage
        case uploadFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Sign in to update your profile photo."
            case .invalidImage:
                return "Could not process the photo."
            case .uploadFailed(let msg):
                return msg
            }
        }
    }

    /// Square JPEG for profile avatar (max side 512 px).
    static func prepareAvatarJPEG(from image: UIImage, maxSide: CGFloat = 512) -> Data? {
        let flat = flattenOrientation(image)
        let side = min(flat.size.width, flat.size.height)
        guard side > 0 else { return nil }

        let cropRect = CGRect(
            x: (flat.size.width - side) / 2,
            y: (flat.size.height - side) / 2,
            width: side,
            height: side
        )
        guard let cg = flat.cgImage?.cropping(to: cropRect.integral) else { return nil }
        var squared = UIImage(cgImage: cg, scale: flat.scale, orientation: .up)

        let longest = max(squared.size.width, squared.size.height)
        if longest > maxSide {
            let scale = maxSide / longest
            let newSize = CGSize(width: squared.size.width * scale, height: squared.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
            squared.draw(in: CGRect(origin: .zero, size: newSize))
            squared = UIGraphicsGetImageFromCurrentImageContext() ?? squared
            UIGraphicsEndImageContext()
        }

        return squared.jpegData(compressionQuality: 0.88)
    }

    /// Uploads avatar to Storage and updates `avatar_url` on the profile row.
    static func uploadProfileAvatar(
        jpegData: Data,
        userId: UUID,
        client: SupabaseClient
    ) async throws -> String {
        _ = try await client.auth.session

        let bucket = SupabaseClientProvider.userAvatarBucket
        let path = "\(userId.uuidString.lowercased())/avatar.jpg"

        do {
            _ = try await client.storage
                .from(bucket)
                .upload(
                    path,
                    data: jpegData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
        } catch {
            throw AvatarUploadError.uploadFailed(error.localizedDescription)
        }

        struct AvatarPatch: Encodable {
            let avatarUrl: String
            enum CodingKeys: String, CodingKey {
                case avatarUrl = "avatar_url"
            }
        }

        let patch = AvatarPatch(avatarUrl: path)
        let table = SupabaseClientProvider.profilesTableName
        let uid = userId.uuidString.lowercased()

        struct AvatarRow: Encodable {
            let userId: String
            let avatarUrl: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case avatarUrl = "avatar_url"
            }
        }

        do {
            // Crea la fila de perfil si aún no existe y guarda la foto; con solo actualizar,
            // una cuenta sin fila se quedaba sin foto y sin aviso.
            try await client
                .from(table)
                .upsert(AvatarRow(userId: uid, avatarUrl: path), onConflict: "user_id")
                .execute()
        } catch {
            // Some schemas use `id` = auth.users.id instead of `user_id`.
            try await client
                .from(table)
                .update(patch)
                .eq("id", value: uid)
                .execute()
        }

        return path
    }

    private static func flattenOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return out
    }
}
