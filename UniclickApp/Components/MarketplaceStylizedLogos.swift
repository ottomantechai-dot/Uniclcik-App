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
