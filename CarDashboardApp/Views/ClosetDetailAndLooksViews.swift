import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - Hex → Color

extension Color {
    /// Parsing tolerante (#RGB / #RRGGBB).
    init(closetHex: String) {
        var s = closetHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.remove(at: s.startIndex) }
        if s.count == 6, let val = UInt32(s, radix: 16) {
            let r = Double((val >> 16) & 0xFF) / 255
            let g = Double((val >> 8) & 0xFF) / 255
            let b = Double(val & 0xFF) / 255
            self.init(red: r, green: g, blue: b)
            return
        }
        if s.count == 3 {
            let expanded = String(s.flatMap { [$0, $0] })
            self.init(closetHex: "#\(expanded)")
            return
        }
        self = Color.gray.opacity(0.35)
    }
}

// MARK: - Looks · marcos blancos (sin halo gris al pulsar)

/// Evita el oscurecimiento gris típico al mantener pulsado.
private struct LookNoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private enum LookVisualTab {
    case avatar
    case garments
}

/// Collage tipo Pinterest: dos columnas con proporciones variables.
private struct LookGarmentsCollageView: View {
    let items: [ClosetItem]
    var horizontalInset: CGFloat = 16

    private let columnGap: CGFloat = 14
    private let verticalGap: CGFloat = 14
    private let thumbPadding: CGFloat = 12
    private let cardCorner: CGFloat = 18
    private let aspectCycle: [CGFloat] = [0.72, 0.94, 0.82, 1.02, 0.86, 0.9]

    var body: some View {
        Group {
            if items.isEmpty {
                Text("Add items to the look to see the collage.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                let leftColumn = stride(from: 0, to: items.count, by: 2).map { items[$0] }
                let rightColumn = stride(from: 1, to: items.count, by: 2).map { items[$0] }

                HStack(alignment: .top, spacing: columnGap) {
                    columnCells(leftColumn)
                    columnCells(rightColumn)
                }
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    @ViewBuilder
    private func columnCells(_ columnItems: [ClosetItem]) -> some View {
        VStack(spacing: verticalGap) {
            ForEach(columnItems) { item in
                let slot = items.firstIndex(where: { $0.id == item.id }) ?? 0
                whiteWellCell(item: item, slot: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func whiteWellCell(item: ClosetItem, slot: Int) -> some View {
        let ar = aspectCycle[slot % aspectCycle.count]
        return ClosetDiskThumbnail(relativePath: ImageStore.displayRelativePath(for: item))
            .frame(maxWidth: .infinity)
            .aspectRatio(ar, contentMode: .fit)
            .padding(thumbPadding)
            .background(
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .fill(Color.white)
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
            )
    }
}

private struct LookAvatarGarmentsToggle: View {
    @Binding var tab: LookVisualTab

    var body: some View {
        HStack(spacing: 4) {
            Button {
                tab = .avatar
            } label: {
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(tab == .avatar ? Color.black : Color.white))
                    .foregroundStyle(tab == .avatar ? Color.white : Color.black)
                    .overlay(Circle().stroke(Color.black, lineWidth: tab == .avatar ? 0 : 1))
            }
            .buttonStyle(LookNoHighlightButtonStyle())

            Button {
                tab = .garments
            } label: {
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(tab == .garments ? Color.black : Color.white))
                    .foregroundStyle(tab == .garments ? Color.white : Color.black)
                    .overlay(Circle().stroke(Color.black, lineWidth: tab == .garments ? 0 : 1))
            }
            .buttonStyle(LookNoHighlightButtonStyle())
        }
        .padding(5)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Color.black, lineWidth: 1))
    }
}

// MARK: - Precio de mercado (ficha de prenda)

struct GarmentMarketPriceCard: View {
    let estimate: PieceMarketPrice
    var lastUpdated: Date? = nil
    var onRefresh: () -> Void

    @State private var sizeText = ""

    var body: some View {
        ShoeMarketPriceCardView(
            estimate: estimate,
            sizeText: $sizeText,
            lastUpdated: lastUpdated,
            onRefresh: onRefresh,
            onApplySize: onRefresh
        )
    }
}

private enum GarmentDetailSection: String, CaseIterable, Identifiable {
    case itemInfo = "Item details"
    case marketPrice = "Market price"

    var id: String { rawValue }
}

// MARK: - Detalle de prenda (estudio grande + datos)

/// Ficha tras tocar una prenda en la rejilla.
struct ClosetGarmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goatVM: GoatAccountViewModel

    @Bindable var item: ClosetItem

    @State private var priceDraft: String = ""
    @State private var purchasePriceDraft: String = ""
    @State private var sizeDraft: String = ""
    @State private var descriptionDraft: String = ""
    @FocusState private var priceFocused: Bool
    @State private var nameDraft: String = ""
    @State private var skuDraft: String = ""
    @State private var prettifying = false
    @State private var showLookComposer = false
    @State private var showShoe360Capture = false
    @State private var showShoe360ProCapture = false
    @State private var showLookbookCapture = false
    @State private var toast: String?
    @State private var marketPriceBusy = false
    @State private var showRemoveItemDialog = false
    @State private var detailSection: GarmentDetailSection = .itemInfo
    @State private var savingChanges = false

    private var secondary: Color {
        Color.black.opacity(0.55)
    }

    private var paletteHexes: [String] { item.colorPaletteHexes }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    studioHero

                    detailSectionPicker
                        .padding(.horizontal, 18)

                    if detailSection == .marketPrice {
                        garmentMarketPriceHeroSection
                            .padding(.horizontal, 18)
                    } else {
                        garmentItemInfoSection
                    }

                    Button {
                        saveAllChangesTapped()
                    } label: {
                        HStack(spacing: 8) {
                            if savingChanges {
                                ProgressView().tint(.white).scaleEffect(0.9)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text(savingChanges ? "Saving…" : "Save changes")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 28).fill(Color.black))
                    }
                    .disabled(savingChanges || prettifying)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)

                    if item.isActiveInStock {
                        Button {
                            showRemoveItemDialog = true
                        } label: {
                            Label(L10n.tr("closet.removeItem"), systemImage: "trash")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(red: 0.92, green: 0.30, blue: 0.30))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
                                        .stroke(Color(red: 0.92, green: 0.30, blue: 0.30), lineWidth: 1.5)
                                )
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                    }

                    Button {
                        showLookComposer = true
                    } label: {
                        Label("Create looks", systemImage: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 28).fill(Color.black))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    Spacer(minLength: 24)
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) {
                        commitAllDraftsToItem()
                        saveSilently()
                        dismiss()
                    }
                    .foregroundStyle(Color.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAllChangesTapped()
                    }
                    .fontWeight(.semibold)
                    .disabled(savingChanges || prettifying)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            priceDraft = ClosetItem.displayPriceDraft(from: item.priceText)
            purchasePriceDraft = ClosetItem.displayPriceDraft(from: item.purchasePriceText)
            sizeDraft = item.sizeText ?? ""
            descriptionDraft = item.productDescription ?? ""
            nameDraft = item.catalogDisplayName
            skuDraft = item.resolvedSKU ?? ""
            ensureLocalPalette()
            if item.category == .shoes {
                detailSection = .marketPrice
            }
            if item.marketPriceNeedsRefresh, item.hasStyleForMarketLookup, !marketPriceBusy {
                Task { await refreshMarketPrice() }
            }
        }
        .onChange(of: priceFocused) { _, focused in
            if !focused {
                normalizeAndSaveAskingPrice(from: priceDraft)
            }
        }
        .sheet(isPresented: $showLookComposer) {
            CreateLookComposerView(seedItemID: item.id)
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
                .preferredColorScheme(.light)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .closetInventoryDidChange, object: item.id)
        }
        .toastOverlay(message: $toast)
        .confirmationDialog(
            L10n.tr("sold.removalDialogTitle"),
            isPresented: $showRemoveItemDialog,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("sold.removalDiscontinuedAction"), role: .destructive) {
                archiveItemAsDiscontinued()
            }
            Button(L10n.tr("common.close"), role: .cancel) {}
        } message: {
            Text(L10n.tr("sold.removalDialogMessage"))
        }
        .sheet(isPresented: $showShoe360Capture) {
            NavigationStack {
                ShoeMultiAngleCaptureView(
                    garmentName: item.name,
                    productCategory: item.category
                ) { paths in
                    item.multiAngleFilenames = paths
                    try? modelContext.save()
                }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShoe360ProCapture) {
            NavigationStack {
                Shoe360ProCaptureView(item: item)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLookbookCapture) {
            NavigationStack {
                GarmentLookbookCaptureView(item: item)
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var studioHero: some View {
        Group {
            if item.allSelectableImagePaths.count > 1 {
                ProductCoverGalleryView(item: item, toast: $toast, style: .detail) {
                    heroStudioActionBar
                }
            } else {
                ZStack(alignment: .bottom) {
                    ClosetDiskThumbnail(relativePath: ImageStore.displayRelativePath(for: item))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)

                    heroStudioActionBar
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                }
                .aspectRatio(0.72, contentMode: .fit)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 10)
    }

    private var heroStudioActionBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await runPrettifyHero() }
            } label: {
                HStack(spacing: 6) {
                    if prettifying {
                        ProgressView().tint(.black).scaleEffect(0.85)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(prettifying ? "Generating…" : "Prettify photo")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.94)))
            }
            .buttonStyle(LookNoHighlightButtonStyle())
            .disabled(prettifying || !GeminiService.apiKeyConfigured)

            if item.category == .shoes {
                Menu {
                    Button {
                        showShoe360Capture = true
                    } label: {
                        Label(
                            item.hasShoeMultiAngle
                                ? "360° Lite · edit (AI photos)"
                                : "360° Lite · AI photos",
                            systemImage: "circle.grid.cross"
                        )
                    }
                    Button {
                        showShoe360ProCapture = true
                    } label: {
                        Label(
                            item.hasFullShoeSpinFromVideo
                                ? "360° Pro · edit (video + studio)"
                                : "360° Pro · video + Gemini studio",
                            systemImage: "film"
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rotate.3d")
                        Text(
                            (item.hasFullShoeSpinFromVideo || item.hasShoeMultiAngle)
                                ? "Edit 360°"
                                : "360° view"
                        )
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.94)))
                }
                .buttonStyle(LookNoHighlightButtonStyle())
            } else {
                Button {
                    showLookbookCapture = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles.rectangle.stack")
                        Text(item.hasLookbook ? "Edit lookbook" : "Create lookbook")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.94)))
                }
                .buttonStyle(LookNoHighlightButtonStyle())
            }
        }
    }

    private var localPaletteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Color palette")
                .padding(.horizontal, 18)

            if paletteHexes.isEmpty {
                Text("Not enough contrast in the photo; add a catalog-style image or tap Prettify.")
                    .font(.system(size: 13))
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 18)
            } else {
                HStack(spacing: 10) {
                    ForEach(paletteHexes, id: \.self) { hex in
                        Circle()
                            .fill(Color(closetHex: hex))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var dressAndSeasonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            chipRow(title: "Dress codes", all: DressCode.allCases, selected: item.dressCodesStored) { code in
                toggleDress(code)
            }
            chipRow(title: "Season", all: Season.allCases, selected: item.seasonsStored) { season in
                toggleSeason(season)
            }
        }
    }

    private func chipRow<T: Hashable & Equatable>(
        title: String,
        all: [T],
        selected: [T],
        label: @escaping (T) -> String,
        onTap: @escaping (T) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title)
                .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(all, id: \.self) { value in
                        let on = selected.contains(value)
                        Button {
                            onTap(value)
                        } label: {
                            Text(label(value))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(on ? Color.white : Color.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(on ? Color.black : Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func chipRow(title: String, all: [DressCode], selected: [DressCode], onTap: @escaping (DressCode) -> Void)
        -> some View
    {
        chipRow(title: title, all: all, selected: selected, label: { $0.displayName }, onTap: onTap)
    }

    private func chipRow(title: String, all: [Season], selected: [Season], onTap: @escaping (Season) -> Void) -> some View {
        chipRow(title: title, all: all, selected: selected, label: { $0.displayName }, onTap: onTap)
    }

    private func toggleDress(_ code: DressCode) {
        var s = item.dressCodesStored
        if let i = s.firstIndex(of: code) { s.remove(at: i) } else { s.append(code) }
        item.dressCodesStored = s
        saveSilently()
    }

    private func toggleSeason(_ season: Season) {
        var s = item.seasonsStored
        if let i = s.firstIndex(of: season) { s.remove(at: i) } else { s.append(season) }
        item.seasonsStored = s
        saveSilently()
    }

    private func fieldLabel(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(secondary)
    }

    private func saveSilently() {
        do {
            try modelContext.save()
            CatalogClosetBridge.syncClosetItemEditsToCatalog(item)
            NotificationCenter.default.post(name: .closetInventoryDidChange, object: item.id)
        } catch {
            toast = "Could not save: \(error.localizedDescription)"
        }
    }

    private func commitAllDraftsToItem() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            item.name = name
        }

        let sku = skuDraft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        item.skuText = sku.isEmpty ? nil : sku

        let purchase = purchasePriceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let formattedPurchase = ClosetItem.normalizedPriceText(from: purchase) {
            item.purchasePriceText = formattedPurchase
            purchasePriceDraft = formattedPurchase
        } else {
            item.purchasePriceText = nil
        }

        normalizeAndSaveAskingPrice(from: priceDraft, updateDraft: true)

        let size = StockSizeDisplay.normalizedStorage(from: sizeDraft) ?? ""
        item.sizeText = size.isEmpty ? nil : size
        sizeDraft = size.isEmpty ? sizeDraft : StockSizeDisplay.cardLabel(from: size) ?? size

        let desc = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        item.productDescription = desc.isEmpty ? nil : desc
    }

    private func normalizeAndSaveAskingPrice(from raw: String, updateDraft: Bool = false) {
        if let formatted = ClosetItem.normalizedPriceText(from: raw) {
            item.priceText = formatted
            if updateDraft { priceDraft = formatted }
        } else {
            item.priceText = nil
        }
        saveSilently()
    }

    /// Applies live market average to asking price; purchase cost is never modified.
    private func applyMarketPriceToAsking(from estimate: PieceMarketPrice? = nil) {
        guard let avg = (estimate ?? item.marketPrice)?.avg, avg > 0 else { return }
        let formatted = PieceMarketPrice.formatUSD(avg)
        priceDraft = formatted
        item.priceText = formatted
        saveSilently()
        toast = "Asking price set to \(formatted)."
    }

    private func saveAllChangesTapped() {
        guard !savingChanges else { return }
        savingChanges = true
        priceFocused = false
        commitAllDraftsToItem()
        saveSilently()
        savingChanges = false
        toast = "All changes saved."
        NotificationCenter.default.post(name: .upsoledCatalogDidChange, object: nil)
    }

    private func archiveItemAsDiscontinued() {
        let closetId = item.id
        Task {
            await CatalogClosetBridge.deleteLinkedCatalogProduct(forClosetItem: closetId)
            await MainActor.run {
                ClosetInventoryRepair.permanentlyDeleteClosetItem(item, in: modelContext)
                toast = L10n.tr("sold.removedToast")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
            }
        }
    }

    private var detailSectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(GarmentDetailSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        detailSection = section
                    }
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(detailSection == section ? Color.white : Color.black.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if detailSection == section {
                                Capsule().fill(Color.black)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(Color(.secondarySystemBackground))
        }
    }

    @ViewBuilder
    private var garmentItemInfoSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Name")
                HStack(spacing: 8) {
                    TextField("Product name", text: $nameDraft)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .onChange(of: nameDraft) { _, new in
                            let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
                            item.name = t.isEmpty ? item.name : t
                            saveSilently()
                        }
                    Image(systemName: "pencil.line")
                        .font(.system(size: 16))
                        .foregroundStyle(secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

                fieldLabel("SKU")
                TextField("e.g. DD1391-101", text: $skuDraft)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .onChange(of: skuDraft) { _, new in
                        let t = new.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        item.skuText = t.isEmpty ? nil : t
                        saveSilently()
                    }
            }
            .padding(.horizontal, 18)

            localPaletteSection
            dressAndSeasonSection

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Category")
                Menu {
                    ForEach(ClothingCategory.allCases, id: \.rawValue) { cat in
                        Button {
                            item.categoryRaw = cat.rawValue
                            saveSilently()
                        } label: {
                            HStack {
                                Text(cat.displayName)
                                if cat.rawValue == item.categoryRaw {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("\(item.category.emoji) \(item.category.displayName)")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13))
                            .foregroundStyle(secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                }
                .foregroundStyle(Color.black)

                fieldLabel("Brand")
                TextField(
                    item.brand == "Unknown Brand" ? "Add brand" : (item.brand ?? ""),
                    text: Binding(
                        get: { item.brand == "Unknown Brand" ? "" : (item.brand ?? "") },
                        set: {
                            item.brand = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil
                                : $0
                            saveSilently()
                        }
                    ))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

                fieldLabel("Pricing")

                fieldLabel("Purchase price")
                TextField("What you paid", text: $purchasePriceDraft)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .onChange(of: purchasePriceDraft) { _, new in
                        let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty {
                            item.purchasePriceText = nil
                        } else if let formatted = ClosetItem.normalizedPriceText(from: t) {
                            item.purchasePriceText = formatted
                        } else {
                            item.purchasePriceText = t
                        }
                        saveSilently()
                    }

                fieldLabel("Asking price")
                HStack(spacing: 8) {
                    TextField("Your listing price", text: $priceDraft)
                        .focused($priceFocused)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                        .onChange(of: priceDraft) { _, new in
                            let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
                            if t.isEmpty {
                                item.priceText = nil
                            } else if let formatted = ClosetItem.normalizedPriceText(from: t) {
                                item.priceText = formatted
                            } else {
                                item.priceText = t
                            }
                            saveSilently()
                        }

                    if let est = item.marketPrice, est.avg > 0 {
                        Button {
                            applyMarketPriceToAsking(from: est)
                        } label: {
                            Text("Market")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if item.hasPricingForProfit {
                    garmentProfitSummaryCard
                }

                fieldLabel("Size")
                TextField(
                    "🇺🇸U.S 11",
                    text: $sizeDraft
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                .onChange(of: sizeDraft) { _, new in
                    let t = StockSizeDisplay.normalizedStorage(from: new) ?? ""
                    item.sizeText = t.isEmpty ? nil : t
                    sizeDraft = t
                    saveSilently()
                }

                if let color = item.colorLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !color.isEmpty {
                    fieldLabel("Color")
                    Text(color)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                }

                if !item.listingPlatforms.isEmpty {
                    fieldLabel("Platforms")
                    Text(item.listingPlatforms.joined(separator: " · "))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                }

                fieldLabel("Description")
                TextEditor(text: $descriptionDraft)
                    .frame(minHeight: 88)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .onChange(of: descriptionDraft) { _, new in
                        let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.productDescription = t.isEmpty ? nil : t
                        saveSilently()
                    }
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var garmentMarketPriceHeroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            marketCharacteristicsSummary

            if marketPriceBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching live prices from StockX & GOAT…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            } else if let est = item.marketPrice {
                ShoeMarketPriceCardView(
                    estimate: est,
                    sizeText: $sizeDraft,
                    isBusy: marketPriceBusy,
                    lastUpdated: item.marketPriceFetchedAt,
                    onRefresh: { Task { await refreshMarketPrice(force: true) } },
                    onApplySize: {
                        let t = StockSizeDisplay.normalizedStorage(from: sizeDraft) ?? ""
                        item.sizeText = t.isEmpty ? nil : t
                        sizeDraft = t
                        saveSilently()
                        Task { await refreshMarketPrice(force: true) }
                    },
                    onApplyMarketPrice: {
                        applyMarketPriceToAsking(from: est)
                    }
                )
            } else {
                Button {
                    Task { await refreshMarketPrice(force: true) }
                } label: {
                    Label("Look up market price", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
                }
                .buttonStyle(.plain)
                .disabled(!item.hasStyleForMarketLookup)
                .opacity(item.hasStyleForMarketLookup ? 1 : 0.45)

                if !item.hasStyleForMarketLookup {
                    Text("Add a name or Style / SKU (e.g. DD1391-101) to fetch real market prices.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.85))
                } else if !KicksDBClient.isConfigured {
                    Text("Add KICKSDB_API_KEY in DeveloperSettings.local.xcconfig for StockX & GOAT prices.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.85))
                }
            }
        }
    }

    @ViewBuilder
    private var marketCharacteristicsSummary: some View {
        let parts: [String] = [
            item.brand?.trimmingCharacters(in: .whitespacesAndNewlines),
            item.resolvedSKU,
            item.cardSizeLabel,
            item.colorLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
            item.category.displayName
        ].compactMap { raw in
            guard let raw, !raw.isEmpty else { return nil }
            return raw
        }

        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("ITEM DETAILS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.black.opacity(0.45))
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var garmentProfitSummaryCard: some View {
        let profit = item.projectedProfitUSD
        let tint = profit >= 0
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("POTENTIAL PROFIT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(profit >= 0 ? "+\(PieceMarketPrice.formatUSD(Int(profit.rounded())))" : "−\(PieceMarketPrice.formatUSD(Int(abs(profit).rounded())))")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAID")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.4))
                    Text(PieceMarketPrice.formatUSD(Int(item.purchaseValueUSD.rounded())))
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SELL AT")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.4))
                    Text(PieceMarketPrice.formatUSD(Int(item.effectiveSellValueUSD.rounded())))
                        .font(.system(size: 13, weight: .bold))
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.22), lineWidth: 1)
                }
        }
    }

    @MainActor
    private func refreshMarketPrice(force: Bool = false) async {
        guard item.hasStyleForMarketLookup else {
            toast = "Add a Style / SKU code first (e.g. DD1391-101)."
            return
        }
        if !force, !item.marketPriceNeedsRefresh { return }

        marketPriceBusy = true
        defer { marketPriceBusy = false }

        let preferKicksDB = KicksDBClient.isConfigured
        do {
            let est = try await PieceMarketPrice.lookupForItem(
                item,
                goatVM: goatVM,
                useWebSearch: !preferKicksDB
            )
            item.applyMarketPrice(est)
            saveSilently()
            if force {
                toast = "Market price: \(PieceMarketPrice.formatUSD(est.avg))"
            }
            // Refresh cards/totals; asking price updates only when user taps Market / Use market price.
        } catch {
            let message = (error as NSError).localizedDescription
            if message.contains("429") || message.localizedCaseInsensitiveContains("quota") {
                toast = "OpenAI quota exceeded. Add KICKSDB_API_KEY for StockX & GOAT prices."
            } else if item.marketPrice == nil {
                toast = message
            }
        }
    }

    private func ensureLocalPalette() {
        guard item.colorPaletteJSON == nil || item.colorPaletteJSON?.isEmpty == true else { return }
        guard let ui = ImageStore.load(item.imageFilename) else { return }
        let hexes = ColorPaletteExtractor.extract(from: ui, count: 5)
        guard let data = try? JSONEncoder().encode(hexes),
              let s = String(data: data, encoding: .utf8)
        else { return }
        item.colorPaletteJSON = s
        saveSilently()
    }

    @MainActor
    private func runPrettifyHero() async {
        guard GeminiService.apiKeyConfigured else {
            toast = "Configura GeminiAPIKey para Prettify."
            return
        }
        let crop = item.originalCropFilename ?? item.imageFilename
        prettifying = true
        defer { prettifying = false }
        do {
            let rel = try await GeminiService.shared.prettify(
                cropRelativePath: crop,
                category: item.category.rawValue,
                itemName: item.name
            )
            item.imageFilename = rel
            item.galleryCoverRelativePath = rel
            if let ui = ImageStore.load(rel) {
                let hexes = ColorPaletteExtractor.extract(from: ui, count: 5)
                if let data = try? JSONEncoder().encode(hexes),
                   let s = String(data: data, encoding: .utf8) {
                    item.colorPaletteJSON = s
                }
            }
            saveSilently()
            toast = "Photo updated."
        } catch {
            toast = error.localizedDescription
        }
    }
}

// MARK: - Crear look (combinar prendas en SwiftData)

struct CreateLookComposerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Si viene del detalle, preselecciona esa prenda.
    var seedItemID: UUID? = nil

    @Query(sort: \ClosetItem.createdAt, order: .reverse)
    private var closetItems: [ClosetItem]

    private var selectableClosetItems: [ClosetItem] {
        closetItems.filter(\.isActiveInStock)
    }

    @State private var selectedIDs = Set<UUID>()
    @State private var lookTitle: String = ""
    @State private var composerToast: String?

    private let gridCols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var selectedOrderedPieces: [ClosetItem] {
        selectableClosetItems.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select at least one item. You can generate the studio-style avatar from the look detail.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .padding(.horizontal, 18)

                        TextField("Nombre del look (opcional)", text: $lookTitle)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                            .padding(.horizontal, 18)

                        if !selectedOrderedPieces.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your look — selected items")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.48))
                                    .padding(.horizontal, 18)
                                LookGarmentsCollageView(items: selectedOrderedPieces, horizontalInset: 14)
                                    .padding(.bottom, 4)
                            }
                        }

                        if closetItems.isEmpty {
                            Text("You have no items in your closet yet. Add photos before creating a look.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.45))
                                .padding(.horizontal, 18)
                                .padding(.top, 12)
                        } else {
                            LazyVGrid(columns: gridCols, spacing: 12) {
                                ForEach(selectableClosetItems) { item in
                                    lookPickerCell(item)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, 8)
                }

                VStack {
                    Spacer()
                    Button {
                        saveLookTapped()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save look")
                        }
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 28).fill(Color.black))
                        .opacity(selectedIDs.isEmpty ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIDs.isEmpty)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                    .background {
                        LinearGradient(
                            colors: [Color.white.opacity(0), Color.white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle("Create looks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }.foregroundStyle(Color.black)
                }
            }
            .toastOverlay(message: $composerToast)
            .onAppear {
                if let seed = seedItemID {
                    selectedIDs.insert(seed)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func lookPickerCell(_ item: ClosetItem) -> some View {
        let on = selectedIDs.contains(item.id)
        return Button {
            if on { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
                    ClosetDiskThumbnail(relativePath: ImageStore.displayRelativePath(for: item))
                        .padding(4)

                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(on ? Color.black : Color.black.opacity(0.25))
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(on ? Color.black : Color.clear, lineWidth: on ? 2.5 : 0)
                }
                .aspectRatio(0.72, contentMode: .fit)

                Text(item.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(LookNoHighlightButtonStyle())
    }

    private func saveLookTapped() {
        let ordered = closetItems.filter { selectedIDs.contains($0.id) }
        guard !ordered.isEmpty else { return }
        let trimmed = lookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName = "Look \(Date().formatted(date: .abbreviated, time: .omitted))"
        let look = Look(name: trimmed.isEmpty ? defaultName : trimmed, items: ordered)
        modelContext.insert(look)
        try? modelContext.save()
        ClosetAnalytics.named("closet_look_saved", params: "items:\(ordered.count)")
        pulseToast("Look saved.")
        dismiss()
    }

    private func pulseToast(_ s: String) {}
}

// MARK: - Detalle de un Look guardado

struct ClosetLookDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var look: Look

    @State private var confirmDelete = false
    @State private var showAvatarGenerator = false
    @State private var visualTab: LookVisualTab = .garments
    @State private var lookDetailToast: String?
    @State private var exportingAvatar = false

    private var pieces: [ClosetItem] { look.resolvedItemsOrdered }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if look.avatarRelativePath != nil {
                        HStack {
                            LookAvatarGarmentsToggle(tab: $visualTab)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }

                    Group {
                        if look.avatarRelativePath == nil {
                            LookGarmentsCollageView(items: pieces, horizontalInset: 16)
                                .padding(.vertical, 4)
                        } else if visualTab == .avatar {
                            if let avatarPath = look.avatarRelativePath {
                                ZStack(alignment: .bottomTrailing) {
                                    Color.white
                                    ClosetDiskThumbnail(relativePath: avatarPath)
                                        .aspectRatio(9 / 16, contentMode: .fit)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)

                                    Button {
                                        Task { await saveAvatarToPhotos(path: avatarPath) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if exportingAvatar {
                                                ProgressView().scaleEffect(0.85).tint(.white)
                                            } else {
                                                Image(systemName: "square.and.arrow.down")
                                            }
                                            Text("9:16 photos")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(Color.black.opacity(0.55)))
                                    }
                                    .buttonStyle(LookNoHighlightButtonStyle())
                                    .disabled(exportingAvatar)
                                    .padding(14)
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .padding(.horizontal, 16)
                            }
                        } else {
                            LookGarmentsCollageView(items: pieces, horizontalInset: 16)
                                .padding(.vertical, 4)
                        }
                    }

                    Text(look.name)
                        .font(.system(size: 20, weight: .heavy))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)

                    lookRibbonCoverSection

                    if look.avatarRelativePath == nil {
                        Text("Items in this look (\(pieces.count))")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.52))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }

                    HStack {
                        Spacer()
                        Button {
                            showAvatarGenerator = true
                        } label: {
                            Label("Create avatar", systemImage: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.black))
                        }
                        .disabled(pieces.isEmpty || !GeminiService.apiKeyConfigured)
                        .buttonStyle(LookNoHighlightButtonStyle())
                        Spacer()
                    }
                    .padding(.vertical, 10)

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Delete this look")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LookNoHighlightButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
                .padding(.top, 8)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Look")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if look.avatarRelativePath != nil {
                    visualTab = .avatar
                } else {
                    visualTab = .garments
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }.foregroundStyle(Color.black)
                }
            }
            .confirmationDialog(
                "Delete this look?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteLook()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showAvatarGenerator) {
                LookAvatarGeneratorSheet(look: look)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
                    .preferredColorScheme(.light)
            }
        }
        .preferredColorScheme(.light)
        .toastOverlay(message: $lookDetailToast)
    }

    @ViewBuilder
    private var lookRibbonCoverSection: some View {
        let candidates = ribbonCoverCandidates()
        let show = candidates.count > 1 || look.avatarRelativePath != nil
        if show {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cover for the My Looks carousel")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button {
                            look.ribbonCoverRelativePath = nil
                            persistLookRibbonSettings()
                            lookDetailToast = "Automatic cover (avatar → items)."
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.35))
                                Text("Auto")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Color.black.opacity(0.55))
                                    .lineLimit(1)
                            }
                            .frame(width: 74, height: 102)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        look.ribbonCoverRelativePath == nil ? Color.black : Color.black.opacity(0.12),
                                        lineWidth: look.ribbonCoverRelativePath == nil ? 2.5 : 1
                                    )
                            )
                        }
                        .buttonStyle(LookNoHighlightButtonStyle())

                        ForEach(Array(candidates.enumerated()), id: \.offset) { _, pair in
                            ribbonCoverChip(label: pair.0, path: pair.1)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func ribbonCoverChip(label: String, path: String) -> some View {
        let on = look.ribbonCoverRelativePath == path
        return Button {
            look.ribbonCoverRelativePath = path
            persistLookRibbonSettings()
            lookDetailToast = "Esta foto es la miniatura del look."
        } label: {
            VStack(spacing: 6) {
                if let ui = StockImageLoader.cachedLocalImage(relativePath: path) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 74, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 74, height: 78)
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 74)
            }
            .padding(.vertical, 4)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(on ? Color.black : Color.black.opacity(0.1), lineWidth: on ? 2.5 : 1)
            )
        }
        .buttonStyle(LookNoHighlightButtonStyle())
    }

    private func ribbonCoverCandidates() -> [(String, String)] {
        var out: [(String, String)] = []
        var seen = Set<String>()
        func push(_ label: String, _ rawPath: String?) {
            guard let trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
                  ImageStore.exists(trimmed) else { return }
            if seen.insert(trimmed).inserted { out.append((label, trimmed)) }
        }

        push("Avatar IA", look.avatarRelativePath)
        for it in pieces {
            let sn = shortPieceLabel(it.name)
            push("\(sn)\n(catálogo)", it.imageFilename)
            for idx in it.lookbookAllFilenamesInOrder.indices {
                let p = it.lookbookAllFilenamesInOrder[idx]
                push("\(sn)\nlook \(idx + 1)", p)
            }
        }
        return out
    }

    private func shortPieceLabel(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 10 { return t }
        return String(t.prefix(8)) + "…"
    }

    private func persistLookRibbonSettings() {
        try? modelContext.save()
    }

    @MainActor
    private func saveAvatarToPhotos(path: String) async {
        exportingAvatar = true
        defer { exportingAvatar = false }
        do {
            try await ClosetPhotoExports.saveClosetAvatarForTikTokExport(relativePath: path)
            lookDetailToast = "TikTok-ready avatar saved to Photos."
        } catch {
            lookDetailToast = error.localizedDescription
        }
    }

    private func deleteLook() {
        if let rel = look.avatarRelativePath {
            ImageStore.deleteIfExists(rel)
        }
        modelContext.delete(look)
        try? modelContext.save()
        ClosetAnalytics.named("closet_look_deleted")
    }
}

// MARK: - Generador de avatar (Gemini multimodal)

struct LookAvatarGeneratorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let look: Look

    @Query(sort: \UserProfile.createdAt) private var userProfiles: [UserProfile]

    @State private var gender: AvatarGender = .female
    @State private var visualTab: LookVisualTab = .avatar
    @State private var isGenerating = false
    @State private var generatedFilename: String?
    @State private var error: String?
    @State private var showFaceSetup = false
    /// Por generación: respeta `UserProfile.useFaceByDefault` al abrir; el usuario puede desactivar solo esta sesión.
    @State private var useFaceForAvatar: Bool = true
    @State private var avatarExportBusy = false
    @State private var avatarExportToast: String?

    private var pieces: [ClosetItem] { look.resolvedItemsOrdered }

    /// Avatar listo para mostrar (sesión actual o ya guardado en el look).
    private var avatarDisplayPath: String? {
        generatedFilename ?? look.avatarRelativePath
    }

    private var hasAvatarPreview: Bool {
        guard let p = avatarDisplayPath, ImageStore.exists(p) else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    previewBlock

                    controlBar

                    faceRow

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 14)
                .padding(.bottom, 8)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }.foregroundStyle(Color.black)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        showFaceSetup = true
                    } label: {
                        faceToolbarGlyph
                    }
                    .buttonStyle(LookNoHighlightButtonStyle())
                    .accessibilityLabel("Mi rostro")

                    Button {
                        Task { await exportAvatarToPhotosTapped() }
                    } label: {
                        if avatarExportBusy {
                            ProgressView()
                                .scaleEffect(0.9)
                                .tint(.black)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(LookNoHighlightButtonStyle())
                    .disabled(avatarExportBusy || avatarDisplayPath == nil)
                    .accessibilityLabel("Save avatar to Photos")

                    Button("Save") { saveTapped() }
                        .disabled(avatarDisplayPath == nil)
                }
            }
            .sheet(isPresented: $showFaceSetup) {
                FaceSetupView()
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                _ = UserProfile.current(in: modelContext)
                visualTab = hasAvatarPreview ? .avatar : .garments
                if let saved = look.avatarGenderRaw, let parsed = AvatarGender(rawValue: saved) {
                    gender = parsed
                } else if let raw = userProfiles.first?.preferredGenderRaw,
                          let parsed = AvatarGender(rawValue: raw) {
                    gender = parsed
                }
                useFaceForAvatar = userProfiles.first?.useFaceByDefault ?? true
            }
        }
        .preferredColorScheme(.light)
        .toastOverlay(message: $avatarExportToast)
    }

    @MainActor
    private func exportAvatarToPhotosTapped() async {
        guard let rel = avatarDisplayPath else { return }
        avatarExportBusy = true
        defer { avatarExportBusy = false }
        do {
            try await ClosetPhotoExports.saveClosetAvatarForTikTokExport(relativePath: rel)
            avatarExportToast = "9:16 avatar saved to Photos."
        } catch {
            avatarExportToast = error.localizedDescription
        }
    }

    @ViewBuilder
    private var previewBlock: some View {
        ZStack {
            Color.white
            if visualTab == .garments {
                LookGarmentsCollageView(items: pieces, horizontalInset: 14)
                    .padding(.horizontal, 2)
            } else {
                avatarPreviewContent
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 460)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var avatarPreviewContent: some View {
        if isGenerating {
            ProgressView("Generando avatar…")
                .padding(40)
        } else if let path = avatarDisplayPath, let img = ImageStore.load(path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .aspectRatio(9 / 16, contentMode: .fit)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } else {
            Text("Your look will appear here: full-body model on a pure white background, no shadows. Choose a model below and tap Generate.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.black.opacity(0.42))
                .padding(.horizontal, 36)
                .padding(.vertical, 48)
        }
    }

    /// Barra inferior: vista avatar/prendas, género para la API y regenerar.
    private var controlBar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                LookAvatarGarmentsToggle(tab: $visualTab)

                Spacer(minLength: 12)

                Button {
                    Task { await generate() }
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        }
                        Image(systemName: "arrow.clockwise")
                        Text(avatarDisplayPath == nil ? "Generar" : "Regenerar")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.black))
                }
                .disabled(isGenerating || pieces.isEmpty)
                .buttonStyle(LookNoHighlightButtonStyle())
            }
            .padding(.horizontal, 16)

            genderRow
                .padding(.horizontal, 16)
        }
    }

    private var faceToolbarGlyph: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: 34, height: 34)
            if let rel = userProfiles.first?.faceImageFilename,
               let ui = ImageStore.load(rel) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
        }
    }

    @ViewBuilder
    private var faceRow: some View {
        let hasPhoto = userProfiles.first?.faceImageFilename != nil
        VStack(alignment: .leading, spacing: 10) {
            if hasPhoto {
                Toggle(isOn: $useFaceForAvatar) {
                    HStack(spacing: 8) {
                        Image(systemName: "face.smiling")
                            .foregroundStyle(Color.black.opacity(0.55))
                        Text("Make it look like me")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.82))
                    }
                }
                .tint(.black)
                .padding(.horizontal, 16)
            } else {
                Button {
                    showFaceSetup = true
                } label: {
                    Label("Agregar mi rostro para personalizar el avatar", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(LookNoHighlightButtonStyle())
                .padding(.horizontal, 16)
            }
        }
    }

    /// Modelo físico pedido al generador — independiente del interruptor prendas / avatar.
    private var genderRow: some View {
        HStack(spacing: 10) {
            Text("Model")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))

            HStack(spacing: 6) {
                ForEach(AvatarGender.allCases, id: \.self) { g in
                    Button {
                        gender = g
                        if let p = userProfiles.first {
                            p.preferredGenderRaw = g.rawValue
                            try? modelContext.save()
                        }
                    } label: {
                        Text(g.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(gender == g ? Color.white : Color.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(gender == g ? Color.black : Color.white))
                            .overlay(
                                Capsule()
                                    .stroke(Color.black, lineWidth: gender == g ? 0 : 1)
                            )
                    }
                    .buttonStyle(LookNoHighlightButtonStyle())
                }
            }

            Spacer(minLength: 0)
        }
    }

    @MainActor
    private func generate() async {
        guard !pieces.isEmpty else { return }
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        let paths = pieces.map(\.imageFilename)
        let lines = pieces.map { piece in
            "- \(piece.category.displayName): \(piece.name)"
        }
        let facePath: String? = {
            guard useFaceForAvatar,
                  let rel = userProfiles.first?.faceImageFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rel.isEmpty
            else { return nil }
            return rel
        }()

        do {
            let rel = try await GeminiService.shared.generateLookAvatar(
                garmentRelativePaths: paths,
                itemDescriptionLines: lines,
                gender: gender,
                faceReferenceRelativePath: facePath
            )
            generatedFilename = rel
            visualTab = .avatar
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveTapped() {
        guard let f = generatedFilename ?? look.avatarRelativePath else { return }
        look.avatarRelativePath = f
        look.avatarGenderRaw = gender.rawValue
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Vista 360° · zapatos (fluida · lite)

private struct Shoe360Viewer: View {
    let filenames: [String]
    @Binding var toast: String?

    @State private var phase: CGFloat = 0
    @State private var spinGrabAnchor: CGFloat = 0
    @State private var isDraggingSpin = false
    @State private var saving = false

    private var n: Int { filenames.count }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let nearest = ShoeFluidSpinMath.nearestFrameIndex(phase: phase, frameCount: max(n, 1))
            let distSnap =
                n <= 1
                    ? 0
                    : ShoeFluidSpinMath.fractionalDistanceToSnap(
                        phase: phase,
                        frameCount: n
                    )
            let showSwipeHint = !isDraggingSpin && n > 1 && distSnap < 0.048

            ZStack {
                Color.white

                ShoeFluidSpinPhaseLayer(filenames: filenames, phase: phase)

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            Task { await saveCurrentAngle() }
                        } label: {
                            HStack(spacing: 5) {
                                if saving {
                                    ProgressView().scaleEffect(0.8).tint(.black)
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                }
                                Text("Photos")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.92)))
                        }
                        .buttonStyle(LookNoHighlightButtonStyle())
                        .disabled(saving || filenames.isEmpty)
                        .padding(10)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(Array(filenames.indices), id: \.self) { i in
                            Capsule()
                                .fill(i == nearest ? Color.black : Color.gray.opacity(0.28))
                                .frame(width: i == nearest ? 18 : 6, height: 4)
                        }
                    }
                    .animation(.easeOut(duration: 0.08), value: nearest)
                    .padding(.bottom, 12)
                }

                Image(systemName: "hand.draw")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.black.opacity(showSwipeHint ? 0.28 : 0))
                    .offset(y: 72)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard !filenames.isEmpty else { return }
                        let nFloat = CGFloat(max(n, 1))
                        if !isDraggingSpin {
                            isDraggingSpin = true
                            spinGrabAnchor = ShoeFluidSpinMath.normalizePhase(phase, frameCount: n)
                        }
                        let deltaFrames = -(value.translation.width / width) * nFloat
                        var t = Transaction()
                        t.animation = nil
                        withTransaction(t) {
                            phase = ShoeFluidSpinMath.normalizePhase(spinGrabAnchor + deltaFrames, frameCount: n)
                        }
                    }
                    .onEnded { _ in
                        isDraggingSpin = false
                        let snapped = ShoeFluidSpinMath.snapPhase(phase, frameCount: n)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            phase = snapped
                        }
                        spinGrabAnchor = phase
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: filenames.count) { _, newCount in
            guard newCount > 0 else {
                phase = 0
                spinGrabAnchor = 0
                return
            }
            phase = ShoeFluidSpinMath.normalizePhase(phase, frameCount: newCount)
            spinGrabAnchor = phase
        }
    }

    @MainActor
    private func saveCurrentAngle() async {
        let idx = ShoeFluidSpinMath.nearestFrameIndex(phase: phase, frameCount: max(n, 1))
        guard filenames.indices.contains(idx) else { return }
        saving = true
        defer { saving = false }
        let rel = filenames[idx]
        do {
            try await ClosetPhotoExports.saveRelativeClosetImageToPhotoAlbum(relativePath: rel)
            toast = "Vista del zapato guardada en Fotos."
        } catch {
            toast = error.localizedDescription
        }
    }
}

/// Captura guiada de 4 ángulos horizontales y generación con Gemini (`shoe360/`).
///
/// Persistencia: llama `onOrderedPathsCommitted` con 4 rutas relativas cuando el usuario guarda (borrador SwiftData desde la vista llamante).
struct ShoeMultiAngleCaptureView: View {
    let garmentName: String
    var productCategory: ClothingCategory = .shoes
    /// Si vienen exactamente 4 UIImage, se asignan a `ShoeAngle.allCases` en ese orden (p. ej. galería en bloque).
    var prefilledCapturedInAngleOrder: [UIImage]? = nil
    /// Si `false`, no muestra toolbar «Cerrar» (usa el padre `NavigationStack`).
    var showsCloseButton: Bool = true
    /// Cuatro rutas relativas ordenadas (`ShoeAngle.allCases`).
    let onOrderedPathsCommitted: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var currentAngle: ShoeAngle = .front
    @State private var captured: [ShoeAngle: UIImage] = [:]
    @State private var prettifiedFilenames: [ShoeAngle: String] = [:]
    @State private var appliedGalleryPrefill = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraUIImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var autoSpinPhase: CGFloat = 0
    @State private var autoSpinTimer: Timer?

    private var orderedCapturedImages: [UIImage] {
        ShoeAngle.allCases.compactMap { captured[$0] }
    }

    private var orderedPrettifiedPaths: [String] {
        ShoeAngle.allCases.compactMap { prettifiedFilenames[$0] }
    }

    private var allCaptured: Bool { ShoeAngle.allCases.allSatisfy { captured[$0] != nil } }
    private var allPrettified: Bool { ShoeAngle.allCases.allSatisfy { prettifiedFilenames[$0] != nil } }

    /// Primer ángulo en orden (Front → Right → Back → Left) que aún no tiene foto.
    private var firstMissingAngle: ShoeAngle? {
        ShoeAngle.allCases.first { captured[$0] == nil }
    }

    /// Solo puedes abrir ángulos ya completados (para reemplazar) o el siguiente pendiente.
    private func isAngleAccessible(_ angle: ShoeAngle) -> Bool {
        if captured[angle] != nil { return true }
        return angle == firstMissingAngle
    }

    private var canCaptureCurrentAngle: Bool {
        isAngleAccessible(currentAngle) && !allCaptured
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Each AI-generated image has an approximate cost; 4 angles ≈ 4 outputs.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                    captureHeroContent
                }
                .frame(height: 280)
                .padding(.horizontal, 16)

                if !allCaptured {
                    Text(currentAngle.productInstruction(for: productCategory))
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("The 4 positions")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.black)
                    Text(
                        productCategory == .shoes
                            ? "Complete each side in order: Front, Right, Back, then Left. You can tap a completed side to replace its photo."
                            : "Capture front, right side, back, and left side in order. AI will turn each photo into a professional white-background catalog image."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    ForEach(ShoeAngle.allCases) { angle in
                        Button {
                            guard isAngleAccessible(angle) else { return }
                            currentAngle = angle
                        } label: {
                            HStack(spacing: 10) {
                                statusIcon(for: angle)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(angle.displayName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(
                                            isAngleAccessible(angle) ? Color.black : Color.black.opacity(0.35)
                                        )
                                }
                                Spacer(minLength: 6)

                                angleRowThumbnail(for: angle)

                                if currentAngle == angle {
                                    Text("Editing")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.black.opacity(0.5))
                                        .frame(width: 70, alignment: .trailing)
                                } else if !isAngleAccessible(angle) {
                                    Text("Locked")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.black.opacity(0.35))
                                        .frame(width: 70, alignment: .trailing)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(currentAngle == angle ? Color(.systemGray5) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isAngleAccessible(angle))
                        .opacity(isAngleAccessible(angle) ? 1 : 0.55)
                    }
                }
                .padding(.horizontal, 16)

                if allCaptured, !allPrettified {
                    Button {
                        Task { await prettifyAll() }
                    } label: {
                        HStack {
                            if isProcessing { ProgressView().tint(.white) }
                            Image(systemName: "sparkles")
                            Text(isProcessing ? "Generating…" : "Generate studio photos")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.black))
                    }
                    .disabled(isProcessing || !GeminiService.apiKeyConfigured)
                    .padding(.horizontal, 16)
                } else if allPrettified {
                    Button {
                        saveMultiAngle()
                    } label: {
                        Label("Save to stock", systemImage: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.black))
                    }
                    .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color.black))
                        }
                        .disabled(!canCaptureCurrentAngle)

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Gallery", systemImage: "photo")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color(.systemGray6)))
                        }
                        .disabled(!canCaptureCurrentAngle)
                    }
                    .opacity(canCaptureCurrentAngle ? 1 : 0.45)
                    .padding(.horizontal, 16)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle("360° studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }
                        .foregroundStyle(Color.black)
                }
            }
        }
        .onAppear {
            applyPrefillIfNeeded()
            syncCurrentAngleToFlow()
        }
        .onChange(of: pickerItem) { _, newVal in
            Task { await loadPickedGallery(newVal) }
        }
        .onChange(of: cameraUIImage) { _, newVal in
            guard let newVal, canCaptureCurrentAngle else { return }
            let flat = newVal.closetFlattenedForShoeCapture()
            captured[currentAngle] = flat
            cameraUIImage = nil
            advanceToNextMissingAngle()
        }
        .fullScreenCover(isPresented: $showCamera) {
            ClosetUIImagePickerBridge(image: $cameraUIImage)
                .background(Color.black)
                .ignoresSafeArea()
        }
        .onDisappear {
            stopHeroAutoSpin()
        }
        .onChange(of: allPrettified) { _, ready in
            if ready, orderedPrettifiedPaths.count == ShoeAngle.allCases.count {
                startHeroAutoSpin(frameCount: ShoeAngle.allCases.count)
            } else {
                stopHeroAutoSpin()
            }
        }
    }

    private func applyPrefillIfNeeded() {
        guard !appliedGalleryPrefill,
              let imgs = prefilledCapturedInAngleOrder,
              imgs.count == ShoeAngle.allCases.count
        else { return }
        appliedGalleryPrefill = true
        for (i, img) in imgs.enumerated() {
            captured[ShoeAngle.allCases[i]] = img.closetFlattenedForShoeCapture()
        }
        syncCurrentAngleToFlow()
    }

    private func syncCurrentAngleToFlow() {
        if let missing = firstMissingAngle {
            if !isAngleAccessible(currentAngle) {
                currentAngle = missing
            }
        } else if let last = ShoeAngle.allCases.last {
            currentAngle = last
        }
    }

    @ViewBuilder
    private var captureHeroContent: some View {
        if allPrettified, orderedPrettifiedPaths.count == ShoeAngle.allCases.count {
            ShoeFluidSpinPhaseLayer(filenames: orderedPrettifiedPaths, phase: autoSpinPhase)
                .onAppear { startHeroAutoSpin(frameCount: ShoeAngle.allCases.count) }
        } else if allCaptured, orderedCapturedImages.count == ShoeAngle.allCases.count {
            ShoeCaptureAutoSpinPreview(images: orderedCapturedImages)
        } else if let img = displayHeroImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .padding(12)
        } else if productCategory == .shoes {
            ShoeGuideAngleVideoView(
                resourceName: "Vidos-zapatos",
                fileExtension: "mp4",
                angle: currentAngle,
                videoGravity: .resizeAspect
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(6)
            .animation(.easeInOut(duration: 0.45), value: currentAngle)
        } else {
            VStack(spacing: 12) {
                Image(systemName: currentAngle.icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.22))
                Text(currentAngle.productSlotCue(for: productCategory))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
        }
    }

    private func startHeroAutoSpin(frameCount: Int) {
        autoSpinTimer?.invalidate()
        autoSpinPhase = 0
        let n = max(frameCount, 1)
        autoSpinTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                autoSpinPhase = ShoeFluidSpinMath.normalizePhase(
                    autoSpinPhase + CGFloat(n) / (2.8 * 30),
                    frameCount: n
                )
            }
        }
    }

    private func stopHeroAutoSpin() {
        autoSpinTimer?.invalidate()
        autoSpinTimer = nil
    }

    private var displayHeroImage: UIImage? {
        if let p = prettifiedFilenames[currentAngle], let u = ImageStore.load(p) { return u }
        return captured[currentAngle]
    }

    @ViewBuilder
    private func statusIcon(for angle: ShoeAngle) -> some View {
        if prettifiedFilenames[angle] != nil {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.green)
        } else if captured[angle] != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.black)
        } else if !isAngleAccessible(angle) {
            Image(systemName: "lock.fill").foregroundStyle(Color.gray.opacity(0.45))
        } else if currentAngle == angle {
            Image(systemName: "camera.fill").foregroundStyle(Color.black)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(Color.gray)
        }
    }

    @ViewBuilder
    private func angleRowThumbnail(for angle: ShoeAngle) -> some View {
        Group {
            if let ui = rowThumbUIImage(for: angle) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .frame(width: 46, height: 46)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.gray.opacity(0.75))
                    }
            }
        }
    }

    private func rowThumbUIImage(for angle: ShoeAngle) -> UIImage? {
        if let path = prettifiedFilenames[angle], let loaded = ImageStore.load(path) { return loaded }
        return captured[angle]
    }

    private func advanceToNextMissingAngle() {
        if let next = ShoeAngle.allCases.first(where: { captured[$0] == nil }) {
            currentAngle = next
        }
    }

    private func loadPickedGallery(_ item: PhotosPickerItem?) async {
        guard canCaptureCurrentAngle else { return }
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data)
        else { return }
        let flat = img.closetFlattenedForShoeCapture()
        await MainActor.run {
            captured[currentAngle] = flat
            advanceToNextMissingAngle()
            pickerItem = nil
        }
    }

    @MainActor
    private func prettifyAll() async {
        guard GeminiService.apiKeyConfigured else {
            errorMessage = "Configura GeminiAPIKey para generar la vista 360°."
            return
        }
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        let nameSnapshot = garmentName
        // Una petición de imagen tras otra (evita timeouts -1001 como en lookbook con paralelismo alto).
        for angle in ShoeAngle.allCases {
            guard let img = captured[angle],
                  let jpeg = img.jpegData(compressionQuality: 0.92)
            else { continue }
            let cropName: String
            do {
                let fname = "\(UUID().uuidString.lowercased()).jpg"
                cropName = try ImageStore.save(jpeg, inFolder: "crops", filename: fname)
            } catch {
                continue
            }
            if let pretty = try? await GeminiService.shared.prettifyProductAngle(
                cropRelativePath: cropName,
                angle: angle,
                itemName: nameSnapshot,
                category: productCategory
            ) {
                prettifiedFilenames[angle] = pretty
            }
        }
        let need = ShoeAngle.allCases.count
        if prettifiedFilenames.count < need {
            errorMessage =
                "Some angles were not generated. Retry with Generate 360° view or capture them again."
        }
    }

    private func saveMultiAngle() {
        let ordered = ShoeAngle.allCases.compactMap { prettifiedFilenames[$0] }
        guard ordered.count == ShoeAngle.allCases.count else {
            errorMessage =
                "Missing generated images (you need \(ShoeAngle.allCases.count))."
            return
        }
        onOrderedPathsCommitted(ordered)
        dismiss()
    }
}

private extension UIImage {
    func closetFlattenedForShoeCapture() -> UIImage {
        ClosetPhotoExports.normalizedClosetProductImage(self)
    }

    func closetFlattenedForLookbookCapture() -> UIImage {
        ClosetPhotoExports.normalizedClosetProductImage(self)
    }

    /// Normalizes orientation to `.up` (reused by shoe 360° and lookbook).
    func closetFlattenedUpright() -> UIImage {
        ClosetPhotoExports.normalizedClosetProductImage(self)
    }
}

/// Miniatura estable para vistas compartidas (mismo estilo que en `ClosetViews`).
private struct ClosetDiskThumbnail: View {
    let relativePath: String

    @State private var image: UIImage?

    init(relativePath: String) {
        self.relativePath = relativePath
        let key = StockImageLoader.localCacheKey(relativePath)
        _image = State(initialValue: ImageCacheService.shared.image(forKey: key))
    }

    var body: some View {
        Group {
            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    Color.white
                    ProgressView().tint(.black)
                }
            }
        }
        .background(Color.white)
        .task(id: relativePath) {
            guard image == nil else { return }
            if let loaded = await StockImageLoader.cachedLocalImageAsync(relativePath: relativePath) {
                image = loaded
            }
        }
    }
}

// MARK: - Lookbook (Feature 6): galería en detalle + captura 5 refs → 10 generaciones Gemini

enum ProductCoverGalleryStyle {
    case hero
    case carousel
    case strip
    case detail
}

/// Browse every product image and pick which one appears as the closet cover.
struct ProductCoverGalleryView<PhotoOverlay: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: ClosetItem
    @Binding var toast: String?
    var style: ProductCoverGalleryStyle = .hero
    @ViewBuilder var photoOverlay: () -> PhotoOverlay

    @State private var selectedIndex: Int = 0
    @State private var selectedScrollID: String?
    @State private var exporting = false

    init(
        item: ClosetItem,
        toast: Binding<String?>,
        style: ProductCoverGalleryStyle = .hero,
        @ViewBuilder photoOverlay: @escaping () -> PhotoOverlay = { EmptyView() }
    ) {
        self.item = item
        self._toast = toast
        self.style = style
        self.photoOverlay = photoOverlay
    }

    private var paths: [String] { item.allSelectableImagePaths }

    private var currentPathIfAny: String? {
        guard paths.indices.contains(selectedIndex) else { return nil }
        return paths[selectedIndex]
    }

    private var activeCoverPath: String {
        ImageStore.preferredCatalogCoverPath(for: item)
    }

    private var isCurrentSelectionCover: Bool {
        guard let current = currentPathIfAny else { return false }
        return current == activeCoverPath
    }

    var body: some View {
        Group {
            switch style {
            case .hero:
                heroGalleryBody
            case .carousel:
                carouselGalleryBody
            case .strip:
                stripGalleryBody
            case .detail:
                detailGalleryBody
            }
        }
        .onAppear {
            syncSelectedFromCoverPreference()
            syncScrollIDFromIndex()
        }
        .onChange(of: paths.count) { _, newCount in
            guard newCount > 0 else {
                selectedIndex = 0
                selectedScrollID = nil
                return
            }
            selectedIndex = min(selectedIndex, newCount - 1)
            syncSelectedFromCoverPreference()
            syncScrollIDFromIndex()
        }
        .onChange(of: item.galleryCoverRelativePath) { _, _ in
            syncSelectedFromCoverPreference()
            syncScrollIDFromIndex()
        }
        .onChange(of: selectedIndex) { _, _ in
            syncScrollIDFromIndex()
        }
        .onChange(of: selectedScrollID) { _, newID in
            guard let newID, let idx = paths.firstIndex(of: newID), idx != selectedIndex else { return }
            selectedIndex = idx
        }
    }

    private var detailGalleryBody: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                carouselBlock

                if currentPathIfAny != nil {
                    VStack(spacing: 8) {
                        photoOverlay()
                        heroActionBar
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            .aspectRatio(0.72, contentMode: .fit)
            .padding(4)

            stripGalleryBody
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    private var heroGalleryBody: some View {
        VStack(spacing: 12) {
            carouselPane(showPhotoOverlay: false)

            thumbnailStrip
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var carouselGalleryBody: some View {
        carouselPane(showPhotoOverlay: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func carouselPane(showPhotoOverlay: Bool) -> some View {
        ZStack(alignment: .bottom) {
            carouselBlock

            if currentPathIfAny != nil {
                VStack(spacing: 8) {
                    if showPhotoOverlay {
                        photoOverlay()
                    }
                    heroActionBar
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(minHeight: style == .hero ? 280 : 0)
    }

    private var stripGalleryBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Cover photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer(minLength: 8)
                if isCurrentSelectionCover {
                    Label("Current cover", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.72))
                } else if currentPathIfAny != nil {
                    Button {
                        setCurrentAsCover()
                    } label: {
                        Text("Set as cover")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.black))
                    }
                    .buttonStyle(LookNoHighlightButtonStyle())
                }
            }

            thumbnailStrip
        }
        .padding(.top, 4)
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(paths.enumerated()), id: \.offset) { i, rel in
                        thumbnailTile(rel, index: i)
                            .id(rel)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: selectedIndex) { _, new in
                guard paths.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(paths[new], anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnailTile(_ rel: String, index: Int) -> some View {
        if let ui = ImageStore.load(rel) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: style == .strip ? 72 : 76,
                        height: style == .strip ? 92 : 98
                    )
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                index == selectedIndex ? Color.black : Color.black.opacity(0.08),
                                lineWidth: index == selectedIndex ? 2 : 1
                            )
                    )
                    .onTapGesture {
                        selectedIndex = index
                        selectedScrollID = rel
                    }

                if rel == activeCoverPath {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.72)))
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    @ViewBuilder
    private var carouselBlock: some View {
        Group {
            if paths.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(paths, id: \.self) { rel in
                            heroImageTile(rel)
                                .containerRelativeFrame(.horizontal)
                                .id(rel)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedScrollID)
                .scrollIndicators(.hidden)
                .overlay(alignment: .topTrailing) {
                    if paths.indices.contains(selectedIndex) {
                        Text("\(selectedIndex + 1) / \(paths.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.52)))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
            } else if let only = paths.first {
                heroImageTile(only)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(height: 280)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func heroImageTile(_ rel: String) -> some View {
        Group {
            if let ui = ImageStore.load(rel) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var heroActionBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await saveCurrentToPhotos() }
            } label: {
                HStack(spacing: 6) {
                    if exporting {
                        ProgressView().scaleEffect(0.85).tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text("Save to Photos")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.52)))
            }
            .buttonStyle(LookNoHighlightButtonStyle())
            .disabled(exporting)

            Button {
                setCurrentAsCover()
            } label: {
                HStack(spacing: 6) {
                    Image(
                        systemName: isCurrentSelectionCover
                            ? "checkmark.circle.fill"
                            : "photo.on.rectangle.angled"
                    )
                    Text(isCurrentSelectionCover ? "Cover photo" : "Set as cover")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(LookNoHighlightButtonStyle())
            .disabled(isCurrentSelectionCover)
        }
    }

    private func syncSelectedFromCoverPreference() {
        let cover = activeCoverPath
        guard !cover.isEmpty, let idx = paths.firstIndex(of: cover) else { return }
        selectedIndex = idx
    }

    private func syncScrollIDFromIndex() {
        guard paths.indices.contains(selectedIndex) else {
            selectedScrollID = paths.first
            return
        }
        selectedScrollID = paths[selectedIndex]
    }

    private func setCurrentAsCover() {
        guard let p = currentPathIfAny else { return }
        item.galleryCoverRelativePath = p
        try? modelContext.save()
        toast = "This photo is now the closet cover."
    }

    @MainActor
    private func saveCurrentToPhotos() async {
        guard let p = currentPathIfAny else { return }
        exporting = true
        defer { exporting = false }
        do {
            try await ClosetPhotoExports.saveRelativeClosetImageToPhotoAlbum(relativePath: p)
            toast = "Saved to Photos."
        } catch {
            toast = error.localizedDescription
        }
    }
}

/// Backward-compatible alias for lookbook-only call sites.
typealias LookbookGalleryView = ProductCoverGalleryView<EmptyView>

struct GarmentLookbookCaptureView: View {
    @Bindable var item: ClosetItem
    /// Sólo el flujo «Ropa / lookbook» independiente; si cierras sin guardar lookbook, borra la fila provisional y miniaturas locales.
    var onAbortStandaloneDraftNotYetSaved: ((ClosetItem) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var currentAngle: GarmentAngle = .front
    @State private var captured: [GarmentAngle: UIImage] = [:]
    @State private var studioResults: [LookbookStudioShot: String] = [:]
    @State private var lifestyleResults: [LookbookLifestyleShot: String] = [:]

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraUIImage: UIImage?
    @State private var isGenerating = false
    @State private var progressCount = 0
    @State private var errorMessage: String?

    private var profile: UserProfile? { profiles.first }

    private var allCaptured: Bool {
        GarmentAngle.allCases.allSatisfy { captured[$0] != nil }
    }

    private var totalTasks: Int {
        LookbookStudioShot.allCases.count + LookbookLifestyleShot.allCases.count
    }

    private var totalGenerated: Int { studioResults.count + lifestyleResults.count }

    private var facePathForGeneration: String? {
        guard let p = profile, p.useFaceByDefault else { return nil }
        let fp = (p.faceImageFilename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return fp.isEmpty ? nil : fp
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(
                    "\(totalTasks) images will be created in order: studio first, then lifestyle. "
                        + "For stability each one is sent to Gemini separately."
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

                heroBlock

                Text(currentAngle.instruction)
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                angleListBlock

                actionBlock

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                }
            }
            .padding(.bottom, 30)
        }
        .navigationTitle("Lookbook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.close")) {
                    if !item.hasLookbook {
                        onAbortStandaloneDraftNotYetSaved?(item)
                    }
                    dismiss()
                }
                .foregroundStyle(Color.black)
            }
        }
        .onChange(of: pickerItem) { _, val in Task { await loadPickedGallery(val) } }
        .onChange(of: cameraUIImage) { _, newVal in
            guard let img = newVal else { return }
            captured[currentAngle] = img.closetFlattenedForLookbookCapture()
            cameraUIImage = nil
            advanceMissingAngle()
        }
        .fullScreenCover(isPresented: $showCamera) {
            ClosetUIImagePickerBridge(image: $cameraUIImage)
                .background(Color.black)
                .ignoresSafeArea()
        }
    }

    private var heroBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.white)
            if let img = captured[currentAngle] {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .background(Color.white)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: currentAngle.icon)
                        .font(.system(size: 52))
                        .foregroundStyle(Color.gray)
                    Text(currentAngle.displayName)
                        .font(.title3.bold())
                }
                .foregroundStyle(Color.black.opacity(0.55))
            }
        }
        .frame(height: 260)
        .padding(.horizontal, 16)
    }

    private var angleListBlock: some View {
        VStack(spacing: 8) {
            ForEach(GarmentAngle.allCases) { angle in
                Button {
                    currentAngle = angle
                } label: {
                    HStack {
                        angleStatus(for: angle)
                        Text(angle.displayName)
                            .foregroundStyle(Color.black)
                        Spacer()
                        if currentAngle == angle {
                            Text("Current")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.black.opacity(0.52))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(currentAngle == angle ? Color(.systemGray5) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func angleStatus(for angle: GarmentAngle) -> some View {
        if captured[angle] != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
        } else if currentAngle == angle {
            Image(systemName: "camera.fill").foregroundStyle(Color.black)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(Color.gray)
        }
    }

    @ViewBuilder
    private var actionBlock: some View {
        if !allCaptured {
            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("Tomar foto", systemImage: "camera")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black))
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Gallery", systemImage: "photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color(.systemGray6)))
                }
            }
            .padding(.horizontal, 16)
        } else if totalGenerated < totalTasks && !isGenerating {
            Button {
                Task { await generateAllLookbookImages() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Generate \(totalTasks) AI images")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.black.opacity(GeminiService.apiKeyConfigured ? 1 : 0.42)))
            }
            .disabled(!GeminiService.apiKeyConfigured || isGenerating)
            .padding(.horizontal, 16)
        } else if isGenerating {
            VStack(spacing: 8) {
                ProgressView(value: Double(progressCount), total: Double(totalTasks))
                    .tint(.black)
                Text("Generating… \(progressCount)/\(totalTasks)")
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.54))
            }
            .padding(.horizontal, 24)
        } else {
            previewsBlock
            Button {
                persistLookbook()
            } label: {
                Label("Save lookbook", systemImage: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.black))
            }
            .padding(.horizontal, 16)
        }
    }

    private var previewsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Studio (\(studioResults.count)/\(LookbookStudioShot.allCases.count))")
                .font(.headline)
                .padding(.horizontal, 16)
            horizontalThumbRow(LookbookStudioShot.allCases.compactMap { studioResults[$0] })
                .padding(.horizontal, 16)

            Text("Lifestyle (\(lifestyleResults.count)/\(LookbookLifestyleShot.allCases.count))")
                .font(.headline)
                .padding(.horizontal, 16)
            horizontalThumbRow(LookbookLifestyleShot.allCases.compactMap { lifestyleResults[$0] })
                .padding(.horizontal, 16)
        }
    }

    private func horizontalThumbRow(_ filenames: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filenames, id: \.self) { rel in
                    if let ui = ImageStore.load(rel) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func advanceMissingAngle() {
        if let next = GarmentAngle.allCases.first(where: { captured[$0] == nil }) {
            currentAngle = next
        }
    }

    @MainActor
    private func loadPickedGallery(_ picker: PhotosPickerItem?) async {
        guard let picker,
              let data = try? await picker.loadTransferable(type: Data.self),
              let img = UIImage(data: data)
        else { return }
        captured[currentAngle] = img.closetFlattenedForLookbookCapture()
        advanceMissingAngle()
        pickerItem = nil
    }

    @MainActor
    private func generateAllLookbookImages() async {
        guard GeminiService.apiKeyConfigured else {
            errorMessage = "Configura GeminiAPIKey para generar el lookbook."
            return
        }
        var refs: [String] = []
        refs.reserveCapacity(GarmentAngle.allCases.count)
        for angle in GarmentAngle.allCases {
            guard let img = captured[angle],
                  let j = img.jpegData(compressionQuality: 0.92)
            else {
                errorMessage = "Missing photos for some angles."
                return
            }
            do {
                let rel = try ImageStore.save(j, inFolder: "crops", filename: "\(UUID().uuidString.lowercased()).jpg")
                refs.append(rel)
            } catch {
                errorMessage = "No se pudo guardar un recorte temporal."
                return
            }
        }

        studioResults.removeAll()
        lifestyleResults.removeAll()

        errorMessage = nil
        let nameSnap = item.name
        let face = facePathForGeneration
        progressCount = 0
        isGenerating = true
        defer { isGenerating = false }

        // Secuencial: 10 llamadas paralelas saturan la sesión/red y expiran antes de terminar (~60s antes de este cambio).
        for variant in LookbookStudioShot.allCases {
            do {
                let path = try await GeminiService.shared.generateLookbookStudio(
                    referenceRelativePaths: refs,
                    variant: variant,
                    itemName: nameSnap)
                await MainActor.run {
                    studioResults[variant] = path
                    progressCount += 1
                }
            } catch {
                await MainActor.run { progressCount += 1 }
            }
        }
        for variant in LookbookLifestyleShot.allCases {
            do {
                let path = try await GeminiService.shared.generateLookbookLifestyle(
                    referenceRelativePaths: refs,
                    variant: variant,
                    itemName: nameSnap,
                    faceReferenceRelativePath: face)
                await MainActor.run {
                    lifestyleResults[variant] = path
                    progressCount += 1
                }
            } catch {
                await MainActor.run { progressCount += 1 }
            }
        }

        let got = studioResults.count + lifestyleResults.count
        if got < totalTasks {
            errorMessage =
                "Se generaron \(got) de \(totalTasks) imágenes. Puedes guardar las que funcionaron."
        }
        ClosetAnalytics.named("closet_lookbook_generate", params: "ok:\(got)")
    }

    private func persistLookbook() {
        let oldStudio = item.lookbookStudio
        let oldLife = item.lookbookLifestyle
        let prevThumb = item.imageFilename
        item.lookbookStudio = LookbookStudioShot.allCases.compactMap { studioResults[$0] }
        item.lookbookLifestyle = LookbookLifestyleShot.allCases.compactMap { lifestyleResults[$0] }
        for p in oldStudio { ImageStore.deleteIfExists(p) }
        for p in oldLife { ImageStore.deleteIfExists(p) }
        if let firstStudio = item.lookbookStudio.first {
            item.imageFilename = firstStudio
            if prevThumb.contains("pending_lookbook") {
                ImageStore.deleteIfExists(prevThumb)
            }
        }
        try? modelContext.save()
        ClosetAnalytics.named("closet_lookbook_saved")
        dismiss()
    }
}
