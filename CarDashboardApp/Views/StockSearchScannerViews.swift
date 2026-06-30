import AVFoundation
import SwiftUI
import UIKit

// MARK: - Stock image cache (scroll fluido, sin recargas)

enum StockImageLoader {
    private actor InflightCoordinator {
        static let shared = InflightCoordinator()
        var tasks: [String: Task<UIImage?, Never>] = [:]

        func existing(for key: String) -> Task<UIImage?, Never>? { tasks[key] }
        func register(_ task: Task<UIImage?, Never>, for key: String) { tasks[key] = task }
        func remove(for key: String) { tasks.removeValue(forKey: key) }
    }

    static func localCacheKey(_ path: String) -> String { "stock:local:\(path)" }
    static func urlCacheKey(_ url: URL) -> String { "stock:url:\(url.absoluteString)" }

    static func cachedLocalImage(relativePath: String) -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let key = localCacheKey(relativePath)
        if let mem = ImageCacheService.shared.image(forKey: key) { return mem }
        // Decodifica directamente a tamaño de miniatura desde disco (sin cargar el bitmap
        // completo en memoria). Evita guardar fotos a resolución completa en la caché y
        // elimina los tirones por evicción/re-decodificación durante el scroll.
        guard let ui = downsampledLocalImage(relativePath: relativePath, maxSide: 400)
            ?? ImageStore.load(relativePath) else { return nil }
        ImageCacheService.shared.store(ui, forKey: key)
        return ui
    }

    /// Carga + downsample desde disco usando `CGImageSource` (no decodifica la imagen completa).
    static func downsampledLocalImage(relativePath: String, maxSide: CGFloat) -> UIImage? {
        let url = ImageStore.url(forRelativePath: relativePath)
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxSide * 3),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Versión asíncrona: hace el decode/downsample fuera del hilo principal.
    static func cachedLocalImageAsync(relativePath: String) async -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let key = localCacheKey(relativePath)
        if let mem = ImageCacheService.shared.image(forKey: key) { return mem }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            downsampledLocalImage(relativePath: relativePath, maxSide: 400)
                ?? ImageStore.load(relativePath)
        }.value
        if let image { ImageCacheService.shared.store(image, forKey: key) }
        return image
    }

    static func memoryCachedURLImage(for url: URL) -> UIImage? {
        ImageCacheService.shared.image(forKey: urlCacheKey(url))
    }

    static func cachedURLImage(for url: URL) async -> UIImage? {
        let key = urlCacheKey(url)
        if let mem = ImageCacheService.shared.image(forKey: key) { return mem }

        if let existing = await InflightCoordinator.shared.existing(for: key) {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            defer { Task { await InflightCoordinator.shared.remove(for: key) } }
            do {
                let (data, _) = try await CarUIImageLoader.imageSession.data(from: url)
                guard let raw = UIImage(data: data) else { return nil }
                let img = downsampleIfNeeded(raw, maxSide: 176)
                ImageCacheService.shared.store(img, forKey: key)
                return img
            } catch {
                return nil
            }
        }
        await InflightCoordinator.shared.register(task, for: key)
        return await task.value
    }

    private static func downsampleIfNeeded(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > maxSide else { return image }
        let scale = maxSide / maxDim
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

struct StockCachedRemoteImage: View {
    let url: URL?

    @State private var image: UIImage?

    init(url: URL?) {
        self.url = url
        if let url {
            _image = State(initialValue: StockImageLoader.memoryCachedURLImage(for: url))
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if url != nil {
                Color.white
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.black.opacity(0.22))
            }
        }
        .task(id: url?.absoluteString) {
            guard let url, image == nil else { return }
            if let loaded = await StockImageLoader.cachedURLImage(for: url) {
                image = loaded
            }
        }
    }
}

// MARK: - Layout mode

enum StockLayoutMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .grid: return L10n.tr("closet.layoutGrid")
        case .list: return L10n.tr("closet.layoutList")
        }
    }
}

// MARK: - Profit badge (grid cards)

struct StockProfitCornerBadge: View {
    let usdLabel: String?
    let pctLabel: String?
    let isLoss: Bool

    var body: some View {
        let tint = isLoss
            ? Color(red: 0.92, green: 0.30, blue: 0.30)
            : Color(red: 0.20, green: 0.70, blue: 0.45)

        VStack(alignment: .trailing, spacing: 2) {
            if let usd = usdLabel {
                Text(usd)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            if let pct = pctLabel {
                Text(pct)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint)
                .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Stock market overview (summary card)

struct StockMarketOverviewStrip: View {
    let snapshot: DashboardMarketSnapshot

    private var tint: Color {
        snapshot.isUp
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                Text("MARKET LIVE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.black.opacity(0.50))
                Spacer(minLength: 0)
                if snapshot.trackedCount > 0 {
                    Text("\(snapshot.trackedCount) tracked")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.38))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DealershipStatsViewModel.formatUSD(snapshot.totalLiveValueUSD))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text("average")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.black.opacity(0.42))
                    .padding(.bottom, 2)
                Spacer(minLength: 0)
                stockTrendBadge
            }

            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.18, green: 0.65, blue: 0.40))
                    Text("From \(DealershipStatsViewModel.formatUSD(snapshot.minUSD))")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.35))
                    Text("Up to \(DealershipStatsViewModel.formatUSD(snapshot.maxUSD))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.42))
                }
            }

            if snapshot.history.count >= 2 {
                PriceTrendSparkline(points: snapshot.history, isUp: snapshot.isUp)
                    .frame(height: 44)
            }

            if snapshot.hasPlatformBreakdown {
                HStack(spacing: 8) {
                    ForEach(snapshot.platforms) { platform in
                        PlatformPriceTag(
                            platform: platform,
                            formatted: PieceMarketPrice.formatUSD(platform.avg)
                        )
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 8) {
                    stockPlaceholderPlatformChip(name: "StockX", color: PlatformPrice.brandColor(for: "StockX"))
                    stockPlaceholderPlatformChip(name: "GOAT", color: PlatformPrice.brandColor(for: "GOAT"))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.07), Color.white],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 1)
                }
        }
    }

    private var stockTrendBadge: some View {
        let pct = snapshot.changePercent
        return HStack(spacing: 2) {
            Image(systemName: snapshot.isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .heavy))
            Text(DealershipStatsViewModel.formatChangePercent(pct))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func stockPlaceholderPlatformChip(name: String, color: Color) -> some View {
        HStack(spacing: 6) {
            PlatformBrandBadge(name: name, color: color, size: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(name.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.black.opacity(0.45))
                Text("Loading…")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.30))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

/// Compact platform price row for stock list cells.
struct StockRowPlatformChip: View {
    let platform: PlatformPrice
    var isPreferred: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            PlatformBrandBadge(name: platform.name, color: platform.color, size: 16)
            Text(PieceMarketPrice.formatUSD(platform.avg))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(isPreferred ? 0.92 : 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPreferred ? platform.color.opacity(0.10) : Color.white.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(platform.color.opacity(isPreferred ? 0.35 : 0.18), lineWidth: 1)
                }
        }
    }
}

// MARK: - Marketplace list row (sparkline + platform price)

struct StockItemSparkline {
    let points: [Double]
    let isUp: Bool

    static func resolve(
        marketPrice: PieceMarketPrice?,
        preferredPlatform: String?,
        stockValueUSD: Double,
        purchaseUSD: Double,
        askingUSD: Double
    ) -> StockItemSparkline {
        let platform = StockMarketRowMetrics.resolvedPlatform(from: marketPrice, preferred: preferredPlatform)
        var points = StockMarketRowMetrics.sparklinePoints(from: marketPrice, platform: platform)
        var isUp = StockMarketRowMetrics.trendPercent(from: marketPrice, platform: platform) >= 0

        if points.count < 2 {
            points = StockMarketRowMetrics.inventorySparkline(
                stockValueUSD: stockValueUSD,
                purchaseUSD: purchaseUSD,
                askingUSD: askingUSD
            )
            if points.count >= 2, let first = points.first, let last = points.last, first > 0 {
                isUp = last >= first
            }
        }

        return StockItemSparkline(points: points, isUp: isUp)
    }
}

private enum StockMarketRowMetrics {
    static func resolvedPlatform(from estimate: PieceMarketPrice?, preferred: String?) -> PlatformPrice? {
        guard let estimate else { return nil }
        if let preferred {
            return estimate.platforms.first {
                $0.name.caseInsensitiveCompare(preferred) == .orderedSame
            }
        }
        return estimate.platforms.first { $0.name == "StockX" }
            ?? estimate.platforms.first { $0.name == "GOAT" }
            ?? estimate.platforms.first
    }

    static func sparklinePoints(from estimate: PieceMarketPrice?, platform: PlatformPrice?) -> [Double] {
        if let platform, platform.history.count >= 2 { return platform.history }
        if let estimate, estimate.history.count >= 2 { return estimate.history }
        if let platform, platform.avg > 0 {
            let v = Double(platform.avg)
            return [v * 0.92, v * 0.97, v]
        }
        if let estimate, estimate.avg > 0 {
            let v = Double(estimate.avg)
            return [v * 0.92, v * 0.97, v]
        }
        return []
    }

    /// Curva suave cuando aún no hay histórico de mercado (coste → valor actual).
    static func inventorySparkline(
        stockValueUSD: Double,
        purchaseUSD: Double,
        askingUSD: Double
    ) -> [Double] {
        let current = stockValueUSD > 0 ? stockValueUSD : (askingUSD > 0 ? askingUSD : purchaseUSD)
        guard current > 0 else { return [] }

        let start: Double
        if purchaseUSD > 0 {
            start = min(purchaseUSD, current * 0.92)
        } else if askingUSD > 0, askingUSD != current {
            start = min(askingUSD * 0.94, current * 0.9)
        } else {
            start = current * 0.82
        }

        return [
            start,
            start + (current - start) * 0.28,
            start + (current - start) * 0.52,
            start + (current - start) * 0.74,
            current * 0.97,
            current,
        ]
    }

    static func trendPercent(from estimate: PieceMarketPrice?, platform: PlatformPrice?) -> Double {
        let points = sparklinePoints(from: estimate, platform: platform)
        guard points.count >= 2, let first = points.first, first > 0, let last = points.last else {
            return estimate?.changePercent ?? 0
        }
        return ((last - first) / first) * 100
    }

    static func deltaUSD(from estimate: PieceMarketPrice?, platform: PlatformPrice?) -> Double {
        let points = sparklinePoints(from: estimate, platform: platform)
        guard points.count >= 2, let first = points.first, let last = points.last else { return 0 }
        return last - first
    }
}

struct StockMarketplaceListRow<ImageContent: View>: View {
    let brandLine: String
    let nameLine: String
    var sizeLabel: String? = nil
    var fallbackPrice: String? = nil
    var marketPrice: PieceMarketPrice? = nil
    var preferredPlatform: String? = nil
    var stockValueUSD: Double = 0
    var purchaseUSD: Double = 0
    var askingUSD: Double = 0
    var profitUSD: String? = nil
    var profitPct: String? = nil
    var isLoss: Bool = false
    var showProfitBadge: Bool = false
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var onTap: () -> Void
    @ViewBuilder var image: () -> ImageContent

    private var sparkBundle: StockItemSparkline {
        StockItemSparkline.resolve(
            marketPrice: marketPrice,
            preferredPlatform: preferredPlatform,
            stockValueUSD: stockValueUSD,
            purchaseUSD: purchaseUSD,
            askingUSD: askingUSD
        )
    }

    private var sparkPoints: [Double] { sparkBundle.points }

    private var trendUp: Bool { sparkBundle.isUp }

    private var deltaUSD: Double {
        StockMarketRowMetrics.deltaUSD(
            from: marketPrice,
            platform: StockMarketRowMetrics.resolvedPlatform(from: marketPrice, preferred: preferredPlatform)
        )
    }

    private var platform: PlatformPrice? {
        StockMarketRowMetrics.resolvedPlatform(from: marketPrice, preferred: preferredPlatform)
    }

    private var displayPlatforms: [PlatformPrice] {
        guard let marketPrice, !marketPrice.platforms.isEmpty else { return [] }
        let order = ["StockX", "GOAT", "Flight Club"]
        var result = order.compactMap { name in
            marketPrice.platforms.first { $0.name == name && $0.avg > 0 }
        }
        if let preferred = preferredPlatform,
           let idx = result.firstIndex(where: { $0.name.caseInsensitiveCompare(preferred) == .orderedSame }),
           idx > 0 {
            let preferredItem = result.remove(at: idx)
            result.insert(preferredItem, at: 0)
        }
        return result
    }

    private var displayPriceUSD: Int {
        platform?.avg ?? marketPrice?.avg ?? Int(stockValueUSD.rounded())
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 6) {
                thumbnailBlock
                productInfoBlock
                Spacer(minLength: 4)
                priceBlock
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selectionMode && isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                }
            }
            .overlay {
                if selectionMode && isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.55), lineWidth: 2)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var thumbnailBlock: some View {
        ZStack(alignment: .topTrailing) {
            image()
                .frame(width: 58, height: 58)
                .background(Color.white)
                .clipped()

            if showProfitBadge, !selectionMode {
                StockProfitCornerBadge(
                    usdLabel: profitUSD,
                    pctLabel: profitPct,
                    isLoss: isLoss
                )
                .scaleEffect(0.62)
                .offset(x: 2, y: -2)
            }

            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black : Color.black.opacity(0.25))
                    .background(Circle().fill(Color.white))
                    .offset(x: 2, y: -2)
            }
        }
    }

    private var productInfoBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(brandLine)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.48))
                .lineLimit(1)

            Text(nameLine)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let sizeLabel {
                Text("Size \(sizeLabel)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priceBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if !displayPlatforms.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(displayPlatforms.prefix(2)) { platform in
                        StockRowPlatformChip(
                            platform: platform,
                            isPreferred: {
                                if let preferred = preferredPlatform {
                                    return platform.name.caseInsensitiveCompare(preferred) == .orderedSame
                                }
                                return platform.name == "StockX"
                            }()
                        )
                    }
                }

                Text("Market price")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.40))

                if sparkPoints.count >= 2 {
                    deltaLabel
                }
            } else if let platform {
                PlatformBrandBadge(name: platform.name, color: platform.color, size: 20)

                if displayPriceUSD > 0 {
                    Text(PieceMarketPrice.formatUSD(displayPriceUSD))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("Current price")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.40))

                    if sparkPoints.count >= 2 {
                        deltaLabel
                    }
                }
            } else if displayPriceUSD > 0 || stockValueUSD > 0 || askingUSD > 0 {
                Text(PieceMarketPrice.formatUSD(Int((stockValueUSD > 0 ? stockValueUSD : askingUSD).rounded())))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(marketPrice == nil ? "Estimated value" : "Current price")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.40))

                if sparkPoints.count >= 2 {
                    deltaLabel
                }
            } else if let fallbackPrice {
                Text(fallbackPrice)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Your price")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.40))
            } else {
                Text("—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
        }
        .frame(minWidth: 82, maxWidth: 98, alignment: .trailing)
    }

    private var deltaLabel: some View {
        let tint = trendUp
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)
        let amount = Int(abs(deltaUSD).rounded())

        return HStack(spacing: 2) {
            Image(systemName: trendUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .heavy))
            Text("\(trendUp ? "+" : "−")\(PieceMarketPrice.formatUSD(amount))")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
            Text("(24h)")
                .font(.system(size: 7, weight: .medium))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

struct StockMarketplaceListDivider: View {
    var body: some View {
        Color.clear.frame(height: 10)
    }
}

// MARK: - Search bar (reference: pill + barcode inside)

struct StockBrowseSearchBar: View {
    @Binding var searchText: String
    @FocusState.Binding var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))

            TextField("", text: $searchText, prompt: Text(L10n.tr("closet.searchPrompt")).foregroundStyle(Color.black.opacity(0.38)))
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.black.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            LiquidGlassSearchPillBackground()
        }
    }
}

// MARK: - Stock browse filters

enum StockSortOrder: String, CaseIterable, Identifiable {
    case newest
    case priceLowHigh
    case priceHighLow
    case sizeLowHigh
    case sizeHighLow
    case brandAZ

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest"
        case .priceLowHigh: return "Price: low → high"
        case .priceHighLow: return "Price: high → low"
        case .sizeLowHigh: return "Size: low → high"
        case .sizeHighLow: return "Size: high → low"
        case .brandAZ: return "Brand A → Z"
        }
    }

    var menuLabel: String {
        switch self {
        case .newest: return "Featured"
        case .priceLowHigh: return "Price ↑"
        case .priceHighLow: return "Price ↓"
        case .sizeLowHigh: return "Size ↑"
        case .sizeHighLow: return "Size ↓"
        case .brandAZ: return "Brand A–Z"
        }
    }
}

enum StockQuickCategory: String, CaseIterable, Identifiable {
    case all
    case shoes
    case clothing
    case accessories
    case bags

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .shoes: return "Shoes"
        case .clothing: return "Clothing"
        case .accessories: return "Accessories"
        case .bags: return "Bags"
        }
    }

    var emoji: String {
        switch self {
        case .all: return "✨"
        case .shoes: return "👞"
        case .clothing: return "👔"
        case .accessories: return "⌚"
        case .bags: return "👜"
        }
    }

    var categoryKeys: Set<String> {
        switch self {
        case .all: return []
        case .shoes: return ["shoes"]
        case .clothing: return [
            "clothing", "tops", "dresses_jumpsuits", "pants_skirts", "coats", "underwear",
            "vintage", "new-drops", "new_drops",
        ]
        case .accessories: return ["accessories"]
        case .bags: return ["bags"]
        }
    }
}

struct StockBrowseFilters: Equatable {
    var sort: StockSortOrder = .newest
    var categoryKeys: Set<String> = []
    var brands: Set<String> = []
    var sizes: Set<String> = []
    var availableNow = false
    var expressShipping = false
    var belowRetail = false
    var genders: Set<String> = []
    var shoeHeights: Set<String> = []
    var activities: Set<String> = []
    var sneakerStyles: Set<String> = []
    /// StockX / GOAT — item must have live price on at least one selected platform.
    var marketplacePlatforms: Set<String> = []

    var preferredMarketplacePlatform: String? {
        if marketplacePlatforms.count == 1 {
            return marketplacePlatforms.first
        }
        if marketplacePlatforms.contains("StockX") { return "StockX" }
        if marketplacePlatforms.contains("GOAT") { return "GOAT" }
        return nil
    }

    var quickCategory: StockQuickCategory {
        get {
            if categoryKeys.isEmpty { return .all }
            for quick in StockQuickCategory.allCases where quick != .all {
                if categoryKeys == quick.categoryKeys { return quick }
            }
            return .all
        }
        set {
            categoryKeys = newValue.categoryKeys
        }
    }

    var isActive: Bool {
        !categoryKeys.isEmpty
            || !brands.isEmpty
            || !sizes.isEmpty
            || !genders.isEmpty
            || !shoeHeights.isEmpty
            || !activities.isEmpty
            || !sneakerStyles.isEmpty
            || !marketplacePlatforms.isEmpty
            || availableNow
            || expressShipping
            || belowRetail
            || sort != .newest
    }

    mutating func reset() {
        sort = .newest
        categoryKeys = []
        brands = []
        sizes = []
        availableNow = false
        expressShipping = false
        belowRetail = false
        genders = []
        shoeHeights = []
        activities = []
        sneakerStyles = []
        marketplacePlatforms = []
    }
}

enum StockFilterEngine {
    static func closetCategoryKey(_ item: ClosetItem) -> String {
        item.category.rawValue
    }

    static func catalogCategoryKey(_ product: UpsoledProduct) -> String {
        let raw = (product.category ?? "other").lowercased()
        if ClothingCategory(rawValue: raw) != nil { return raw }
        switch raw {
        case "clothing": return "clothing"
        case "new-drops", "new_drops": return "new-drops"
        default: return raw
        }
    }

    static func brandKey(_ raw: String?) -> String? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !t.isEmpty, t.lowercased() != "unknown brand" else { return nil }
        return t
    }

    static func matches(_ filters: StockBrowseFilters, closetItem item: ClosetItem) -> Bool {
        if !filters.categoryKeys.isEmpty,
           !filters.categoryKeys.contains(closetCategoryKey(item)) {
            return false
        }
        if !filters.sneakerStyles.isEmpty, closetCategoryKey(item) != ClothingCategory.shoes.rawValue {
            return false
        }
        if !filters.brands.isEmpty {
            guard let b = brandKey(item.brand), filters.brands.contains(b) else { return false }
        }
        if !filters.sizes.isEmpty {
            guard let s = StockSizeDisplay.normalizedStorage(from: item.sizeText),
                  filters.sizes.contains(s) else { return false }
        }
        if filters.belowRetail, !isBelowRetail(closetItem: item) { return false }
        if !filters.genders.isEmpty, !matchesGender(filters.genders, item: item) { return false }
        if !filters.marketplacePlatforms.isEmpty, !matchesMarketplace(filters.marketplacePlatforms, item: item) {
            return false
        }
        return true
    }

    static func matches(_ filters: StockBrowseFilters, catalogProduct product: UpsoledProduct) -> Bool {
        if !filters.categoryKeys.isEmpty,
           !filters.categoryKeys.contains(catalogCategoryKey(product)) {
            return false
        }
        if !filters.sneakerStyles.isEmpty {
            let key = catalogCategoryKey(product)
            guard key == "shoes" || key == "sneakers" || key == "footwear" else { return false }
        }
        if !filters.brands.isEmpty {
            guard let b = brandKey(product.brand), filters.brands.contains(b) else { return false }
        }
        if !filters.sizes.isEmpty {
            let productSizes = product.sizes.compactMap { StockSizeDisplay.normalizedStorage(from: $0) }
            guard productSizes.contains(where: { filters.sizes.contains($0) }) else { return false }
        }
        if filters.belowRetail, !isBelowRetail(catalogProduct: product) { return false }
        return true
    }

    private static func isBelowRetail(closetItem item: ClosetItem) -> Bool {
        let asking = ClosetItem.parsePriceUSD(from: item.priceText)
        guard asking > 0, let market = item.marketPrice, market.min > 0 else { return false }
        return asking < Double(market.min)
    }

    private static func isBelowRetail(catalogProduct product: UpsoledProduct) -> Bool {
        guard product.price > 0, product.purchaseCostUSD > 0 else { return false }
        return product.price < product.purchaseCostUSD
    }

    private static func matchesGender(_ genders: Set<String>, item: ClosetItem) -> Bool {
        let blob = "\(item.name) \(item.brand ?? "")".lowercased()
        for gender in genders {
            switch gender {
            case "men":
                if blob.contains("men") || blob.contains("hombre") { return true }
            case "women":
                if blob.contains("women") || blob.contains("mujer") || blob.contains("wmns") { return true }
            case "kids":
                if blob.contains("kid") || blob.contains("gs") || blob.contains("niño") { return true }
            case "unisex":
                if blob.contains("unisex") { return true }
            default: break
            }
        }
        return false
    }

    private static func matchesMarketplace(_ platforms: Set<String>, item: ClosetItem) -> Bool {
        guard let mp = item.marketPrice else { return false }
        let available = Set(mp.platforms.map(\.name))
        return !platforms.isDisjoint(with: available)
    }

    static func sortClosetItems(_ items: [ClosetItem], by order: StockSortOrder) -> [ClosetItem] {
        switch order {
        case .newest:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .priceLowHigh:
            return items.sorted { $0.stockValueUSD < $1.stockValueUSD }
        case .priceHighLow:
            return items.sorted { $0.stockValueUSD > $1.stockValueUSD }
        case .sizeLowHigh:
            return items.sorted {
                StockSizeDisplay.sortValue(from: $0.sizeText) < StockSizeDisplay.sortValue(from: $1.sizeText)
            }
        case .sizeHighLow:
            return items.sorted {
                StockSizeDisplay.sortValue(from: $0.sizeText) > StockSizeDisplay.sortValue(from: $1.sizeText)
            }
        case .brandAZ:
            return items.sorted {
                ($0.brand ?? "").localizedCaseInsensitiveCompare($1.brand ?? "") == .orderedAscending
            }
        }
    }

    static func sortCatalogProducts(_ products: [UpsoledProduct], by order: StockSortOrder) -> [UpsoledProduct] {
        switch order {
        case .newest:
            return products.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .priceLowHigh:
            return products.sorted { $0.stockValueUSD < $1.stockValueUSD }
        case .priceHighLow:
            return products.sorted { $0.stockValueUSD > $1.stockValueUSD }
        case .sizeLowHigh:
            return products.sorted {
                let a = productSizeSortValue($0)
                let b = productSizeSortValue($1)
                return a < b
            }
        case .sizeHighLow:
            return products.sorted {
                productSizeSortValue($0) > productSizeSortValue($1)
            }
        case .brandAZ:
            return products.sorted {
                ($0.brand ?? "").localizedCaseInsensitiveCompare($1.brand ?? "") == .orderedAscending
            }
        }
    }

    private static func productSizeSortValue(_ product: UpsoledProduct) -> Double {
        let cores = product.sizes.compactMap { StockSizeDisplay.normalizedStorage(from: $0) }
        guard let first = cores.first else { return 9999 }
        return StockSizeDisplay.sortValue(from: first)
    }

    static func availableBrands(closet: [ClosetItem], catalog: [UpsoledProduct]) -> [String] {
        var set = Set<String>()
        for item in closet {
            if let b = brandKey(item.brand) { set.insert(b) }
        }
        for p in catalog {
            if let b = brandKey(p.brand) { set.insert(b) }
        }
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func availableSizes(closet: [ClosetItem], catalog: [UpsoledProduct]) -> [String] {
        var set = Set<String>()
        for item in closet {
            if let s = StockSizeDisplay.normalizedStorage(from: item.sizeText) { set.insert(s) }
        }
        for p in catalog {
            for raw in p.sizes {
                if let s = StockSizeDisplay.normalizedStorage(from: raw) { set.insert(s) }
            }
        }
        return set.sorted {
            StockSizeDisplay.sortValue(from: $0) < StockSizeDisplay.sortValue(from: $1)
        }
    }

    static func availableCategoryOptions(closet: [ClosetItem], catalog: [UpsoledProduct]) -> [(key: String, emoji: String, title: String)] {
        var keys = Set<String>()
        for item in closet { keys.insert(closetCategoryKey(item)) }
        for p in catalog { keys.insert(catalogCategoryKey(p)) }

        let meta: (String) -> (String, String) = { key in
            if let cat = ClothingCategory(rawValue: key) {
                return (cat.emoji, cat.displayName)
            }
            switch key {
            case "clothing": return ("👔", "Clothing")
            case "shoes": return ("👞", "Shoes")
            case "accessories": return ("⌚", "Accessories")
            case "vintage": return ("🕰️", "Vintage")
            case "new-drops": return ("✨", "New drops")
            default: return ("📦", key.replacingOccurrences(of: "_", with: " ").capitalized)
            }
        }

        return keys.sorted().map { key in
            let m = meta(key)
            return (key, m.0, m.1)
        }
    }
}

// MARK: - Filter strip + sheet UI

struct StockBrowseFilterStrip: View {
    @Binding var filters: StockBrowseFilters
    var onOpenSheet: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StockQuickCategory.allCases) { quick in
                    let active = filters.quickCategory == quick
                    Button {
                        filters.quickCategory = quick
                    } label: {
                        HStack(spacing: 4) {
                            Text(quick.emoji)
                            Text(quick.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(active ? Color.white : Color.black.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule().fill(active ? Color.black : Color.black.opacity(0.06))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onOpenSheet) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filters")
                            .font(.system(size: 12, weight: .semibold))
                        if filters.isActive {
                            Circle()
                                .fill(Color(red: 0.20, green: 0.45, blue: 0.85))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }
}

struct StockBrowseFilterSortBar: View {
    @Binding var filters: StockBrowseFilters
    var onFilter: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onFilter) {
                HStack(spacing: 6) {
                    Text("Filter by")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                }
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(StockSortOrder.allCases) { order in
                    Button {
                        filters.sort = order
                    } label: {
                        if filters.sort == order {
                            Label(order.menuLabel, systemImage: "checkmark")
                        } else {
                            Text(order.menuLabel)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Sort by: \(filters.sort.menuLabel)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct StockBrowseFiltersSheet: View {
    @Binding var filters: StockBrowseFilters
    @Binding var layoutMode: StockLayoutMode
    let closetItems: [ClosetItem]
    let catalogProducts: [UpsoledProduct]
    @Environment(\.dismiss) private var dismiss

    @State private var categoryExpanded = true
    @State private var platformExpanded = true
    @State private var genderExpanded = false
    @State private var brandsExpanded = false
    @State private var shoeHeightExpanded = false
    @State private var activityExpanded = false

    private var brands: [String] {
        StockFilterEngine.availableBrands(closet: closetItems, catalog: catalogProducts)
    }

    private var resultCount: Int {
        let closet = closetItems.filter { StockFilterEngine.matches(filters, closetItem: $0) }.count
        let catalog = catalogProducts
            .filter { StockFilterEngine.matches(filters, catalogProduct: $0) }
            .reduce(0) { $0 + max(1, $1.quantity ?? 1) }
        return closet + catalog
    }

    private var resultsLabel: String {
        resultCount >= 1000 ? "1000+" : "\(resultCount)"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    layoutModeRow
                    filterDivider

                    toggleRow(title: "Available now", isOn: $filters.availableNow)
                    filterDivider
                    toggleRow(title: "Xpress shipping", icon: "🚀", isOn: $filters.expressShipping)
                    filterDivider
                    toggleRow(title: "Below retail price", isOn: $filters.belowRetail)
                    filterDivider

                    accordionSection(title: "Platform", isExpanded: $platformExpanded) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(StockMarketplacePlatformOption.allCases) { platform in
                                platformOptionRow(platform)
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    accordionSection(title: "Category", isExpanded: $categoryExpanded) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Sneakers")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.88))
                                .padding(.bottom, 10)

                            ForEach(StockSneakerStyleFilter.allCases) { style in
                                optionRow(
                                    title: style.label,
                                    isSelected: filters.sneakerStyles.contains(style.rawValue)
                                ) {
                                    toggleSet(style.rawValue, in: &filters.sneakerStyles)
                                    if !filters.sneakerStyles.isEmpty {
                                        filters.categoryKeys.insert(ClothingCategory.shoes.rawValue)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    accordionSection(title: "Gender", isExpanded: $genderExpanded) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(StockGenderFilter.allCases) { gender in
                                optionRow(
                                    title: gender.label,
                                    isSelected: filters.genders.contains(gender.rawValue)
                                ) {
                                    toggleSet(gender.rawValue, in: &filters.genders)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    accordionSection(title: "Brands", isExpanded: $brandsExpanded) {
                        VStack(alignment: .leading, spacing: 0) {
                            if brands.isEmpty {
                                Text("No brands available")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.45))
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(brands, id: \.self) { brand in
                                    optionRow(
                                        title: brand,
                                        isSelected: filters.brands.contains(brand)
                                    ) {
                                        toggleSet(brand, in: &filters.brands)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    accordionSection(title: "Shoe height", isExpanded: $shoeHeightExpanded) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(StockShoeHeightFilter.allCases) { height in
                                optionRow(
                                    title: height.label,
                                    isSelected: filters.shoeHeights.contains(height.rawValue)
                                ) {
                                    toggleSet(height.rawValue, in: &filters.shoeHeights)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    accordionSection(title: "Activity", isExpanded: $activityExpanded) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(StockActivityFilter.allCases) { activity in
                                optionRow(
                                    title: activity.label,
                                    isSelected: filters.activities.contains(activity.rawValue)
                                ) {
                                    toggleSet(activity.rawValue, in: &filters.activities)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            applyButton
        }
        .background(Color.white)
        .preferredColorScheme(.light)
    }

    private var headerBar: some View {
        ZStack {
            Text("Filter by")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.88))

            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var layoutModeRow: some View {
        HStack {
            Text("Results view")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.88))
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                ForEach(StockLayoutMode.allCases) { mode in
                    Button {
                        layoutMode = mode
                    } label: {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(layoutMode == mode ? Color.black : Color.black.opacity(0.28))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.accessibilityLabel)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private func toggleRow(title: String, icon: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Text(icon)
                    .font(.system(size: 14))
            }
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.88))
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.black)
        }
        .padding(.vertical, 16)
    }

    private func accordionSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .tracking(0.3)
                    Spacer(minLength: 12)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                .padding(.vertical, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }

            filterDivider
        }
    }

    private func platformOptionRow(_ platform: StockMarketplacePlatformOption) -> some View {
        Button {
            toggleSet(platform.rawValue, in: &filters.marketplacePlatforms)
        } label: {
            HStack(spacing: 12) {
                StylizedMarketplaceLogo(brand: platform.rawValue)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(platform.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))

                Spacer(minLength: 12)

                if filters.marketplacePlatforms.contains(platform.rawValue) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func optionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.82))
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filterDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(height: 1)
    }

    private var applyButton: some View {
        Button {
            dismiss()
        } label: {
            Text("See \(resultsLabel) results")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule(style: .continuous).fill(Color.black))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(Color.white)
    }

    private func toggleSet(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}

private enum StockMarketplacePlatformOption: String, CaseIterable, Identifiable {
    case stockX = "StockX"
    case goat = "GOAT"

    var id: String { rawValue }
}

private enum StockSneakerStyleFilter: String, CaseIterable, Identifiable {
    case lifestyle
    case performance
    case luxury

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lifestyle: return "Lifestyle"
        case .performance: return "Performance"
        case .luxury: return "Luxury"
        }
    }
}

private enum StockGenderFilter: String, CaseIterable, Identifiable {
    case men, women, kids, unisex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .men: return "Men"
        case .women: return "Women"
        case .kids: return "Kids"
        case .unisex: return "Unisex"
        }
    }
}

private enum StockShoeHeightFilter: String, CaseIterable, Identifiable {
    case low, mid, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low top"
        case .mid: return "Mid top"
        case .high: return "High top"
        }
    }
}

private enum StockActivityFilter: String, CaseIterable, Identifiable {
    case lifestyle, running, basketball, training, outdoor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lifestyle: return "Lifestyle"
        case .running: return "Running"
        case .basketball: return "Basketball"
        case .training: return "Training"
        case .outdoor: return "Outdoor"
        }
    }
}

// MARK: - Scan lookup payload

struct StockScanLookupPayload: Identifiable {
    let id = UUID()
    let scannedCode: String
    let productTitle: String
    let brand: String
    let sku: String
    let imageURL: String?
    let buyPriceUSD: Int?
    let sellPriceUSD: Int?
    let marketEstimate: PieceMarketPrice?
    let matchingStockItemID: UUID?
}

enum StockScanLookupService {
    @MainActor
    static func lookup(
        code rawCode: String,
        stock: [ClosetItem],
        goatVM: GoatAccountViewModel
    ) async -> StockScanLookupPayload {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = code.uppercased()
        let local = stock.first { item in
            let sku = (item.resolvedSKU ?? "").uppercased()
            if !sku.isEmpty, sku == normalized { return true }
            if let stored = item.skuText?.uppercased(), stored == normalized { return true }
            return item.name.uppercased().contains(normalized)
        }

        if goatVM.hasProviderToken {
            do {
                let pair = try await GoatAliasAPIService.searchAndPrice(keyword: code)
                let product = pair.product
                let prices = pair.prices
                return StockScanLookupPayload(
                    scannedCode: code,
                    productTitle: product.displayTitle,
                    brand: product.brand,
                    sku: product.sku.isEmpty ? normalized : product.sku,
                    imageURL: product.imageURL,
                    buyPriceUSD: prices.lowestUSD,
                    sellPriceUSD: prices.highestOfferUSD,
                    marketEstimate: prices.asPieceMarketPrice(),
                    matchingStockItemID: local?.id
                )
            } catch {
                // Fall through to OpenAI / local-only payload.
            }
        }

        do {
            let est = try await PieceMarketPrice.fetchStyleFromInternet(
                styleCode: SneakerSKU.extract(from: code) ?? normalized,
                brand: local?.brand,
                category: local?.category.displayName ?? "Shoes",
                sizeText: local?.sizeText,
                useWebSearch: true
            )
            return StockScanLookupPayload(
                scannedCode: code,
                productTitle: local?.catalogDisplayName ?? "Style \(normalized)",
                brand: local?.brand ?? "",
                sku: SneakerSKU.extract(from: code) ?? normalized,
                imageURL: nil,
                buyPriceUSD: est.avg,
                sellPriceUSD: est.max,
                marketEstimate: est,
                matchingStockItemID: local?.id
            )
        } catch {
            let style = SneakerSKU.extract(from: code) ?? normalized
            return StockScanLookupPayload(
                scannedCode: code,
                productTitle: local?.catalogDisplayName ?? "Style \(style)",
                brand: local?.brand ?? "",
                sku: style,
                imageURL: nil,
                buyPriceUSD: nil,
                sellPriceUSD: nil,
                marketEstimate: nil,
                matchingStockItemID: local?.id
            )
        }
    }
}

// MARK: - Barcode scanner (full screen)

struct StockBarcodeScannerScreen: View {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    @State private var torchOn = false
    @State private var didScan = false

    var body: some View {
        ZStack {
            StockBarcodeCameraView(isTorchOn: torchOn) { code in
                guard !didScan else { return }
                didScan = true
                onCode(code)
            }
            .ignoresSafeArea()

            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .mask {
                    Rectangle()
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: 280, height: 170)
                                .blendMode(.destinationOut)
                        }
                }
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        torchOn.toggle()
                    } label: {
                        Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer()

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: 280, height: 170)
                    .overlay(alignment: .topLeading) {
                        scanCorner(rotation: 0)
                    }
                    .overlay(alignment: .topTrailing) {
                        scanCorner(rotation: 90)
                    }
                    .overlay(alignment: .bottomLeading) {
                        scanCorner(rotation: 270)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        scanCorner(rotation: 180)
                    }

                Spacer()

                Text(L10n.tr("closet.scanHint"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func scanCorner(rotation: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 18))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 18, y: 0))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .frame(width: 18, height: 18)
        .rotationEffect(.degrees(rotation))
        .padding(6)
    }
}

private struct StockBarcodeCameraView: UIViewControllerRepresentable {
    var isTorchOn: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> StockBarcodeScannerViewController {
        let vc = StockBarcodeScannerViewController()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: StockBarcodeScannerViewController, context: Context) {
        uiViewController.setTorch(isTorchOn)
    }
}

final class StockBarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
        setTorch(false)
    }

    func setTorch(_ on: Bool) {
        guard let device = captureDevice, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCapture() }
                }
            }
        default:
            break
        }
    }

    private func setupCapture() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        captureDevice = device
        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.ean8, .ean13, .code128, .code39, .qr, .upce, .pdf417, .code93]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(value)
    }
}

// MARK: - Scan result sheet

struct StockScanResultSheet: View {
    let payload: StockScanLookupPayload
    var onViewStockItem: (UUID) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("closet.scanSuccess"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            HStack(alignment: .top, spacing: 14) {
                productThumb
                VStack(alignment: .leading, spacing: 6) {
                    Text(payload.productTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black)
                        .lineLimit(3)
                    if !payload.sku.isEmpty {
                        Text("SKU \(payload.sku)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            HStack(spacing: 10) {
                priceActionCard(
                    title: L10n.tr("closet.scanBuyLabel"),
                    value: payload.buyPriceUSD,
                    background: Color(red: 0.20, green: 0.70, blue: 0.45)
                )
                priceActionCard(
                    title: L10n.tr("closet.scanSellLabel"),
                    value: payload.sellPriceUSD,
                    background: Color.black
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            if let itemID = payload.matchingStockItemID {
                Button {
                    onViewStockItem(itemID)
                } label: {
                    Text(L10n.tr("closet.scanViewInStock"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }

            Spacer(minLength: 12)
        }
        .background(Color.white)
    }

    @ViewBuilder
    private var productThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 72, height: 72)
            if let urlStr = payload.imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: "shoeprints.fill")
                            .foregroundStyle(Color.black.opacity(0.25))
                    }
                }
                .frame(width: 64, height: 64)
            } else {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.black.opacity(0.25))
            }
        }
    }

    private func priceActionCard(title: String, value: Int?, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
            Text(value.map { PieceMarketPrice.formatUSD($0) } ?? "—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(background)
        }
    }
}
