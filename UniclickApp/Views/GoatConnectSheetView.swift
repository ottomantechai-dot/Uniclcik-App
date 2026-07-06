import SwiftUI

/// GOAT catalog: search products, prices, and seller inventory.
struct GoatConnectSheetView: View {
    @ObservedObject var goatVM: GoatAccountViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var account = ""
    @State private var password = ""
    @State private var tab: HubTab = .catalog
    @AppStorage("goatAPIToken") private var goatAPITokenDraft = ""

    private enum HubTab: String, CaseIterable {
        case catalog = "Catalog"
        case inventory = "My listings"
        case account = "Account"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if goatVM.hasProviderToken {
                    Picker("", selection: $tab) {
                        ForEach(HubTab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !goatVM.hasProviderToken {
                            missingTokenBanner
                        }

                        switch tab {
                        case .catalog:
                            catalogSection
                        case .inventory:
                            inventorySection
                        case .account:
                            accountSection
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("GOAT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }
                        .foregroundStyle(Color.black)
                }
            }
            .task {
                await goatVM.pingAPI()
                if goatVM.isConnected {
                    await goatVM.loadSellerInventory()
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var missingTokenBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("settings.goatMissingToken"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.orange)

            SecureField("Commercial GOAT API token", text: $goatAPITokenDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            Text("Get a token from the CommercialGoatAPI provider, or add GOAT_API_TOKEN in DeveloperSettings.local.xcconfig.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.45))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        }
    }

    @ViewBuilder
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search GOAT products")
                .font(.system(size: 16, weight: .bold))
            Text("Look up SKUs, styles, or model names and pull live GOAT prices.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.52))

            HStack(spacing: 8) {
                TextField("SKU or product name", text: $goatVM.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                Button {
                    Task { await goatVM.searchCatalog() }
                } label: {
                    if goatVM.isSearching {
                        ProgressView()
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black))
                .foregroundStyle(.white)
                .disabled(goatVM.isSearching || !goatVM.hasProviderToken)
            }
        }

        if let err = goatVM.lastError {
            Text(err)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.red)
        }

        if !goatVM.searchResults.isEmpty {
            Text("\(goatVM.searchResults.count) products")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))

            ForEach(goatVM.searchResults) { product in
                Button {
                    Task { await goatVM.loadPrices(for: product) }
                } label: {
                    productRow(product)
                }
                .buttonStyle(.plain)
            }
        }

        if let detail = goatVM.selectedPriceDetail, let product = goatVM.selectedProduct {
            priceDetailCard(product: product, detail: detail)
        } else if goatVM.isLoadingPrices {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading GOAT prices…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var inventorySection: some View {
        if !goatVM.isConnected {
            Text("Sign in under the Account tab to sync your GOAT listings and sales.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        } else {
            HStack {
                Text("Active listings")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Refresh") {
                    Task { await goatVM.loadSellerInventory() }
                }
                .font(.system(size: 13, weight: .semibold))
            }

            if goatVM.isLoadingInventory {
                ProgressView().padding(.vertical, 8)
            } else if goatVM.sellingListings.isEmpty {
                Text("No active listings returned from GOAT.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.45))
            } else {
                ForEach(goatVM.sellingListings) { row in
                    listingRow(row)
                }
            }

            Text("Recent sales")
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 12)

            if goatVM.soldListings.isEmpty {
                Text("No recent sales returned from GOAT.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.45))
            } else {
                ForEach(goatVM.soldListings) { row in
                    listingRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if goatVM.isConnected, let session = goatVM.session {
            HStack(spacing: 12) {
                StylizedMarketplaceLogo(brand: "GOAT")
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("settings.connected"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                    Text(session.connectedLabel)
                        .font(.system(size: 15, weight: .bold))
                    Text(session.accountEmail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.20, green: 0.70, blue: 0.45).opacity(0.08))
            }

            Button(role: .destructive) {
                goatVM.disconnect()
            } label: {
                Text(L10n.tr("settings.goatDisconnect"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("settings.goatSignInTitle"))
                    .font(.system(size: 16, weight: .bold))
                Text(L10n.tr("settings.goatSignInSubtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.52))
            }

            TextField("alias@email.com", text: $account)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            Button {
                Task {
                    _ = await goatVM.signIn(account: account, password: password)
                    if goatVM.isConnected { tab = .inventory }
                }
            } label: {
                HStack {
                    if goatVM.isSigningIn { ProgressView().tint(.white) }
                    Text(goatVM.isSigningIn ? L10n.tr("settings.goatSigningIn") : L10n.tr("settings.goatSignIn"))
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
            .disabled(goatVM.isSigningIn || !goatVM.hasProviderToken)
        }
    }

    private func productRow(_ product: GoatProductSummary) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "shoeprints.fill")
                        .foregroundStyle(Color.black.opacity(0.25))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(2)
                if !product.sku.isEmpty {
                    Text("SKU \(product.sku)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                if let p = product.listPriceUSD {
                    Text(PieceMarketPrice.formatUSD(p))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.25))
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private func priceDetailCard(product: GoatProductSummary, detail: GoatProductPriceDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOAT PRICES")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Color.black.opacity(0.55))

            Text(product.displayTitle)
                .font(.system(size: 16, weight: .bold))

            HStack(spacing: 16) {
                pricePill(title: "Lowest", value: detail.lowestUSD)
                pricePill(title: "Top offer", value: detail.highestOfferUSD)
                pricePill(title: "Average", value: detail.averageUSD)
            }

            if let est = detail.asPieceMarketPrice() {
                GarmentMarketPriceCard(estimate: est) {
                    Task { await goatVM.loadPrices(for: product) }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground).opacity(0.45))
        }
    }

    private func pricePill(title: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.4))
            Text(value.map { PieceMarketPrice.formatUSD($0) } ?? "—")
                .font(.system(size: 14, weight: .bold))
        }
    }

    private func listingRow(_ row: GoatSellerListing) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !row.sku.isEmpty { Text(row.sku).font(.system(size: 11)).foregroundStyle(.secondary) }
                    if let size = row.sizeLabel { Text("Size \(size)").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            if let p = row.priceUSD {
                Text(PieceMarketPrice.formatUSD(p))
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .padding(.vertical, 8)
    }
}
