import AuthenticationServices
import Combine
import Foundation
import Supabase
import UIKit

@MainActor
final class AuthViewModel: ObservableObject {
    enum IdentityProvider: String, CaseIterable {
        case google = "Google"
        case stockX = "StockX"
        case apple = "Apple"
    }

    enum PhoneEnrollment: Equatable {
        case saved
        case needsCode
        case failed
    }

    struct AuthMethods: Decodable {
        let external: [String: Bool]

        var phoneEnabled: Bool { external["phone"] == true }
    }

    private static let accountPhoneKey = "registration_phone"
    private static let recoveryKey = "auth.passwordRecoveryUserID"
    private static let callback = URL(string: "com.upsoledd.app://auth/callback")!
    private static let recoveryCallback = URL(string: "com.upsoledd.app://auth/recovery")!
    private static let confirmationCallback = URL(string: "com.upsoledd.app://auth/confirm")!
    private let client: SupabaseClient

    @Published private(set) var session: Session?
    @Published private(set) var isRestoringSession = true
    @Published private(set) var methods: AuthMethods?
    @Published private(set) var isVerifyingRecovery = false
    @Published private(set) var recoveryUserID: String? = UserDefaults.standard.string(forKey: recoveryKey)
    @Published var callbackNotice: String?
    @Published var lastErrorMessage: String?
    /// Foto de perfil del usuario con sesión iniciada (`profiles.avatar_url` o metadatos OAuth).
    @Published private(set) var profileAvatarImage: UIImage?
    @Published private(set) var isUploadingProfileAvatar = false
    /// Empresa del usuario autenticado (cargada desde `profiles.company_id` vía RPC).
    @Published private(set) var companyId: UUID?
    /// Organización del usuario autenticado (cargada desde `user_profiles.organization_id`).
    @Published private(set) var organizationId: UUID?

    private var authStateTask: Task<Void, Never>?
    private var profileAvatarTask: Task<Void, Never>?
    private var companyIdTask: Task<Void, Never>?
    private var organizationIdTask: Task<Void, Never>?
    private static let aiBlockedOrganizationIDs: Set<UUID> = [
        UUID(uuidString: "1d8bfc03-fa2b-419c-9f2a-bcce92651c5d")!,
    ]

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
        session = client.auth.currentSession
        isRestoringSession = session == nil
        startAuthStateListener()
        Task { await refreshSessionIfNeeded() }
        scheduleProfileAvatarLoad()
        scheduleCompanyIdLoad()
        scheduleOrganizationIdLoad()
    }

    deinit {
        authStateTask?.cancel()
        companyIdTask?.cancel()
        organizationIdTask?.cancel()
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var needsNewPassword: Bool {
        guard let session else { return false }
        return recoveryUserID == session.user.id.uuidString
    }

    var registrationPhone: String? {
        session?.user.userMetadata[Self.accountPhoneKey]?.stringValue
    }

    var needsRegistrationPhone: Bool {
        guard let user = session?.user, !OnboardingStore.isDone(user.id.uuidString) else { return false }
        guard user.phoneConfirmedAt == nil else { return false }
        let provider = user.appMetadata["provider"]?.stringValue
        let isSocial = ["google", "apple", "custom:stockx"].contains(provider ?? "")
        guard registrationPhone != nil || isSocial else { return false }
        return registrationPhone == nil || methods?.phoneEnabled != false
    }

    var userEmail: String? {
        session?.user.email
    }

    var userDisplayName: String {
        if let email = userEmail, !email.isEmpty {
            return email
        }
        return "Invitado"
    }

    /// Nombre corto para saludo (parte local del correo, legible).
    var shortGreetingName: String {
        guard let email = userEmail, !email.isEmpty else { return "Invitado" }
        guard let at = email.firstIndex(of: "@") else { return email }
        let local = String(email[..<at])
        let parts = local.split { $0 == "." || $0 == "_" || $0 == "-" }
        let words = parts.map { String($0).capitalized }.filter { !$0.isEmpty }
        if words.isEmpty { return "Invitado" }
        return words.joined(separator: " ")
    }

    var userInitials: String {
        let name = shortGreetingName
        let parts = name.split(separator: " ")
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        if let f = name.first { return String(f).uppercased() }
        return "?"
    }

    var canAccessIASection: Bool {
        guard let organizationId else { return true }
        return !Self.aiBlockedOrganizationIDs.contains(organizationId)
    }

    var canAccessTeamLocationSection: Bool {
        guard let organizationId else { return true }
        return !Self.aiBlockedOrganizationIDs.contains(organizationId)
    }

    private func startAuthStateListener() {
        authStateTask?.cancel()
        authStateTask = Task { [client] in
            for await (event, newSession) in client.auth.authStateChanges {
                await MainActor.run {
                    if event == .passwordRecovery, let newSession {
                        self.requireNewPassword(for: newSession)
                    }
                    self.session = newSession
                    self.isRestoringSession = false
                    self.scheduleProfileAvatarLoad()
                    self.scheduleCompanyIdLoad()
                    self.scheduleOrganizationIdLoad()
                }
            }
        }
    }

    private func refreshSessionIfNeeded() async {
        defer { isRestoringSession = false }
        do {
            let s = try await client.auth.session
            await MainActor.run {
                self.session = s
                self.scheduleProfileAvatarLoad()
                self.scheduleCompanyIdLoad()
                self.scheduleOrganizationIdLoad()
            }
        } catch {
            await MainActor.run {
                self.session = client.auth.currentSession
                self.scheduleProfileAvatarLoad()
                self.scheduleCompanyIdLoad()
                self.scheduleOrganizationIdLoad()
            }
        }
    }

    /// Carga el `company_id` del usuario autenticado desde Supabase (`profiles.company_id`).
    private func scheduleCompanyIdLoad() {
        companyIdTask?.cancel()
        guard session != nil else {
            companyId = nil
            return
        }
        companyIdTask = Task {
            let cid = await VehiclesService.fetchMyCompanyId()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.companyId = cid
            }
        }
    }

    /// Carga el `organization_id` del usuario autenticado desde Supabase (`user_profiles.organization_id`).
    private func scheduleOrganizationIdLoad() {
        organizationIdTask?.cancel()
        guard session != nil else {
            organizationId = nil
            return
        }
        organizationIdTask = Task {
            let oid = await VehiclesService.fetchMyOrganizationId()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.organizationId = oid
            }
        }
    }

    private func scheduleProfileAvatarLoad() {
        profileAvatarTask?.cancel()
        guard let session else {
            profileAvatarImage = nil
            return
        }

        let user = session.user
        let userId = user.id
        let token = session.accessToken

        profileAvatarTask = Task { [client] in
            let ref = await UserProfileService.resolveAvatarRef(user: user, client: client)
            guard !Task.isCancelled else { return }
            let image = await UserProfileService.loadProfileAvatarImage(
                avatarRef: ref,
                userId: userId,
                client: client,
                accessToken: token
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.session?.user.id == userId else { return }
                self.profileAvatarImage = image
            }
        }
    }

    func uploadProfileAvatar(_ image: UIImage) async {
        guard let session else {
            lastErrorMessage = UserProfileService.AvatarUploadError.notAuthenticated.localizedDescription
            return
        }
        guard let jpeg = UserProfileService.prepareAvatarJPEG(from: image) else {
            lastErrorMessage = UserProfileService.AvatarUploadError.invalidImage.localizedDescription
            return
        }

        isUploadingProfileAvatar = true
        lastErrorMessage = nil
        defer { isUploadingProfileAvatar = false }

        let userId = session.user.id
        do {
            let path = try await UserProfileService.uploadProfileAvatar(
                jpegData: jpeg,
                userId: userId,
                client: client
            )
            if let preview = UIImage(data: jpeg) {
                profileAvatarImage = preview
                ImageCacheService.shared.store(
                    preview,
                    forKey: "profileAvatar:\(userId.uuidString.lowercased()):\(path)"
                )
            }
            scheduleProfileAvatarLoad()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        lastErrorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Enter your email and password."
            return
        }
        do {
            let s = try await client.auth.signIn(email: trimmed, password: password)
            session = s
            scheduleProfileAvatarLoad()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshMethods() async {
        let settingsURL = SupabaseClientProvider.supabaseURL.appendingPathComponent("auth/v1/settings")
        var request = URLRequest(url: settingsURL, timeoutInterval: 8)
        request.setValue(SupabaseClientProvider.anonKey, forHTTPHeaderField: "apikey")
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let loaded = try? JSONDecoder().decode(AuthMethods.self, from: data) {
            methods = loaded
        }
    }

    func signIn(with provider: IdentityProvider) async {
        lastErrorMessage = nil
        if provider == .stockX {
            do {
                session = try await signInWithStockX()
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                lastErrorMessage = error.localizedDescription
            }
            return
        }

        let backendProvider: Provider = provider == .google ? .google : .apple
        await refreshMethods()
        guard let methods else {
            lastErrorMessage = "Could not check sign-in availability. Try again."
            return
        }
        guard methods.external[backendProvider.rawValue] == true else {
            lastErrorMessage = "Sign-in with \(provider.rawValue) has not been enabled yet."
            return
        }
        do {
            session = try await client.auth.signInWithOAuth(provider: backendProvider, redirectTo: Self.callback)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func signInWithStockX() async throws -> Session {
        // This SDK version accepts built-in provider names. Reuse its PKCE setup and
        // send Supabase's custom OAuth identifier in the documented provider parameter.
        let sdkURL = try client.auth.getOAuthSignInURL(provider: .google, redirectTo: Self.callback)
        guard var components = URLComponents(url: sdkURL, resolvingAgainstBaseURL: false) else {
            throw StockXSignInError.providerUnavailable
        }
        let parameters = (components.queryItems ?? []).filter { $0.name != "provider" }
        components.queryItems = parameters + [URLQueryItem(name: "provider", value: "custom:stockx")]
        guard let authorizeURL = components.url else { throw StockXSignInError.providerUnavailable }

        let transport = URLSession(configuration: .ephemeral, delegate: AuthNoRedirect(), delegateQueue: nil)
        defer { transport.finishTasksAndInvalidate() }
        var request = URLRequest(url: authorizeURL, timeoutInterval: 10)
        request.setValue(SupabaseClientProvider.anonKey, forHTTPHeaderField: "apikey")
        let (_, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
              let destination = http.value(forHTTPHeaderField: "Location"),
              let stockXURL = URL(string: destination), stockXURL.scheme == "https",
              stockXURL.host == "accounts.stockx.com" else { throw StockXSignInError.providerUnavailable }

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?.keyWindow
        else { throw StockXSignInError.providerUnavailable }

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let presenter = StockXAuthPresentation(window: window)
            let web = ASWebAuthenticationSession(url: stockXURL, callbackURLScheme: Self.callback.scheme) { [presenter] url, error in
                _ = presenter
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? StockXSignInError.providerUnavailable)
                }
            }
            web.presentationContextProvider = presenter
            web.start()
        }
        guard callbackURL.scheme == Self.callback.scheme, callbackURL.host == Self.callback.host,
              callbackURL.path == Self.callback.path else { throw StockXSignInError.providerUnavailable }
        return try await client.auth.session(from: callbackURL)
    }

    func signUp(email: String, password: String, phone: String) async -> String? {
        lastErrorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await client.auth.signUp(
                email: trimmed,
                password: password,
                data: [Self.accountPhoneKey: .string(phone)],
                redirectTo: Self.confirmationCallback
            )
            if let s = response.session {
                session = s
                scheduleProfileAvatarLoad()
            } else {
                return "Check your email and confirm your account. Then sign in to start onboarding."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        return nil
    }

    func saveRegistrationPhone(_ phone: String) async -> PhoneEnrollment {
        lastErrorMessage = nil
        await refreshMethods()
        guard let methods else {
            lastErrorMessage = "Could not check phone verification. Try again."
            return .failed
        }

        do {
            let attributes = UserAttributes(
                phone: methods.phoneEnabled ? phone : nil,
                data: [Self.accountPhoneKey: .string(phone)]
            )
            let user = try await client.auth.update(user: attributes)
            session = client.auth.currentSession
            return methods.phoneEnabled && user.phoneConfirmedAt == nil ? .needsCode : .saved
        } catch {
            lastErrorMessage = error.localizedDescription
            return .failed
        }
    }

    func confirmRegistrationPhone(_ phone: String, code: String) async {
        lastErrorMessage = nil
        do {
            _ = try await client.auth.verifyOTP(phone: phone, token: code, type: .phoneChange)
            session = client.auth.currentSession
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        lastErrorMessage = nil
        do {
            try await client.auth.signOut()
            profileAvatarTask?.cancel()
            companyIdTask?.cancel()
            organizationIdTask?.cancel()
            profileAvatarImage = nil
            companyId = nil
            organizationId = nil
            session = nil
            clearRecovery()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func sendRecoveryEmail(_ email: String) async -> Bool {
        lastErrorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await client.auth.resetPasswordForEmail(trimmed, redirectTo: Self.recoveryCallback)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func sendRecoverySMS(_ phone: String) async -> Bool {
        lastErrorMessage = nil
        do {
            try await client.auth.signInWithOTP(phone: phone, shouldCreateUser: false)
            return true
        } catch let error as AuthError where ["user_not_found", "signup_disabled", "otp_disabled"].contains(error.errorCode.rawValue) {
            // Keep the response the same for registered and unregistered numbers.
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func confirmRecoverySMS(_ phone: String, code: String) async {
        await exchangeRecovery {
            try await self.client.auth.verifyOTP(phone: phone, token: code, type: .sms).session
        }
    }

    func confirmRecoveryLink(_ input: String) async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let link = URLComponents(string: value),
              link.scheme == "https", link.host == SupabaseClientProvider.supabaseURL.host,
              link.user == nil, link.path == "/auth/v1/verify",
              (link.queryItems ?? []).contains(where: { $0.name == "type" && $0.value == "recovery" }),
              let token = link.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty else {
            lastErrorMessage = "Paste the original recovery link from your email."
            return
        }
        await exchangeRecovery {
            try await self.client.auth.verifyOTP(tokenHash: token, type: .recovery).session
        }
    }

    func handleCallback(_ url: URL) async {
        guard url.scheme == Self.callback.scheme, url.host == Self.callback.host,
              url.user == nil, url.port == nil else { return }
        switch url.path {
        case Self.recoveryCallback.path:
            await exchangeRecovery { try await self.client.auth.session(from: url) }
            if let message = lastErrorMessage { callbackNotice = message }
        case Self.callback.path, Self.confirmationCallback.path:
            do {
                session = try await client.auth.session(from: url)
            } catch {
                callbackNotice = "The link is expired or was opened on a different device. Request a new link or sign in."
            }
        default:
            return
        }
    }

    func changeRecoveredPassword(_ password: String) async {
        guard needsNewPassword else { return }
        lastErrorMessage = nil
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
            session = client.auth.currentSession
            clearRecovery()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func cancelRecovery() async {
        lastErrorMessage = nil
        // The SDK removes the local session before sending logout to the server.
        try? await client.auth.signOut(scope: .local)
        session = client.auth.currentSession
        clearRecovery()
    }

    private func exchangeRecovery(_ exchange: () async throws -> Session?) async {
        guard !isVerifyingRecovery else { return }
        lastErrorMessage = nil
        isVerifyingRecovery = true
        defer { isVerifyingRecovery = false }
        do {
            guard let recovered = try await exchange() else {
                lastErrorMessage = "The code or link is invalid."
                return
            }
            requireNewPassword(for: recovered)
            session = recovered
        } catch {
            lastErrorMessage = "The code or link is invalid or has expired."
        }
    }

    private func requireNewPassword(for session: Session) {
        recoveryUserID = session.user.id.uuidString
        UserDefaults.standard.set(recoveryUserID, forKey: Self.recoveryKey)
    }

    private func clearRecovery() {
        recoveryUserID = nil
        UserDefaults.standard.removeObject(forKey: Self.recoveryKey)
    }
}

private enum StockXSignInError: LocalizedError {
    case providerUnavailable

    var errorDescription: String? {
        "StockX sign-in requires an enabled StockX integration. You can sign in with email."
    }
}

private final class AuthNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
private final class StockXAuthPresentation: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}
