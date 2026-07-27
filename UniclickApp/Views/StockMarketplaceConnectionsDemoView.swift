import SwiftUI

/// Conexiones de marketplace: cuenta de vendedor + plataformas por categoría (demo).
struct StockMarketplaceConnectionsDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goatVM: GoatAccountViewModel

    private var allConnectablePlatforms: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for segment in StockMarketplaceSegment.allCases {
            for platform in segment.platforms where seen.insert(platform).inserted {
                ordered.append(platform)
            }
        }
        return ordered
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeading("My seller account")
                    MarketplaceSellerAccountsCard(platforms: allConnectablePlatforms)

                    sectionHeading("By category")
                    ForEach(StockMarketplaceSegment.allCases) { segment in
                        categoryCard(segment)
                    }

                    Text("Conecta tus cuentas para sincronizar precios e inventario. GOAT usa login real; el resto es demo.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.98))
            .navigationTitle("Conexiones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .preferredColorScheme(.light)
            .task {
                await goatVM.validateStoredSession()
            }
        }
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.black.opacity(0.48))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func categoryCard(_ segment: StockMarketplaceSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(segment.emoji)
                    .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.92))
                    Text(segment.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(segment.platforms, id: \.self) { platform in
                        HStack(spacing: 6) {
                            StylizedMarketplaceLogo(brand: platform)
                                .frame(width: 28, height: 20)
                            Text(platform)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.72))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
                        }
                    }
                }
            }

            if let note = segment.connectionNote {
                Text(note)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                }
        }
    }
}
