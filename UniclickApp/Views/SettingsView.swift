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
        "settings.approved": "Aprobado",
        "settings.connect": "Connect",
        "settings.approveConnection": "Aprobar",
        "settings.approveConnectionSubtitle": "Aprueba la conexión para sincronizar precios e inventario.",
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
        "closet.segmentProducts": "Products",
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
        "closet.addSheetSubtitle": "Add photos and details to your inventory in just a few steps.",
        "closet.addSheetPhotoHint": "Choose photos for your stock",
        "closet.addSheetSectionPhotos": "Choose photos for your stock",
        "closet.addSheetSectionAI": "Or use AI-powered tools",
        "closet.addSheetGallery": "Gallery",
        "closet.addSheetGallerySub": "Up to 5 photos",
        "closet.addSheetCamera": "Camera",
        "closet.addSheetCameraSub": "One photo instantly",
        "closet.addSheetShoes360": "Any product (360°)",
        "closet.addSheetShoes360Sub": "Front, right, back, and left — AI turns your photos into professional white-background catalog images.",
        "closet.addSheetRecommended": "Recommended",
        "closet.addSheetApparel": "Apparel · AI lookbook",
        "closet.addSheetApparelSub": "Shirts, pants, socks, belts… 5 guide photos (front, back, details) and we generate catalog and lifestyle images you can swipe through.",
        "closet.addSheetTrustTitle": "Smart, fast and secure",
        "closet.addSheetTrustSub": "AI guides you step by step to create the best product listings.",
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
        "auth.welcomeLine1": "Welcome",
        "auth.welcomeLine2": "back",
        "auth.signUpLine1": "Create",
        "auth.signUpLine2": "your account",
        "auth.signInCardSubtitle": "Access your inventory and keep managing your store.",
        "auth.signUpCardSubtitle": "Set up your account and start managing your inventory.",
        "auth.rememberMe": "Remember me",
        "auth.createYourAccount": "Create your account",
        "auth.email": "Email",
        "auth.password": "Password",
        "auth.forgot": "Forgot your password?",
        "auth.signIn": "Sign in",
        "auth.alreadyHaveAccount": "Already have an account?",
        "auth.orContinue": "or continue with",
        "auth.continueApple": "Continuar con Apple",
        "auth.continueGoogle": "Continuar con Google",
        "auth.noAccount": "Don't have an account?",
        "auth.signUp": "Sign up",
        "auth.createAccount": "Create account",
        "auth.startCollection": "Start building your collection.",
        "auth.signInToEmpire": "Sign in to access your sneaker empire.",
        "auth.helpTitle": "Help",
        "auth.helpBody": "Help will be available here soon.",
        "auth.comingSoonTitle": "Coming soon",
        "auth.comingSoonBody": "This option will be available in a future update.",
        "auth.resetAccess": "Recover access",
        "auth.connecting": "Connecting…",
        "auth.landingHeadline1": "Your entire inventory.",
        "auth.landingHeadline2": "In one place.",
        "auth.landingSubtitle": "Manage products, orders and sales from one platform.",
        "auth.featureInventory": "Inventory control",
        "auth.featureOrders": "Orders & sales",
        "auth.featureReports": "Smart reports",
        "auth.featureAccess": "Access anywhere",
        "auth.registerWithEmail": "Sign up with Email",
        "auth.alreadyHaveAccountShort": "Already have an account?",
    ]
}

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel

    @State private var showProfilePhotoSheet = false

    @Environment(\.dismiss) private var dismiss
    private let pageGray = Color(red: 0.965, green: 0.965, blue: 0.975)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 14) {
                    profileHeroSection
                        .padding(.top, 8).padding(.bottom, 6)

                    glassCard {
                        glassRow(icon: "envelope", title: "Email", value: auth.session?.user.email ?? "—")
                        Divider().padding(.leading, 58)
                        glassRow(icon: "phone", title: "Phone", value: "+1 (305) 555-0100")
                    }

                    platformGroup("Sneaker platforms", icon: "shoe.2", brands: ["StockX", "GOAT", "eBay", "Flight Club"])
                    platformGroup("Card platforms", icon: "rectangle.portrait.on.rectangle.portrait", brands: ["Collectr", "TCGplayer", "eBay"])
                    platformGroup("Coming soon", icon: "clock", brands: ["Grailed", "Poshmark", "Stadium Goods", "Alias"], dimmed: true)

                    glassCard {
                        glassRow(icon: "info.circle", title: "Version", value: "\(settingsVM.appVersion) (\(settingsVM.buildNumber))")
                    }

                    Button { Task { await auth.signOut() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log out")
                        }
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(.white, in: .capsule)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 30)
            }
        }
        .background(pageGray.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            // X para salir del perfil.
            Button { dismiss() } label: { TopBarGlassButton(systemImage: "xmark") }
                .buttonStyle(.plain).padding(.trailing, 16).padding(.top, 4)
                .accessibilityLabel("Close")
        }
        .preferredColorScheme(.light)
        .environment(\.dashboardLightSurface, true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showProfilePhotoSheet) {
            ProfilePhotoUploadSheet { image in
                Task { await auth.uploadProfileAvatar(image) }
            }
            .presentationDragIndicator(Visibility.visible)
            .presentationDetents([.medium])
        }
    }

    /// Un grupo de plataformas: cada una en su círculo de cristal con el nombre debajo.
    private func platformGroup(_ title: String, icon: String, brands: [String], dimmed: Bool = false) -> some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 32, height: 32).background(Color.black.opacity(0.05), in: .circle)
                    Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.black)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(brands, id: \.self) { brand in
                        VStack(spacing: 6) {
                            Group {
                                if UIImage(named: "Logo" + brand) != nil {
                                    Image("Logo" + brand).resizable().scaledToFit().frame(width: 30, height: 30).clipShape(.rect(cornerRadius: 8))
                                } else {
                                    StylizedMarketplaceLogo(brand: brand).frame(width: 38, height: 22)
                                }
                            }
                            .frame(width: 54, height: 54)
                            .background(.white, in: .circle)
                            .overlay { Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1) }
                            .opacity(dimmed ? 0.55 : 1)
                            Text(brand).font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(dimmed ? 0.45 : 0.75)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(14)
        }
    }

    private func glassCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity)
            .background(.white, in: .rect(cornerRadius: 24))
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func glassRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.05), in: .circle)
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.black)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(.black.opacity(0.55)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

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
                                        Color(white: 0.25),
                                        Color.black,
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
                .overlay { Circle().strokeBorder(Color.white, lineWidth: 3) }
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)

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
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(.white, in: .circle)
                        .glassEffect(.regular.interactive(), in: .circle)
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

    // MARK: - Plataformas

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
                    ForEach(
                        MarketplacePlatformDisplay.allCases.filter {
                            $0 != .grailed && $0 != .stadiumGoods
                        },
                        id: \.rawValue
                    ) { platform in
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
}
