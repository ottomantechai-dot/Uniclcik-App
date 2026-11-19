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

    static func localCacheKey(_ path: String, maxSide: CGFloat = 400) -> String {
        "stock:local:\(Int(maxSide.rounded())):\(path)"
    }
    static func urlCacheKey(_ url: URL) -> String { "stock:url:\(url.absoluteString)" }

    static func cachedLocalImage(relativePath: String, maxSide: CGFloat = 400) -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let key = localCacheKey(relativePath, maxSide: maxSide)
        if let mem = ImageCacheService.shared.image(forKey: key) { return mem }
        // Decodifica directamente a tamaño de miniatura desde disco (sin cargar el bitmap
        // completo en memoria). Evita guardar fotos a resolución completa en la caché y
        // elimina los tirones por evicción/re-decodificación durante el scroll.
        guard let ui = downsampledLocalImage(relativePath: relativePath, maxSide: maxSide)
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
    static func cachedLocalImageAsync(relativePath: String, maxSide: CGFloat = 400) async -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let key = localCacheKey(relativePath, maxSide: maxSide)
        if let mem = ImageCacheService.shared.image(forKey: key) { return mem }

        if let existing = await InflightCoordinator.shared.existing(for: key) {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            defer { Task { await InflightCoordinator.shared.remove(for: key) } }
            let image = await Task.detached(priority: .utility) {
                downsampledLocalImage(relativePath: relativePath, maxSide: maxSide)
                    ?? ImageStore.load(relativePath)
            }.value
            if let image { ImageCacheService.shared.store(image, forKey: key) }
            return image
        }
        await InflightCoordinator.shared.register(task, for: key)
        return await task.value
    }

    static func prefetchLocalImages(relativePaths: [String], maxSide: CGFloat = 168) async {
        await withTaskGroup(of: Void.self) { group in
            for path in relativePaths where !path.isEmpty {
                group.addTask {
                    _ = await cachedLocalImageAsync(relativePath: path, maxSide: maxSide)
                }
            }
        }
    }

    static func prefetchURLImages(urls: [URL], maxSide: CGFloat = 176) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = await cachedURLImage(for: url, maxSide: maxSide)
                }
            }
        }
    }

    static func memoryCachedURLImage(for url: URL) -> UIImage? {
        ImageCacheService.shared.image(forKey: urlCacheKey(url))
    }

    static func cachedURLImage(for url: URL, maxSide: CGFloat = 176) async -> UIImage? {
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
                let img = downsampleIfNeeded(raw, maxSide: maxSide)
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
    var maxPixelSide: CGFloat = 176
    var fillFrame: Bool = false

    @State private var image: UIImage?

    init(url: URL?, maxPixelSide: CGFloat = 176, fillFrame: Bool = false) {
        self.url = url
        self.maxPixelSide = maxPixelSide
        self.fillFrame = fillFrame
        if let url {
            _image = State(initialValue: StockImageLoader.memoryCachedURLImage(for: url))
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fillFrame ? .fill : .fit)
            } else if url != nil {
                ZStack {
                    Color.white
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.black.opacity(0.35))
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.black.opacity(0.22))
            }
        }
        .task(id: url?.absoluteString) {
            guard let url, image == nil else { return }
            if let loaded = await StockImageLoader.cachedURLImage(for: url, maxSide: maxPixelSide) {
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

private let stockPurchaseBlue = Color(red: 0.20, green: 0.45, blue: 0.85)

/// Columna de marketplace en la fila de lista (plataformas según categoría).
struct StockRowMarketplaceColumn: View {
    let platformName: String
    let price: Int?
    var trendDeltaUSD: Double? = nil

    private var displayBrand: String {
        switch platformName.uppercased() {
        case "STOCKX": return "StockX"
        case "GOAT": return "GOAT"
        case "EBAY": return "eBay"
        case "FLIGHT CLUB": return "Flight Club"
        case "TCG COLLECTOR": return "TCG Collector"
        case "GRAILED": return "Grailed"
        case "POSHMARK": return "Poshmark"
        default: return platformName
        }
    }

    private var logoHeight: CGFloat {
        switch displayBrand.uppercased() {
        case "FLIGHT CLUB", "TCG COLLECTOR", "POSHMARK":
            return 12
        default:
            return 20
        }
    }

    private var logoMaxWidth: CGFloat? {
        switch displayBrand.uppercased() {
        case "FLIGHT CLUB":
            return 54
        case "TCG COLLECTOR":
            return 58
        case "POSHMARK":
            return 52
        default:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            StylizedMarketplaceLogo(brand: displayBrand)
                .frame(maxWidth: logoMaxWidth ?? .infinity)
                .frame(height: logoHeight)

            if let price, price > 0 {
                Text(PieceMarketPrice.formatUSD(price))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                platformTrendLabel
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.22))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var platformTrendLabel: some View {
        let delta = trendDeltaUSD ?? 0
        let trendUp = delta >= 0
        let tint = trendDeltaUSD == nil
            ? Color.black.opacity(0.35)
            : (trendUp
                ? Color(red: 0.20, green: 0.70, blue: 0.45)
                : Color(red: 0.92, green: 0.30, blue: 0.30))
        let amount = Int(abs(delta).rounded())

        HStack(spacing: 1) {
            Image(systemName: trendUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 7, weight: .heavy))
            if delta > 0 {
                Text("+\(PieceMarketPrice.formatUSD(amount))")
            } else if delta < 0 {
                Text("−\(PieceMarketPrice.formatUSD(amount))")
            } else {
                Text("+\(PieceMarketPrice.formatUSD(0))")
            }
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
}

/// Pie de la lista de stock con estado de precios en vivo.
struct StockMarketplaceListLiveFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.30))
                Text("Prices updated in real time")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 0.13, green: 0.55, blue: 0.30))
                    .frame(width: 5, height: 5)
                Text("Last update: now")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    static func platform(from name: String, in estimate: PieceMarketPrice?) -> PlatformPrice? {
        estimate?.platforms.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func platformDeltaUSD(for name: String, marketPrice: PieceMarketPrice?) -> Double? {
        if let platform = platform(from: name, in: marketPrice),
           platform.history.count >= 2,
           let first = platform.history.first,
           let last = platform.history.last {
            return last - first
        }
        if let estimate = marketPrice,
           estimate.history.count >= 2,
           let first = estimate.history.first,
           let last = estimate.history.last {
            return last - first
        }
        return nil
    }

    static func platformPriceUSD(
        for name: String,
        marketPrice: PieceMarketPrice?,
        stockValueUSD: Double,
        askingUSD: Double
    ) -> Int? {
        if let match = marketPrice?.platforms.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.avg > 0
        }) {
            return match.avg
        }

        // Solo precios confirmados: si esa plataforma no ha dado precio, no se inventa uno.
        return nil
    }

    static func synthesizedPlatformPrice(platform name: String, base: Int) -> Int {
        StockCategoryMarketplaceCatalog.synthesizedPlatformPrice(platform: name, base: base)
    }
}

struct StockMarketplaceListRow<ImageContent: View>: View {
    let brandLine: String
    let nameLine: String
    var sizeLabel: String? = nil
    var fallbackPrice: String? = nil
    var marketPrice: PieceMarketPrice? = nil
    var marketplaceSegment: StockMarketplaceSegment = .shoes
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

    private func platformPriceUSD(for name: String) -> Int? {
        StockMarketRowMetrics.platformPriceUSD(
            for: name,
            marketPrice: marketPrice,
            stockValueUSD: stockValueUSD,
            askingUSD: askingUSD
        )
    }

    private var displayPriceUSD: Int {
        let platformPrices = marketplaceSegment.platforms.compactMap { platformPriceUSD(for: $0) }
        if let lowest = platformPrices.min(), lowest > 0 { return lowest }
        if let platformAvg = platform?.avg, platformAvg > 0 { return platformAvg }
        if let marketAvg = marketPrice?.avg, marketAvg > 0 { return marketAvg }
        if stockValueUSD > 0 { return Int(stockValueUSD.rounded()) }
        if askingUSD > 0 { return Int(askingUSD.rounded()) }
        return 0
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    thumbnailBlock

                    productInfoBlock
                        .frame(maxWidth: .infinity, alignment: .leading)

                    rightSummaryBlock
                }

                marketplaceColumnsBlock
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
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

    private func platformTrendDeltaUSD(for name: String) -> Double? {
        StockMarketRowMetrics.platformDeltaUSD(for: name, marketPrice: marketPrice)
    }

    private var marketplaceColumnsBlock: some View {
        Group {
            if marketplaceSegment.platforms.count > 4 {
                ScrollView(.horizontal, showsIndicators: false) {
                    marketplaceColumnsRow(compact: true)
                }
            } else {
                marketplaceColumnsRow(compact: false)
            }
        }
    }

    /// Las plataformas en una sola cápsula de cristal: el logo de cada una y, debajo, cuánto por
    /// encima o por debajo de tu precio está allí (en %). Sin precio confirmado, una raya.
    private func marketplaceColumnsRow(compact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(marketplaceSegment.platforms.enumerated()), id: \.element) { index, platform in
                VStack(spacing: 3) {
                    StylizedMarketplaceLogo(brand: platform)
                        .frame(height: 15)
                        .frame(maxWidth: 58)
                    let percent = platformPercent(for: platform)
                    Text(percent.map { String(format: "%+.0f%%", $0) } ?? "—")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(percent == nil ? Color.black.opacity(0.3) : (percent! >= 0 ? Color(red: 0.13, green: 0.55, blue: 0.30) : Color.red))
                }
                .frame(maxWidth: .infinity)
                if index < marketplaceSegment.platforms.count - 1 {
                    Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1, height: 24)
                }
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .glassEffect(.regular, in: .capsule)
    }

    /// Diferencia entre el precio confirmado de la plataforma y tu precio (o el valor del stock).
    private func platformPercent(for name: String) -> Double? {
        guard let price = platformPriceUSD(for: name) else { return nil }
        let base = askingUSD > 0 ? askingUSD : stockValueUSD
        guard base > 0 else { return nil }
        return (Double(price) - base) / base * 100
    }

    private var thumbnailBlock: some View {
        ZStack(alignment: .topTrailing) {
            image()
                .padding(4)
                .frame(width: 84, height: 84)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
        VStack(alignment: .leading, spacing: 4) {
            BrandLogoLabel(brand: brandLine)

            Text(nameLine)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.9)

            if let sizeLabel {
                Text("Size \(sizeLabel)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var rightSummaryBlock: some View {
        VStack(alignment: .trailing, spacing: 8) {
            estimatedValueContent

            if purchaseUSD > 0 {
                purchasePriceCard
            }
        }
        .frame(minWidth: 108, alignment: .trailing)
    }

    @ViewBuilder
    private var estimatedValueContent: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if displayPriceUSD > 0 || stockValueUSD > 0 || askingUSD > 0 {
                Text(PieceMarketPrice.formatUSD(displayPriceUSD))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Estimated value")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.40))
                    .fixedSize(horizontal: true, vertical: false)

                if sparkPoints.count >= 2 {
                    deltaLabel
                } else {
                    deltaLabelStable
                }
            } else if let fallbackPrice {
                Text(fallbackPrice)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Your price")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.40))
            } else {
                Text("—")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
        }
    }

    private var purchasePriceCard: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("My cost")
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)

            Text(PieceMarketPrice.formatUSD(Int(purchaseUSD.rounded())))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(stockPurchaseBlue)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(stockPurchaseBlue.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(stockPurchaseBlue.opacity(0.18), lineWidth: 1)
                }
        }
    }

    private var deltaLabelStable: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .heavy))
            Text("+\(PieceMarketPrice.formatUSD(0))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Text("(24h)")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var deltaLabel: some View {
        let tint = trendUp
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)
        let amount = Int(abs(deltaUSD).rounded())

        return HStack(spacing: 2) {
            Image(systemName: trendUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 10, weight: .heavy))
            Text("\(trendUp ? "+" : "−")\(PieceMarketPrice.formatUSD(amount))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Text("(24h)")
                .font(.system(size: 9, weight: .medium))
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
    var onScanBarcode: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.35))

            TextField(
                "",
                text: $searchText,
                prompt: Text("Search by brand, color, SKU…")
                    .foregroundStyle(Color.black.opacity(0.38))
            )
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(size: 15, weight: .regular))
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

            if let onScanBarcode {
                Button {
                    searchFocused = false
                    onScanBarcode()
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("closet.scanBarcode"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    var toolbarSortLabel: String { menuLabel }
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
                stockToolbarButtonLabel(
                    icon: "line.3.horizontal.decrease",
                    title: "Filter"
                )
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(StockSortOrder.allCases) { order in
                    Button {
                        filters.sort = order
                    } label: {
                        if filters.sort == order {
                            Label(order.toolbarSortLabel, systemImage: "checkmark")
                        } else {
                            Text(order.toolbarSortLabel)
                        }
                    }
                }
            } label: {
                stockToolbarButtonLabel(
                    icon: "arrow.up.arrow.down",
                    title: "Sort: \(filters.sort.toolbarSortLabel)"
                )
            }
        }
    }

    private func stockToolbarButtonLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(Color.black.opacity(0.82))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }
        }
    }
}

struct StockBrowseFiltersSheet: View {
    @Binding var filters: StockBrowseFilters
    @Binding var layoutMode: StockLayoutMode
    let closetItems: [ClosetItem]
    let catalogProducts: [UpsoledProduct]
    var onScan: () -> Void = {}
    var onReports: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private let gray = Color(red: 0.965, green: 0.965, blue: 0.975)

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

    var body: some View {
        ScrollView(showsIndicators: false) {
            GlassEffectContainer(spacing: 10) {
                VStack(alignment: .leading, spacing: 14) {
                    // Vista: cuadrícula o lista.
                    section("View", icon: "rectangle.grid.2x2") {
                        HStack(spacing: 10) {
                            ForEach(StockLayoutMode.allCases) { mode in
                                chip(mode == .grid ? "Grid" : "List", icon: mode.iconName, on: layoutMode == mode, wide: true) { layoutMode = mode }
                            }
                        }
                    }

                    section("Sort", icon: "arrow.up.arrow.down") {
                        flow(StockSortOrder.allCases.map(\.rawValue)) { raw in
                            let order = StockSortOrder(rawValue: raw) ?? .newest
                            chip(order.menuLabel, on: filters.sort == order) { filters.sort = order }
                        }
                    }

                    section("Platforms", icon: "storefront") {
                        HStack(spacing: 10) {
                            ForEach(StockMarketplacePlatformOption.allCases) { platform in
                                let on = filters.marketplacePlatforms.contains(platform.rawValue)
                                Button { toggleSet(platform.rawValue, in: &filters.marketplacePlatforms) } label: {
                                    VStack(spacing: 8) {
                                        StylizedMarketplaceLogo(brand: platform.rawValue).frame(width: 40, height: 16)
                                            .frame(width: 58, height: 58)
                                            .background(.white, in: .circle)
                                            .glassEffect(.regular.interactive(), in: .circle)
                                            .overlay { Circle().strokeBorder(on ? Color.black : .clear, lineWidth: 2) }
                                        Text(platform.rawValue).font(.system(size: 12, weight: on ? .bold : .medium)).foregroundStyle(.black)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    section("Brands", icon: "tag") {
                        if brands.isEmpty {
                            Text("No brands available").font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.45))
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(brands, id: \.self) { brand in
                                        let on = filters.brands.contains(brand)
                                        Button { toggleSet(brand, in: &filters.brands) } label: {
                                            BrandLogoLabel(brand: brand, wide: true)
                                                .frame(width: 60, height: 26)
                                                .frame(width: 84, height: 52)
                                                .background(.white, in: .rect(cornerRadius: 16))
                                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                                                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(on ? Color.black : .clear, lineWidth: 2) }
                                        }
                                        .buttonStyle(.plain).accessibilityLabel(brand)
                                    }
                                }
                                .padding(.vertical, 2).padding(.horizontal, 16)
                            }
                            // Las marcas llegan hasta los bordes del contenedor y se desvanecen ahí, sin corte.
                            .mask {
                                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                                       .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                               startPoint: .leading, endPoint: .trailing)
                            }
                            .padding(.horizontal, -16)
                        }
                    }

                    section("Availability", icon: "bolt") {
                        toggle("Available now", icon: "checkmark.circle", isOn: $filters.availableNow)
                        Divider()
                        toggle("Xpress shipping", icon: "shippingbox", isOn: $filters.expressShipping)
                        Divider()
                        toggle("Below retail price", icon: "arrow.down.right.circle", isOn: $filters.belowRetail)
                    }

                    section("Category", icon: "square.grid.2x2") {
                        flow(StockSneakerStyleFilter.allCases.map(\.rawValue)) { raw in
                            let style = StockSneakerStyleFilter(rawValue: raw)
                            chip(style?.label ?? raw, on: filters.sneakerStyles.contains(raw)) {
                                toggleSet(raw, in: &filters.sneakerStyles)
                                if !filters.sneakerStyles.isEmpty { filters.categoryKeys.insert(ClothingCategory.shoes.rawValue) }
                            }
                        }
                    }

                    section("Gender", icon: "person.2") {
                        flow(StockGenderFilter.allCases.map(\.rawValue)) { raw in
                            chip(StockGenderFilter(rawValue: raw)?.label ?? raw, on: filters.genders.contains(raw)) { toggleSet(raw, in: &filters.genders) }
                        }
                    }

                    section("Shoe height", icon: "ruler") {
                        flow(StockShoeHeightFilter.allCases.map(\.rawValue)) { raw in
                            chip(StockShoeHeightFilter(rawValue: raw)?.label ?? raw, on: filters.shoeHeights.contains(raw)) { toggleSet(raw, in: &filters.shoeHeights) }
                        }
                    }

                    section("Activity", icon: "figure.run") {
                        flow(StockActivityFilter.allCases.map(\.rawValue)) { raw in
                            chip(StockActivityFilter(rawValue: raw)?.label ?? raw, on: filters.activities.contains(raw)) { toggleSet(raw, in: &filters.activities) }
                        }
                    }

                    section("Tools", icon: "wand.and.stars") {
                        HStack(spacing: 10) {
                            chip("Scan a box", icon: "barcode.viewfinder", on: false, wide: true) { dismiss(); onScan() }
                            chip("Sale reports", icon: "doc.text.magnifyingglass", on: false, wide: true) { dismiss(); onReports() }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 110)
            }
        }
        .background(gray.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: { TopBarGlassButton(systemImage: "xmark") }.buttonStyle(.plain)
                Spacer()
                Text("Filters").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                Spacer()
                Button { filters.reset() } label: { TopBarGlassButton(systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.plain).accessibilityLabel("Reset filters")
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
            .background { LinearGradient(colors: [gray, gray.opacity(0)], startPoint: .center, endPoint: .bottom).ignoresSafeArea(edges: .top) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { dismiss() } label: {
                Text("See \(resultCount >= 1000 ? "1000+" : "\(resultCount)") results")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56).background(.black, in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
            .background { LinearGradient(colors: [gray.opacity(0), gray], startPoint: .top, endPoint: .center).ignoresSafeArea(edges: .bottom) }
        }
        .preferredColorScheme(.light)
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 32, height: 32).glassEffect(.regular, in: .circle)
                Text(title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 24))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func chip(_ title: String, icon: String? = nil, on: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(on ? .white : .black)
            .padding(.horizontal, 14).frame(maxWidth: wide ? .infinity : nil, minHeight: 40)
            .background(on ? Color.black : Color.black.opacity(0.05), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// Fichas que van saltando de línea según quepan.
    private func flow<Content: View>(_ items: [String], @ViewBuilder _ content: @escaping (String) -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { content($0).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }

    private func toggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(.black)
        }
        .tint(.black)
    }

    private func toggleSet(_ value: String, in set: inout Set<String>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
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
        stock: [ClosetItem]
    ) async -> StockScanLookupPayload {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = code.uppercased()
        let local = stock.first { item in
            let sku = (item.resolvedSKU ?? "").uppercased()
            if !sku.isEmpty, sku == normalized { return true }
            if let stored = item.skuText?.uppercased(), stored == normalized { return true }
            return item.name.uppercased().contains(normalized)
        }

        let style = SneakerSKU.extract(from: code) ?? normalized
        if let estimate = try? await KicksDBClient.fetchAggregated(
            query: style,
            fallbackQuery: local?.catalogDisplayName,
            sizeQuery: local?.sizeText
        ) {
            return StockScanLookupPayload(
                scannedCode: code,
                productTitle: estimate.matchedTitle ?? local?.catalogDisplayName ?? "Style \(style)",
                brand: local?.brand ?? "",
                sku: estimate.matchedSKU ?? style,
                imageURL: nil,
                buyPriceUSD: estimate.min,
                sellPriceUSD: estimate.max,
                marketEstimate: estimate,
                matchingStockItemID: local?.id
            )
        }

        do {
            let est = try await PieceMarketPrice.fetchStyleFromInternet(
                styleCode: style,
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

    @Environment(\.dismiss) private var dismiss
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
            .allowsHitTesting(false)

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
                    Button(action: closeScanner) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer()

                    Button {
                        torchOn.toggle()
                    } label: {
                        Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(torchOn ? "Turn flash off" : "Turn flash on")
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer()

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: 280, height: 170)
                    .allowsHitTesting(false)
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
                    .allowsHitTesting(false)
            }
            .zIndex(1)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func closeScanner() {
        guard !didScan else { return }
        torchOn = false
        onCancel()
        dismiss()
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
    @State private var saleReport: SaleReport?

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

            Button {
                saleReport = SaleReport.from(payload: payload)
            } label: {
                Label("View sale report", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .fullScreenCover(item: $saleReport) { SaleReportView(report: $0) }

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


/// La marca del zapato con su logo (Nike, adidas, Jordan, New Balance, Puma, Dior); las demás, con su nombre.
struct BrandLogoLabel: View {
    let brand: String
    /// En pequeño, para ir dentro de un círculo: el logo o la inicial de la marca.
    var compact = false
    /// Para las fichas de la tira de marcas: logo más grande, o el nombre si no hay logo.
    var wide = false

    private var asset: String? { Self.assetName(for: brand) }

    /// Nombre del logo de una marca en Assets, o nil si no hay.
    static func assetName(for brand: String) -> String? {
        let key = brand.lowercased().replacingOccurrences(of: " ", with: "")
        if key == "on" || key == "onrunning" { return "BrandLogo-on" }   // «On» va aparte: su nombre está dentro de otros
        for name in ["nike", "adidas", "jordan", "newbalance", "puma", "dior", "vans", "crocs", "asics", "ugg", "salomon", "timberland"] where key.contains(name) { return "BrandLogo-" + name }
        return nil
    }

    var body: some View {
        if wide {
            if let asset {
                Image(asset).resizable().scaledToFit().frame(width: 56, height: 24).foregroundStyle(.black)
                    .accessibilityLabel(brand)
            } else {
                Text(brand).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.black).lineLimit(1).minimumScaleFactor(0.7)
            }
        } else if compact {
            if let asset {
                Image(asset).resizable().scaledToFit().frame(width: 18, height: 14).foregroundStyle(.black)
                    .accessibilityLabel(brand)
            } else {
                Text(String(brand.prefix(1)).uppercased()).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            }
        } else if let asset {
            Image(asset).resizable().scaledToFit()
                .frame(width: 34, height: 18, alignment: .leading)
                .foregroundStyle(.black)
                .accessibilityLabel(brand)
        } else {
            Text(brand)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.5))
                .lineLimit(1)
        }
    }
}
