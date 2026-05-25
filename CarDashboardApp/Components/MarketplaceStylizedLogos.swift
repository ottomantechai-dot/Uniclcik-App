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

/// Insignia que recrea el estilo visual aproximado de cada marketplace.
struct StylizedMarketplaceLogo: View {
    let brand: String

    var body: some View {
        switch brand {
        case "StockX":        stockXLogo
        case "GOAT":          goatLogo
        case "Grailed":       grailedLogo
        case "eBay":          ebayLogo
        case "Flight Club":   flightClubLogo
        case "Stadium Goods": stadiumGoodsLogo
        default:              genericLogo
        }
    }

    // StockX: negro con "X" verde lima
    private var stockXLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06))
            HStack(spacing: 0) {
                Text("S")
                    .foregroundStyle(.white)
                Text("X")
                    .foregroundStyle(Color(red: 0.20, green: 0.95, blue: 0.45))
            }
            .font(.system(size: 21, weight: .heavy, design: .rounded))
            .tracking(-1)
        }
    }

    // GOAT: blanco con "g" negra serif
    private var goatLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
            Text("g")
                .font(.system(size: 30, weight: .black, design: .serif))
                .foregroundStyle(Color.black)
                .offset(y: 1)
        }
    }

    // Grailed: blanco con "G" negra tipo sans
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

    // eBay: blanco con "ebay" multicolor inspirado en su paleta
    private var ebayLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
            HStack(spacing: 0) {
                Text("e").foregroundStyle(Color(red: 0.90, green: 0.20, blue: 0.20))
                Text("b").foregroundStyle(Color(red: 0.15, green: 0.50, blue: 0.95))
                Text("a").foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.10))
                Text("y").foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.30))
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .tracking(-0.5)
        }
    }

    // Flight Club: negro con "FLIGHT CLUB" en blanco/rojo
    private var flightClubLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06))
            VStack(spacing: -2) {
                Text("FLIGHT")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                Text("CLUB")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Color(red: 0.92, green: 0.15, blue: 0.20))
            }
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
