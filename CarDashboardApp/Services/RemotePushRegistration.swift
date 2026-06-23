import Foundation
import Supabase
import UIKit
import UserNotifications

/// Registro de APNs y sincronización del token con Supabase (`user_apns_devices`).
enum RemotePushRegistration {
    private static let pendingTokenKey = "Upsoled.pendingAPNsTokenHex"

    /// Push desactivado: no solicita permiso ni registra el dispositivo en APNs.
    @MainActor
    static func requestAuthorizationAndRegister() async {}

    /// Llamar cuando APNs devuelve el token (desde `AppDelegate`).
    static func storeDeviceTokenFromAPNs(_ data: Data) {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: pendingTokenKey)
        #if DEBUG
        let prefix = hex.prefix(12)
        print("[Upsoled APNs] Token recibido de Apple (hex \(prefix)…, \(hex.count) chars). Subiendo a Supabase si hay sesión.")
        #endif
        Task {
            await syncPendingTokenToSupabase()
        }
    }

    /// Tras iniciar sesión, reintenta subir el token pendiente.
    static func syncPendingTokenToSupabase(client: SupabaseClient = SupabaseClientProvider.shared) async {
        guard let hex = UserDefaults.standard.string(forKey: pendingTokenKey), !hex.isEmpty else { return }
        guard let uid = client.auth.currentSession?.user.id else {
            #if DEBUG
            print("[Upsoled APNs] Hay token pero no hay sesión: inicia sesión para guardarlo en user_apns_devices.")
            #endif
            return
        }

        struct Row: Encodable {
            let user_id: UUID
            let device_token: String
        }

        do {
            try await client
                .from("user_apns_devices")
                .upsert(Row(user_id: uid, device_token: hex), onConflict: "user_id,device_token")
                .execute()
            #if DEBUG
            print("[Upsoled APNs] OK: token guardado en Supabase (user_apns_devices) para usuario \(uid.uuidString.prefix(8))…")
            #endif
        } catch {
            #if DEBUG
            print("[Upsoled APNs] Error al guardar token: \(error)")
            #endif
        }
    }
}
