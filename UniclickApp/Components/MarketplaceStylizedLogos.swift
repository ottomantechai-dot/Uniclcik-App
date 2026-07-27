import SwiftUI

/// Marketplace que mostramos con insignias tipográficas estilizadas (representaciones aproximadas,
/// no los logos oficiales de cada marca).
enum MarketplacePlatformDisplay: String, CaseIterable {
    case stockX = "StockX"
    case goat = "GOAT"
    case grailed = "Grailed"
    case ebay = "eBay"
    case flightClub = "Flight Club"
    case stadiumGoods = "Stadium Goods"
    case tcgCollector = "TCG Collector"
    case poshmark = "Poshmark"
    case alias = "Alias"
}

/// Logos oficiales en `Assets.xcassets/logos-de-tiendas/*.imageset`.
struct StylizedMarketplaceLogo: View {
    let brand: String

    private var assetName: String? {
        switch brand {
        case "StockX": return "stockx"
        case "GOAT": return "goat"
        case "eBay": return "ebay"
        case "Flight Club": return "flight-club"
        default: return nil
        }
    }

    var body: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
        } else {
            legacyLogo
        }
    }

    @ViewBuilder
    private var legacyLogo: some View {
        switch brand {
        case "Grailed":       grailedLogo
        case "Stadium Goods": stadiumGoodsLogo
        case "TCG Collector": tcgCollectorLogo
        case "Poshmark":      poshmarkLogo
        case "Alias":         aliasLogo
        default:              genericLogo
        }
    }
    private var grailedLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
                }
            Text("G")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.black)
        }
    }

    // Stadium Goods: blanco con "SG" negro
    private var stadiumGoodsLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                }
            Text("SG")
                .font(.system(size: 17, weight: .black, design: .serif))
                .foregroundStyle(Color.black)
                .tracking(-1)
        }
    }

    private var tcgCollectorLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.12, green: 0.22, blue: 0.48))
            Text("TCG")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.white)
        }
    }

    private var poshmarkLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.47, green: 0.09, blue: 0.20))
            Text("P")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color.white)
        }
    }

    private var aliasLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
            Text("A")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
        }
    }

    private var genericLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.18))
            Text(String(brand.prefix(2)).uppercased())
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.65))
        }
    }
}

// MARK: - Seller account connections

/// Lista de plataformas con botón **Connect** — mismo estilo que Settings → My seller account.
struct MarketplaceSellerAccountsCard: View {
    var platforms: [String] = ["StockX", "GOAT", "eBay", "Flight Club"]

    @EnvironmentObject private var goatVM: GoatAccountViewModel
    @AppStorage("demo.marketplace.connectedCSV") private var connectedCSV = ""
    @State private var showGoatConnect = false
    @State private var pendingApprovalPlatform: String?
    @State private var showApprovalSheet = false

    var body: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(platforms.enumerated()), id: \.element) { index, name in
                    if index > 0 {
                        rowDivider
                    }
                    platformRow(name: name)
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showGoatConnect) {
            GoatConnectSheetView(goatVM: goatVM)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showApprovalSheet) {
            if let platform = pendingApprovalPlatform {
                MarketplaceConnectApprovalSheet(platformName: platform) {
                    approveConnection(platform)
                }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 56)
            .padding(.trailing, 16)
    }

    @ViewBuilder
    private func platformRow(name: String) -> some View {
        let connected = isConnected(name)
        let content = sellerRow(
            name: name,
            connected: connected,
            subtitle: name == "GOAT" ? goatVM.session?.connectedLabel : nil
        )

        if connected || name == "GOAT" {
            Button {
                if name == "GOAT" { showGoatConnect = true }
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            Button {
                beginConnect(name)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    private func beginConnect(_ name: String) {
        if name == "GOAT" {
            showGoatConnect = true
            return
        }
        pendingApprovalPlatform = name
        showApprovalSheet = true
    }

    private func approveConnection(_ name: String) {
        guard !isConnected(name) else { return }
        connectedCSV = connectedCSV.isEmpty ? name : "\(connectedCSV),\(name)"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        pendingApprovalPlatform = nil
    }

    private func isConnected(_ name: String) -> Bool {
        if name == "GOAT" { return goatVM.isConnected }
        return connectedCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(name)
    }

    private func sellerRow(name: String, connected: Bool, subtitle: String?) -> some View {
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
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(L10n.tr("settings.approved"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.20, green: 0.70, blue: 0.45).opacity(0.12))
                }
            } else {
                Text(L10n.tr("settings.connect"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Sheet de aprobación antes de conectar una plataforma (demo).
struct MarketplaceConnectApprovalSheet: View {
    let platformName: String
    var onApprove: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            StylizedMarketplaceLogo(brand: platformName)
                .frame(width: 72, height: 72)

            VStack(spacing: 8) {
                Text("Conectar \(platformName)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.92))

                Text(L10n.tr("settings.approveConnectionSubtitle"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Button {
                onApprove()
                dismiss()
            } label: {
                Text(L10n.tr("settings.approveConnection"))
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background {
                        Capsule(style: .continuous).fill(Color.black)
                    }
            }
            .buttonStyle(.plain)

            Button(L10n.tr("common.close")) { dismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.white)
    }
}
