import SwiftUI
import UIKit

// MARK: - Internacionalización (ES/EN)

enum AppLanguage: String, CaseIterable {
    case spanish = "es"
    case english = "en"

    var displayName: String {
        switch self {
        case .spanish: return "Español"
        case .english: return "English"
        }
    }

    var shortName: String {
        switch self {
        case .spanish: return "ES"
        case .english: return "EN"
        }
    }

    var flag: String {
        switch self {
        case .spanish: return "🇪🇸"
        case .english: return "🇬🇧"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .spanish: return "es_ES"
        case .english: return "en_US"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
}

/// Pequeño sistema de traducciones in-memory. Las vistas observan
/// `@AppStorage("appLanguage")` y se redibujan al cambiar el idioma.
enum L10n {
    static func tr(_ key: String, lang: AppLanguage) -> String {
        let dict = lang == .spanish ? es : en
        return dict[key] ?? (en[key] ?? key)
    }

    static let es: [String: String] = [
        // Common
        "common.ok": "OK",
        "common.close": "Cerrar",
        "common.send": "Enviar",
        "common.sort": "Ordenar",
        "common.filters": "Filtros",
        "common.description": "Descripción",

        // Tabs
        "tab.dashboard": "Dashboard",
        "tab.closet": "Clóset",
        "tab.collection": "Colección",
        "tab.soled": "Vendidos",
        "tab.pricing": "Precios",
        "tab.settings": "Ajustes",

        // Settings — generic
        "settings.title": "Ajustes",
        "settings.search": "Buscar",
        "settings.personalInfo": "Información personal",
        "settings.sellerAccounts": "Mi cuenta de vendedor",
        "settings.platforms": "Plataformas",
        "settings.closetAvatars": "Clóset y avatares",
        "settings.preferences": "Preferencias",
        "settings.advanced": "Avanzado",
        "settings.language": "Idioma",
        "settings.role": "Rol",
        "settings.admin": "Admin",
        "settings.email": "Email",
        "settings.phone": "Teléfono",
        "settings.size": "Talla",
        "settings.currency": "Divisa",
        "settings.notifications": "Notificaciones",
        "settings.teamAlerts": "Avisos del equipo y tareas",
        "settings.teamAlertsDesc": "Recibe push cuando te envíen un mensaje directo, aviso de grupo o una tarea. Desactívalo si no quieres notificaciones en este dispositivo.",
        "settings.development": "Desarrollo",
        "settings.imageDiagnostics": "Diagnóstico de imágenes (consola Xcode)",
        "settings.imageDiagnosticsDesc": "Al cargar la colección se imprimen columnas JSON, rutas Storage, user_id y cuántos slots ve la UI. Abre la consola con ⌘⇧Y y tira hacia abajo para refrescar el listado.",
        "settings.logout": "Cerrar sesión",
        "settings.version": "Versión",
        "settings.connected": "Conectado",
        "settings.connect": "Conectar",
        "settings.noSession": "Sin sesión",
        "settings.referencePhoto": "Foto de referencia",
        "settings.myFace": "Mi rostro",
        "settings.myFaceDesc": "Opcional: mejora cómo el avatar se parece a ti al generar looks (solo en este dispositivo).",
        "settings.notificationsTitle": "Notificaciones",
        "settings.marketplacesGalleryDesc": "Marcas disponibles para conectar.",

        // Dashboard
        "dashboard.totalStock": "Valor total del stock",
        "dashboard.sneakersInStock": "Sneakers en stock",
        "dashboard.sold": "Vendidas",
        "dashboard.heroTitle": "Tu imperio de\nsneakers en uno.",
        "dashboard.heroCTA": "Explorar ahora",
        "dashboard.new": "NUEVO",
        "dashboard.quickAdd": "Añadir",
        "dashboard.quickInvoices": "Facturas",
        "dashboard.quickStats": "Stats",
        "dashboard.quickMore": "Más",
        "dashboard.lastSale": "Última operación",
        "dashboard.viewAll": "Ver todas",
        "dashboard.noItems": "Sin artículos en stock",
        "dashboard.item": "Artículo",
        "dashboard.whereToPublish": "Dónde publicar",
        "dashboard.whereToPublishSub": "Conecta tus tiendas y publica con 1 toque",

        // Cars / Collection
        "cars.searchPrompt": "¿Qué estás buscando?",
        "cars.results": "sneakers",
        "cars.loadingMore": "Cargando más sneakers…",
        "cars.size": "Talla",
        "cars.empty": "Sin resultados",
        "cars.emptyFootnote": "Prueba a limpiar filtros o cambiar la búsqueda.",
        "cars.editSheetTitle": "Editar artículo",
        "cars.editSheetIntroTitle": "Edita los datos del artículo",
        "cars.editSheetIntroSubtitle": "Puedes modificar campos manualmente o usar el micrófono de arriba.",
        "cars.listening": "Escuchando… toca el micrófono para terminar",
        "cars.fieldBrand": "Marca",
        "cars.fieldModel": "Modelo",
        "cars.fieldYear": "Año",
        "cars.fieldPlate": "Referencia",
        "cars.fieldPrice": "Precio",
        "cars.fieldMileage": "Stock",
        "cars.fieldPower": "SKU",
        "cars.fieldFuel": "Estado",
        "cars.fieldTransmission": "Canal",
        "cars.fieldColor": "Color",
        "cars.fieldDgt": "Etiqueta",
        "cars.saving": "Guardando...",
        "cars.saveChanges": "Guardar cambios",
        "cars.startDictation": "Iniciar dictado",
        "cars.stopDictation": "Detener dictado",
        "cars.enableMic": "Activa micrófono en Ajustes para dictar.",
        "cars.enableSpeech": "Activa reconocimiento de voz en Ajustes.",
        "cars.dictationApplied": "Dictado aplicado. Revisa los campos antes de guardar.",
        "cars.invalidYear": "Año no válido.",

        // Sold
        "sold.searchPrompt": "Buscar venta",
        "sold.thisPeriod": "Vendido este periodo",
        "sold.sales": "Ventas",
        "sold.profit": "Beneficio",
        "sold.filterAll": "Todas",
        "sold.filterMonth": "Este mes",
        "sold.filterTop": "Top beneficio",
        "sold.emptyTitle": "Sin ventas",
        "sold.emptyDesc": "No hay ventas registradas en este periodo.",
        "sold.today": "Hoy",
        "sold.yesterday": "Ayer",
        "sold.daysAgo": "Hace %@ días",
        "sold.oneWeekAgo": "Hace 1 semana",
        "sold.weeksAgo": "Hace %@ semanas",
        "sold.monthsAgo": "Hace %@ meses",

        // Pricing
        "pricing.title": "Pricing Tier",
        "pricing.placeholder": "El diseño de chat con IA ya no aparece aquí.",

        // Closet
        "closet.title": "Mi clóset",
        "closet.empty": "Tus prendas guardadas aparecerán aquí. Pulsa + para analizar fotos con IA.",
        "closet.add": "Añadir",

        // Price compare (comparativa de mercado)
        "price.compareTitle": "Comparativa de mercado",
        "price.compareSubtitle": "Precio medio en las principales plataformas",
        "price.lookup": "Buscar precio",
        "price.searching": "Buscando precio…",
        "price.notFound": "Sin coincidencias",
        "price.avg": "Precio medio",
        "price.min": "Mínimo",
        "price.max": "Máximo",
        "price.lastSales": "Últimas ventas",
        "price.source": "Fuente",
        "price.refresh": "Actualizar",

        // Login / Welcome
        "auth.welcome": "Bienvenido",
        "auth.subtitle": "Tu imperio de sneakers empieza aquí.",
        "auth.signInTitle": "Iniciar sesión",
        "auth.signInSubtitle": "Accede a tu cuenta de UPSOLED.",
        "auth.welcomeBack": "Bienvenido de nuevo",
        "auth.createYourAccount": "Crea tu cuenta",
        "auth.email": "Correo electrónico",
        "auth.password": "Contraseña",
        "auth.forgot": "¿Olvidaste tu contraseña?",
        "auth.signIn": "Iniciar sesión",
        "auth.alreadyHaveAccount": "¿Ya tienes cuenta?",
        "auth.orContinue": "o continúa con",
        "auth.continueApple": "Continuar con Apple",
        "auth.continueGoogle": "Continuar con Google",
        "auth.noAccount": "¿No tienes cuenta?",
        "auth.signUp": "Regístrate",
        "auth.createAccount": "Crea tu cuenta",
        "auth.startCollection": "Empieza a construir tu colección.",
        "auth.signInToEmpire": "Inicia sesión para acceder a tu imperio de sneakers.",
        "auth.helpTitle": "Ayuda",
        "auth.helpBody": "Próximamente podrás obtener ayuda desde aquí.",
        "auth.comingSoonTitle": "Próximamente",
        "auth.comingSoonBody": "Esta opción estará disponible en una próxima actualización.",
        "auth.resetAccess": "Recuperar acceso",
        "auth.connecting": "Conectando…",
    ]

    static let en: [String: String] = [
        // Common
        "common.ok": "OK",
        "common.close": "Close",
        "common.send": "Send",
        "common.sort": "Sort",
        "common.filters": "Filters",
        "common.description": "Description",

        // Tabs
        "tab.dashboard": "Dashboard",
        "tab.closet": "Closet",
        "tab.collection": "Collection",
        "tab.soled": "Sold",
        "tab.pricing": "Pricing",
        "tab.settings": "Settings",

        // Settings
        "settings.title": "Settings",
        "settings.search": "Search",
        "settings.personalInfo": "Personal information",
        "settings.sellerAccounts": "My seller account",
        "settings.platforms": "Platforms",
        "settings.closetAvatars": "Closet and avatars",
        "settings.preferences": "Preferences",
        "settings.advanced": "Advanced",
        "settings.language": "Language",
        "settings.role": "Role",
        "settings.admin": "Admin",
        "settings.email": "Email",
        "settings.phone": "Phone",
        "settings.size": "Size",
        "settings.currency": "Currency",
        "settings.notifications": "Notifications",
        "settings.teamAlerts": "Team alerts & tasks",
        "settings.teamAlertsDesc": "Receive push notifications for direct messages, group alerts or tasks. Disable if you don't want notifications on this device.",
        "settings.development": "Development",
        "settings.imageDiagnostics": "Image diagnostics (Xcode console)",
        "settings.imageDiagnosticsDesc": "When loading the collection, JSON columns, Storage paths, user_id and slot counts are printed. Open the console with ⌘⇧Y and pull down to refresh.",
        "settings.logout": "Log out",
        "settings.version": "Version",
        "settings.connected": "Connected",
        "settings.connect": "Connect",
        "settings.noSession": "No session",
        "settings.referencePhoto": "Reference photo",
        "settings.myFace": "My face",
        "settings.myFaceDesc": "Optional: improves how the avatar looks like you when generating outfits (only on this device).",
        "settings.notificationsTitle": "Notifications",
        "settings.marketplacesGalleryDesc": "Available brands to connect.",

        // Dashboard
        "dashboard.totalStock": "Total stock value",
        "dashboard.sneakersInStock": "Sneakers in stock",
        "dashboard.sold": "Sold",
        "dashboard.heroTitle": "Your sneaker empire,\nall in one place.",
        "dashboard.heroCTA": "Explore now",
        "dashboard.new": "NEW",
        "dashboard.quickAdd": "Add",
        "dashboard.quickInvoices": "Invoices",
        "dashboard.quickStats": "Stats",
        "dashboard.quickMore": "More",
        "dashboard.lastSale": "Last sale",
        "dashboard.viewAll": "View all",
        "dashboard.noItems": "No items in stock",
        "dashboard.item": "Item",
        "dashboard.whereToPublish": "Where to list",
        "dashboard.whereToPublishSub": "Connect your stores and list with 1 tap",

        // Cars / Collection
        "cars.searchPrompt": "What are you looking for?",
        "cars.results": "sneakers",
        "cars.loadingMore": "Loading more sneakers…",
        "cars.size": "Size",
        "cars.empty": "No results",
        "cars.emptyFootnote": "Try clearing filters or changing the search.",
        "cars.editSheetTitle": "Edit item",
        "cars.editSheetIntroTitle": "Edit item details",
        "cars.editSheetIntroSubtitle": "You can edit fields manually or use the microphone above.",
        "cars.listening": "Listening… tap the microphone to finish",
        "cars.fieldBrand": "Brand",
        "cars.fieldModel": "Model",
        "cars.fieldYear": "Year",
        "cars.fieldPlate": "Reference",
        "cars.fieldPrice": "Price",
        "cars.fieldMileage": "Stock",
        "cars.fieldPower": "SKU",
        "cars.fieldFuel": "Condition",
        "cars.fieldTransmission": "Channel",
        "cars.fieldColor": "Color",
        "cars.fieldDgt": "Label",
        "cars.saving": "Saving...",
        "cars.saveChanges": "Save changes",
        "cars.startDictation": "Start dictation",
        "cars.stopDictation": "Stop dictation",
        "cars.enableMic": "Enable microphone access in Settings to dictate.",
        "cars.enableSpeech": "Enable speech recognition in Settings.",
        "cars.dictationApplied": "Dictation applied. Review the fields before saving.",
        "cars.invalidYear": "Invalid year.",

        // Sold
        "sold.searchPrompt": "Search a sale",
        "sold.thisPeriod": "Sold this period",
        "sold.sales": "Sales",
        "sold.profit": "Profit",
        "sold.filterAll": "All",
        "sold.filterMonth": "This month",
        "sold.filterTop": "Top profit",
        "sold.emptyTitle": "No sales",
        "sold.emptyDesc": "There are no recorded sales in this period.",
        "sold.today": "Today",
        "sold.yesterday": "Yesterday",
        "sold.daysAgo": "%@ days ago",
        "sold.oneWeekAgo": "1 week ago",
        "sold.weeksAgo": "%@ weeks ago",
        "sold.monthsAgo": "%@ months ago",

        // Pricing
        "pricing.title": "Pricing Tier",
        "pricing.placeholder": "The AI chat design no longer appears here.",

        // Closet
        "closet.title": "My closet",
        "closet.empty": "Your saved items will appear here. Tap + to analyze photos with AI.",
        "closet.add": "Add",

        // Price compare
        "price.compareTitle": "Market comparison",
        "price.compareSubtitle": "Average price across major platforms",
        "price.lookup": "Lookup price",
        "price.searching": "Searching price…",
        "price.notFound": "No matches",
        "price.avg": "Average price",
        "price.min": "Minimum",
        "price.max": "Maximum",
        "price.lastSales": "Recent sales",
        "price.source": "Source",
        "price.refresh": "Refresh",

        // Tabs (closet missing in English)

        // Login / Welcome
        "auth.welcome": "Welcome",
        "auth.subtitle": "Your sneaker empire starts here.",
        "auth.signInTitle": "Sign in",
        "auth.signInSubtitle": "Access your UPSOLED account.",
        "auth.welcomeBack": "Welcome back",
        "auth.createYourAccount": "Create your account",
        "auth.email": "Email",
        "auth.password": "Password",
        "auth.forgot": "Forgot your password?",
        "auth.signIn": "Sign in",
        "auth.alreadyHaveAccount": "Already have an account?",
        "auth.orContinue": "or continue with",
        "auth.continueApple": "Continue with Apple",
        "auth.continueGoogle": "Continue with Google",
        "auth.noAccount": "Don't have an account?",
        "auth.signUp": "Sign up",
        "auth.createAccount": "Create your account",
        "auth.startCollection": "Start building your collection.",
        "auth.signInToEmpire": "Sign in to access your sneaker empire.",
        "auth.helpTitle": "Help",
        "auth.helpBody": "Help will be available here soon.",
        "auth.comingSoonTitle": "Coming soon",
        "auth.comingSoonBody": "This option will be available in a future update.",
        "auth.resetAccess": "Recover access",
        "auth.connecting": "Connecting…",
    ]
}

/// Wrapper para usar como `@AppStorage("appLanguage") var lang: AppLanguage`
extension AppLanguage: RawRepresentable {}

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel

    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    private var appLanguage: AppLanguage { AppLanguage(rawValue: appLanguageRaw) ?? .spanish }

    @State private var showClosetFaceSetup = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    profileHeroSection
                        .padding(.top, 8)

                    Group {
                        sectionTitle(L10n.tr("settings.language", lang: appLanguage))
                        languageSection
                    }

                    Group {
                        sectionTitle("OpenAI API")
                        openAIKeySection
                    }

                    Group {
                        sectionTitle(L10n.tr("settings.personalInfo", lang: appLanguage))
                        generalInfoSection
                    }

                    Group {
                        sectionTitle(L10n.tr("settings.sellerAccounts", lang: appLanguage))
                        sellerAccountsSection
                    }

                    Group {
                        sectionTitle(L10n.tr("settings.platforms", lang: appLanguage))
                        marketplaceLogosGallerySection
                    }

                    Group {
                        sectionTitle(L10n.tr("settings.closetAvatars", lang: appLanguage))
                        closetAvatarSection
                    }

                    if auth.isAuthenticated {
                        Group {
                            sectionTitle(L10n.tr("settings.preferences", lang: appLanguage))
                            notificationsSection
                        }
                    }

                    accountSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(minWidth: 0, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.light)
        .environment(\.dashboardLightSurface, true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showClosetFaceSetup) {
            FaceSetupView()
                .presentationDragIndicator(Visibility.visible)
        }
        .task(id: auth.session?.user.id) {
            guard let uid = auth.session?.user.id else { return }
            await settingsVM.loadNotifyTeamPush(
                client: SupabaseClientProvider.shared,
                userId: uid
            )
        }
    }

    // MARK: - Clóset (rostro para avatares Gemini)

    private var closetAvatarSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("settings.referencePhoto", lang: appLanguage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.50))

                Button {
                    showClosetFaceSetup = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.black.opacity(0.75))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("settings.myFace", lang: appLanguage))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.88))
                            Text(L10n.tr("settings.myFaceDesc", lang: appLanguage))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.50))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.35))
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Notificaciones

    private var notificationsSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("settings.notificationsTitle", lang: appLanguage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.50))

                Toggle(
                    isOn: Binding(
                        get: { settingsVM.notifyTeamPushEnabled },
                        set: { new in
                            settingsVM.notifyTeamPushEnabled = new
                            if let uid = auth.session?.user.id {
                                Task {
                                    await settingsVM.persistNotifyTeamPush(
                                        new,
                                        client: SupabaseClientProvider.shared,
                                        userId: uid
                                    )
                                }
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("settings.teamAlerts", lang: appLanguage))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Text(L10n.tr("settings.teamAlertsDesc", lang: appLanguage))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.50))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(PremiumAccent.tabActive)
            }
        }
    }

    // MARK: - Profile

    // Selector de idioma (ES/EN)
    private var languageSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                }

                Text(L10n.tr("settings.language", lang: appLanguage))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))

                Spacer(minLength: 8)

                // Segmented picker estilo capsule
                HStack(spacing: 4) {
                    ForEach(AppLanguage.allCases, id: \.self) { l in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                appLanguageRaw = l.rawValue
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(l.flag)
                                    .font(.system(size: 13))
                                Text(l.shortName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        appLanguage == l
                                            ? .white
                                            : Color.black.opacity(0.60)
                                    )
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(
                                        appLanguage == l
                                            ? AnyShapeStyle(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.30, green: 0.55, blue: 0.95),
                                                        Color(red: 0.14, green: 0.36, blue: 0.85),
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            : AnyShapeStyle(Color.clear)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background {
                    Capsule().fill(Color(red: 0.95, green: 0.96, blue: 0.99))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // OpenAI API key — para el servicio de comparativa de precio
    @AppStorage("openaiAPIKey") private var openaiAPIKey: String = ""
    @State private var openaiKeyDraft: String = ""
    @State private var openaiKeyRevealed: Bool = false

    private var openAIKeySection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.14))
                            .frame(width: 32, height: 32)
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("API key")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Text(openaiAPIKey.isEmpty
                             ? "Sin configurar · usando datos simulados"
                             : "Activa · sk-•••\(String(openaiAPIKey.suffix(4)))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(openaiAPIKey.isEmpty
                                ? Color.orange.opacity(0.85)
                                : Color(red: 0.18, green: 0.62, blue: 0.40))
                    }
                    Spacer(minLength: 0)

                    // Indicador estado
                    Circle()
                        .fill(openaiAPIKey.isEmpty
                            ? Color.orange.opacity(0.85)
                            : Color(red: 0.20, green: 0.70, blue: 0.45))
                        .frame(width: 8, height: 8)
                }

                HStack(spacing: 10) {
                    Group {
                        if openaiKeyRevealed {
                            TextField("sk-...", text: $openaiKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("sk-...", text: $openaiKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.95, green: 0.96, blue: 0.99))
                    }

                    Button {
                        openaiKeyRevealed.toggle()
                    } label: {
                        Image(systemName: openaiKeyRevealed ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.50))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        openaiAPIKey = openaiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    } label: {
                        Text("Guardar")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.30, green: 0.55, blue: 0.95),
                                            Color(red: 0.14, green: 0.36, blue: 0.85),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(openaiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(openaiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)

                    if !openaiAPIKey.isEmpty {
                        Button {
                            openaiAPIKey = ""
                            openaiKeyDraft = ""
                        } label: {
                            Text("Borrar")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.red.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule()
                                        .strokeBorder(Color.red.opacity(0.30), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }

                Text("Tu key se guarda solo en este dispositivo. Se usa para estimar precios de mercado con gpt-4o-mini.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.50))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .onAppear {
                if openaiKeyDraft.isEmpty { openaiKeyDraft = openaiAPIKey }
            }
        }
    }

    // Profile hero — avatar grande centrado + nombre + email + rol
    private var profileHeroSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    if let photo = auth.profileAvatarImage {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.30, green: 0.55, blue: 0.95),
                                        Color(red: 0.14, green: 0.36, blue: 0.85),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(String(auth.userDisplayName.prefix(1)).uppercased())
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 108, height: 108)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.55, blue: 0.95).opacity(0.50),
                                    Color(red: 0.14, green: 0.36, blue: 0.85).opacity(0.15),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
                .shadow(color: Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.25), radius: 18, y: 8)

                // Edit camera button
                Button {} label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.30, green: 0.55, blue: 0.95),
                                        Color(red: 0.14, green: 0.36, blue: 0.85),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle().strokeBorder(Color.white, lineWidth: 2.5)
                            }
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.40), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 4) {
                Text(auth.userDisplayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .multilineTextAlignment(.center)

                Text(auth.session?.user.email ?? L10n.tr("settings.noSession", lang: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // Rol pill
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(L10n.tr("settings.admin", lang: appLanguage).uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                }
                .foregroundStyle(Color(red: 0.18, green: 0.40, blue: 0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.12))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Título de sección estilo iOS Settings
    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.black.opacity(0.48))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // Información personal — lista de rows
    private var generalInfoSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 0) {
            VStack(spacing: 0) {
                infoRow(icon: "person.fill", iconTint: Color(red: 0.20, green: 0.45, blue: 0.85), label: L10n.tr("settings.role", lang: appLanguage), value: L10n.tr("settings.admin", lang: appLanguage))
                infoDivider
                infoRow(icon: "envelope.fill", iconTint: Color(red: 0.20, green: 0.45, blue: 0.85), label: L10n.tr("settings.email", lang: appLanguage), value: auth.session?.user.email ?? "—")
                infoDivider
                infoRow(icon: "phone.fill", iconTint: Color(red: 0.20, green: 0.70, blue: 0.45), label: L10n.tr("settings.phone", lang: appLanguage), value: "+34 600 000 000")
                infoDivider
                infoRow(icon: "shoeprints.fill", iconTint: Color(red: 0.95, green: 0.55, blue: 0.20), label: L10n.tr("settings.size", lang: appLanguage), value: "EU 42 · US 9")
                infoDivider
                infoRow(icon: "dollarsign.circle.fill", iconTint: Color(red: 0.55, green: 0.30, blue: 0.85), label: L10n.tr("settings.currency", lang: appLanguage), value: "$")
            }
            .padding(.vertical, 4)
        }
    }

    private var infoDivider: some View {
        Divider()
            .padding(.leading, 56)
            .padding(.trailing, 16)
    }

    private func infoRow(icon: String, iconTint: Color, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(iconTint.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(iconTint)
            }

            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.80)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // Cuentas de vendedor — lista de plataformas con insignia estilizada y estado
    private var sellerAccountsSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 0) {
            VStack(spacing: 0) {
                sellerRow(name: "StockX", connected: true)
                infoDivider
                sellerRow(name: "GOAT", connected: true)
                infoDivider
                sellerRow(name: "Grailed", connected: false)
                infoDivider
                sellerRow(name: "eBay", connected: false)
                infoDivider
                sellerRow(name: "Flight Club", connected: false)
                infoDivider
                sellerRow(name: "Stadium Goods", connected: false)
            }
            .padding(.vertical, 4)
        }
    }

    /// Todas las referencias visuales de marketplace en rejilla (mismo estilo que en la lista anterior).
    private var marketplaceLogosGallerySection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("settings.marketplacesGalleryDesc", lang: appLanguage))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 12
                ) {
                    ForEach(MarketplacePlatformDisplay.allCases, id: \.rawValue) { platform in
                        VStack(spacing: 8) {
                            StylizedMarketplaceLogo(brand: platform.rawValue)
                                .frame(width: 54, height: 54)

                            Text(platform.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.82))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func sellerRow(name: String, connected: Bool) -> some View {
        HStack(spacing: 14) {
            StylizedMarketplaceLogo(brand: name)
                .frame(width: 36, height: 36)

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))

            Spacer(minLength: 8)

            if connected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(L10n.tr("settings.connected", lang: appLanguage))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
            } else {
                Text(L10n.tr("settings.connect", lang: appLanguage))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Cuenta

    private var accountSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                Button {
                    Task { await auth.signOut() }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.10))
                                .frame(width: 32, height: 32)
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.red.opacity(0.92))
                        }
                        Text(L10n.tr("settings.logout", lang: appLanguage))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Acerca de

    private var aboutSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "info.circle.fill",
                    iconColor: PremiumAccent.tabActive,
                    title: L10n.tr("settings.version", lang: appLanguage)
                ) {
                    Text("\(settingsVM.appVersion) (\(settingsVM.buildNumber))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.50))
                }
            }
        }
    }

    // MARK: - Helpers

    private func settingsRow<Trailing: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.85))

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AuthViewModel())
}
