import PhotosUI
import SwiftUI
import UIKit

// MARK: - Localization (English)

enum L10n {
    static func tr(_ key: String) -> String {
        strings[key] ?? key
    }

    static let strings: [String: String] = [
        // Common
        "common.ok": "OK",
        "common.close": "Close",
        "common.send": "Send",
        "common.sort": "Sort",
        "common.filters": "Filters",
        "common.description": "Description",

        // Tabs
        "tab.dashboard": "Home",
        "tab.closet": "Your stock",
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
        "settings.profilePhoto": "Profile photo",
        "settings.profilePhotoPrompt": "Update your profile picture",
        "settings.profilePhotoTake": "Take photo",
        "settings.profilePhotoLibrary": "Choose from library",
        "settings.profilePhotoUploading": "Uploading…",
        "settings.profilePhotoFailed": "Could not upload profile photo.",
        "settings.referencePhoto": "Reference photo",
        "settings.myFace": "My face",
        "settings.myFaceDesc": "Optional: improves how the avatar looks like you when generating outfits (only on this device).",
        "settings.notificationsTitle": "Notifications",
        "settings.marketplacesGalleryDesc": "Available brands to connect.",
        "settings.goatSignIn": "Sign in",
        "settings.goatSignInTitle": "Connect your GOAT seller account",
        "settings.goatSignInSubtitle": "Use your Alias seller email and password. Your session stays on this device.",
        "settings.goatSigningIn": "Signing in…",
        "settings.goatDisconnect": "Disconnect GOAT",
        "settings.goatMissingToken": "Add GOAT_API_TOKEN in DeveloperSettings.local.xcconfig (CommercialGoatAPI provider token).",
        "settings.goatValidating": "Checking connection…",
        "settings.openAI": "OpenAI API",
        "settings.openAIKeyTitle": "API key",
        "settings.openAIKeyMissing": "Not configured · using simulated data",
        "settings.openAIKeyActive": "Active · sk-•••%@",
        "settings.openAIKeySave": "Save",
        "settings.openAIKeyClear": "Clear",
        "settings.openAIKeyHint": "Your key is stored only on this device. It is used to estimate market prices with gpt-4o-mini.",

        // Dashboard
        "dashboard.totalStock": "Total stock value",
        "dashboard.sneakersInStock": "Sneakers in stock",
        "dashboard.sold": "Sold",
        "dashboard.heroTitle": "Your sneaker empire,\nall in one place.",
        "dashboard.heroCTA": "See your stock",
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
        "sold.emptyTitle": "No sales yet",
        "sold.emptyDesc": "You don't have any sales in this period.",
        "sold.today": "Today",
        "sold.yesterday": "Yesterday",
        "sold.daysAgo": "%@ days ago",
        "sold.oneWeekAgo": "1 week ago",
        "sold.weeksAgo": "%@ weeks ago",
        "sold.monthsAgo": "%@ months ago",
        "sold.markSold": "Mark as sold",
        "sold.markSoldConfirmTitle": "Mark as sold?",
        "sold.markSoldConfirmMessage": "This item will move to Sold and disappear from your active stock.",
        "sold.markSoldAction": "Mark sold",
        "sold.markedSoldToast": "Item moved to Sold.",
        "sold.undoSold": "Move back to stock",
        "sold.sectionSold": "Sold",
        "sold.sectionRemoved": "Previously removed",
        "sold.removedEmptyTitle": "No removed items",
        "sold.removedEmptyDesc": "Items you discontinue will appear here. You can restore them or delete them permanently.",
        "sold.restoreToStock": "Restore to stock",
        "sold.deletePermanently": "Delete permanently",
        "sold.deletePermanentlyConfirm": "Delete this item forever? Photos on this device will be erased.",
        "sold.removedReasonDiscontinued": "Discontinued",
        "sold.removedToast": "Moved to Previously removed.",
        "sold.restoredToast": "Item restored to your stock.",
        "sold.removalDialogTitle": "Remove this item?",
        "sold.removalDialogMessage": "Did you sell it, or are you removing it from your inventory?",
        "sold.removalBulkTitle": "Remove selected items?",
        "sold.removalBulkMessage": "Tell us why you're removing these items from active stock.",
        "sold.removalSoldAction": "I sold it",
        "sold.removalDiscontinuedAction": "Discontinuing — remove from stock",
        "sold.removalSoldToast": "Moved to Sold.",
        "closet.removeItem": "Remove item",

        // Pricing
        "pricing.title": "Pricing Tier",
        "pricing.placeholder": "The AI chat design no longer appears here.",

        // Closet
        "closet.title": "Your stock",
        "closet.myLooks": "My looks",
        "closet.segmentProducts": "Products",
        "closet.segmentLooks": "Looks",
        "closet.looksEmpty": "No saved looks yet. Combine items and generate an avatar to see them here.",
        "closet.empty": "Your saved items will appear here. Tap + to analyze photos with AI.",
        "closet.add": "Add",
        "closet.welcomeGreeting": "Welcome, %@!",
        "closet.startTitle": "Start with your stock.",
        "closet.startSubtitle": "Upload photos of your product or outfit — each item can reach studio polish.",
        "closet.progressGoalIntro": "Add five products to your stock to finish the tutorial.",
        "closet.progressGreatRemainingOne": "You're one product away from finishing the tutorial.",
        "closet.progressGreatRemainingPlural": "Add %lld more products to your stock to finish the tutorial.",
        "closet.addWide": "+ Add",
        "closet.starterReminderPartial": "Keep using the tab bar + or '+ Add' until you have five products in your stock.",
        "closet.addSheetTitle": "Add to stock",
        "closet.addSheetPhotoHint": "📷 Choose photos for your stock",
        "closet.searchPrompt": "Search by brand, color, SKU…",
        "closet.scanBarcode": "Scan barcode or QR",
        "closet.scanHint": "The barcode must fit entirely inside the frame.",
        "closet.scanSuccess": "Scan successful!",
        "closet.scanBuyLabel": "Buy / bid",
        "closet.scanSellLabel": "Sell / offer",
        "closet.scanViewInStock": "View in your stock",
        "closet.layoutGrid": "Grid view",
        "closet.layoutList": "List view",
        "closet.searchEmpty": "No items match your search.",

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

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var goatVM: GoatAccountViewModel

    @State private var showClosetFaceSetup = false
    @State private var showGoatConnect = false
    @State private var showProfilePhotoSheet = false

    @AppStorage("openaiAPIKey") private var openaiAPIKey: String = ""
    @State private var openaiKeyDraft: String = ""
    @State private var openaiKeyRevealed = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    profileHeroSection
                        .padding(.top, 8)

                    Group {
                        sectionTitle(L10n.tr("settings.openAI"))
                        openAIKeySection
                    }

                    Group {
                        sectionTitle(L10n.tr("settings.personalInfo"))
                        generalInfoSection
                    }

                    Group {
                        sectionTitle(L10n.tr("settings.sellerAccounts"))
                        sellerAccountsSection
                    }

                    Group {
                        sectionTitle(L10n.tr("settings.platforms"))
                        marketplaceLogosGallerySection
                    }

                    Group {
                        sectionTitle(L10n.tr("settings.closetAvatars"))
                        closetAvatarSection
                    }

                    if auth.isAuthenticated {
                        Group {
                            sectionTitle(L10n.tr("settings.preferences"))
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
        .sheet(isPresented: $showGoatConnect) {
            GoatConnectSheetView(goatVM: goatVM)
                .presentationDragIndicator(Visibility.visible)
        }
        .sheet(isPresented: $showProfilePhotoSheet) {
            ProfilePhotoUploadSheet { image in
                Task { await auth.uploadProfileAvatar(image) }
            }
            .presentationDragIndicator(Visibility.visible)
            .presentationDetents([.medium])
        }
        .task(id: auth.session?.user.id) {
            guard let uid = auth.session?.user.id else { return }
            await settingsVM.loadNotifyTeamPush(
                client: SupabaseClientProvider.shared,
                userId: uid
            )
        }
        .task {
            await goatVM.validateStoredSession()
        }
    }

    // MARK: - OpenAI API

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
                        Text(L10n.tr("settings.openAIKeyTitle"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Text(
                            openaiAPIKey.isEmpty
                                ? L10n.tr("settings.openAIKeyMissing")
                                : String(
                                    format: L10n.tr("settings.openAIKeyActive"),
                                    String(openaiAPIKey.suffix(4))
                                )
                        )
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            openaiAPIKey.isEmpty
                                ? Color.orange.opacity(0.85)
                                : Color(red: 0.18, green: 0.62, blue: 0.40)
                        )
                    }
                    Spacer(minLength: 0)

                    Circle()
                        .fill(
                            openaiAPIKey.isEmpty
                                ? Color.orange.opacity(0.85)
                                : Color(red: 0.20, green: 0.70, blue: 0.45)
                        )
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
                        Text(L10n.tr("settings.openAIKeySave"))
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
                            Text(L10n.tr("settings.openAIKeyClear"))
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

                Text(L10n.tr("settings.openAIKeyHint"))
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

    // MARK: - Clóset (rostro para avatares Gemini)

    private var closetAvatarSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("settings.referencePhoto"))
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
                            Text(L10n.tr("settings.myFace"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.88))
                            Text(L10n.tr("settings.myFaceDesc"))
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
                Text(L10n.tr("settings.notificationsTitle"))
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
                        Text(L10n.tr("settings.teamAlerts"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Text(L10n.tr("settings.teamAlertsDesc"))
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

    // Profile hero — avatar grande centrado + nombre + email
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

                if auth.isUploadingProfileAvatar {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 108, height: 108)
                    ProgressView()
                        .tint(.white)
                }

                // Edit camera button
                Button {
                    guard auth.isAuthenticated else { return }
                    showProfilePhotoSheet = true
                } label: {
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
                .disabled(!auth.isAuthenticated || auth.isUploadingProfileAvatar)
            }

            VStack(spacing: 4) {
                Text(auth.userDisplayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .multilineTextAlignment(.center)

                Text(auth.session?.user.email ?? L10n.tr("settings.noSession"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
                infoRow(icon: "envelope.fill", iconTint: Color(red: 0.20, green: 0.45, blue: 0.85), label: L10n.tr("settings.email"), value: auth.session?.user.email ?? "—")
                infoDivider
                infoRow(icon: "phone.fill", iconTint: Color(red: 0.20, green: 0.70, blue: 0.45), label: L10n.tr("settings.phone"), value: "+34 600 000 000")
                infoDivider
                infoRow(icon: "shoeprints.fill", iconTint: Color(red: 0.95, green: 0.55, blue: 0.20), label: L10n.tr("settings.size"), value: "EU 42 · US 9")
                infoDivider
                infoRow(icon: "dollarsign.circle.fill", iconTint: Color(red: 0.55, green: 0.30, blue: 0.85), label: L10n.tr("settings.currency"), value: "$")
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
                sellerRow(name: "StockX", connected: false)
                infoDivider
                Button {
                    showGoatConnect = true
                } label: {
                    sellerRow(name: "GOAT", connected: goatVM.isConnected, subtitle: goatVM.session?.connectedLabel)
                }
                .buttonStyle(.plain)
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
                Text(L10n.tr("settings.marketplacesGalleryDesc"))
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

    private func sellerRow(name: String, connected: Bool, subtitle: String? = nil) -> some View {
        HStack(spacing: 14) {
            StylizedMarketplaceLogo(brand: name)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                if let subtitle, connected {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if connected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(L10n.tr("settings.connected"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
            } else {
                Text(L10n.tr("settings.connect"))
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
                        Text(L10n.tr("settings.logout"))
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
                    title: L10n.tr("settings.version")
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

// MARK: - Profile photo upload

private struct ProfilePhotoUploadSheet: View {
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(L10n.tr("settings.profilePhotoPrompt"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Button {
                    showCamera = true
                } label: {
                    Label(L10n.tr("settings.profilePhotoTake"), systemImage: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.black))
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(L10n.tr("settings.profilePhotoLibrary"), systemImage: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(L10n.tr("settings.profilePhoto"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }
                        .foregroundStyle(Color.black)
                }
            }
            .onChange(of: pickerItem) { _, item in
                Task { await loadPickerItem(item) }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: ingestCameraPick) {
                ClosetUIImagePickerBridge(image: $cameraImage)
                    .background(Color.black)
                    .ignoresSafeArea()
            }
        }
    }

    @MainActor
    private func loadPickerItem(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data)
        else { return }
        finish(with: img)
        pickerItem = nil
    }

    private func ingestCameraPick() {
        guard let img = cameraImage else { return }
        cameraImage = nil
        finish(with: img)
    }

    private func finish(with image: UIImage) {
        onImagePicked(image)
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AuthViewModel())
        .environmentObject(GoatAccountViewModel())
}
