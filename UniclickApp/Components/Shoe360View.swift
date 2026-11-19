import SwiftUI
import UIKit

// MARK: - Zapato en 360°
// StockX publica 36 fotos de cada zapato girando, en su servidor público de imágenes. La dirección
// sale del nombre del producto. Si ese producto no tiene giro, se enseña la foto normal.

@MainActor
final class Shoe360Loader: ObservableObject {
    nonisolated static let frameCount = 36
    @Published var frames: [UIImage?] = Array(repeating: nil, count: frameCount)
    @Published var available = false
    private var loadedTitle = ""

    private nonisolated(unsafe) static let cache = NSCache<NSString, UIImage>()

    /// «adidas Yeezy Boost 350 V2 Steel Grey» → «adidas-Yeezy-Boost-350-V2-Steel-Grey».
    nonisolated static func slug(_ title: String) -> String {
        let cleaned = title.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." ? Character(scalar) : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: "-")
    }

    nonisolated static func url(slug: String, frame: Int) -> URL? {
        URL(string: String(format: "https://images.stockx.com/360/%@/Images/%@/Lv2/img%02d.jpg?w=560&q=55&fm=jpg", slug, slug, frame + 1))
    }

    /// Prueba cada nombre (el de StockX primero) hasta dar con uno que tenga giro.
    func load(titles: [String], imageURLs: [URL] = [], queries: [String] = []) async {
        let key = (titles + imageURLs.map(\.absoluteString) + queries).joined(separator: "|")
        guard key != loadedTitle else { return }
        loadedTitle = key
        frames = Array(repeating: nil, count: Self.frameCount)
        available = false
        guard let slug = await Self.resolveSlug(titles: titles, imageURLs: imageURLs, queries: queries), loadedTitle == key else { return }
        // La primera foto sale al instante (del disco si ya se vio antes); el resto llega en paralelo.
        if let first = await Self.image(slug: slug, frame: 0) {
            frames[0] = first
            available = true
        }
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for frame in 1..<Self.frameCount {
                group.addTask { (frame, await Self.image(slug: slug, frame: frame)) }
            }
            for await (frame, image) in group where loadedTitle == key {
                frames[frame] = image
            }
        }
    }

    /// Descarga el giro por adelantado (lista del stock, tendencias) para que al abrir el zapato ya esté.
    nonisolated static func prefetch(titles: [String], imageURLs: [URL] = [], queries: [String] = []) async {
        guard let slug = await resolveSlug(titles: titles, imageURLs: imageURLs, queries: queries) else { return }
        await withTaskGroup(of: Void.self) { group in
            for frame in 0..<frameCount {
                group.addTask { _ = await image(slug: slug, frame: frame) }
            }
        }
    }

    // MARK: Qué nombre tiene giro (se recuerda entre aperturas)

    /// El nombre exacto del giro va dentro de las direcciones de las fotos de StockX:
    /// «…/images/Air-Jordan-4-Retro-Oxidized-Green-Product.jpg» o «…/360/<nombre>/Images/…».
    nonisolated static func slugs(fromImageURL url: URL) -> [String] {
        guard url.host?.contains("stockx") == true else { return [] }
        let parts = url.pathComponents
        if let at = parts.firstIndex(of: "360"), at + 1 < parts.count { return [parts[at + 1]] }
        var name = url.deletingPathExtension().lastPathComponent
        for suffix in ["-Product", "_V2", "-V2", "-1", "-2"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
        if name.hasSuffix("-Product") { name.removeLast("-Product".count) }
        return name.isEmpty ? [] : [name]
    }

    private nonisolated static func resolveSlug(titles: [String], imageURLs: [URL], queries: [String]) async -> String? {
        var slugs: [String] = imageURLs.flatMap { slugs(fromImageURL: $0) }
        for title in titles {
            for option in [slug(title), slug(title.replacingOccurrences(of: "Adidas", with: "adidas"))] where !option.isEmpty && !slugs.contains(option) {
                slugs.append(option)
            }
        }
        let defaults = UserDefaults.standard
        var known = (defaults.dictionary(forKey: "shoe360.slugs") as? [String: String]) ?? [:]
        let keys = slugs + queries.map { "q:" + $0 }
        func remember(_ hit: String) {
            for name in keys { known[name] = hit }
            defaults.set(known, forKey: "shoe360.slugs")
        }
        for key in keys { if let hit = known[key], !hit.isEmpty { return hit } }
        for option in slugs.prefix(6) {
            if await image(slug: option, frame: 0) != nil { remember(option); return option }
        }
        // Con el nombre del stock no salió: se pregunta a StockX (por el SKU o el nombre) cuál es su ficha,
        // y de su foto se saca el nombre exacto del giro.
        for query in queries.prefix(2) where !query.isEmpty {
            guard let hit = try? await KicksDBClient.search(platform: .stockx, query: query) else { continue }
            var options: [String] = []
            if let image = hit.image.flatMap(URL.init(string:)) { options += self.slugs(fromImageURL: image) }
            if let title = hit.title ?? hit.name { options.append(slug(title)) }
            for option in options where !option.isEmpty {
                if await image(slug: option, frame: 0) != nil { remember(option); return option }
            }
        }
        return nil
    }

    // MARK: Fotos (memoria → disco → red)

    private nonisolated static let folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("shoe360", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private nonisolated static func image(slug: String, frame: Int) async -> UIImage? {
        let name = "\(slug)-\(frame).jpg" as NSString
        if let hit = cache.object(forKey: name) { return hit }
        let file = folder.appendingPathComponent(name as String)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            cache.setObject(image, forKey: name)
            return image
        }
        guard let url = url(slug: slug, frame: frame) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: name)
        try? data.write(to: file, options: .atomic)
        return image
    }
}

/// Foto del zapato que gira al arrastrar. Sin giro disponible, enseña `fallbackURL`.
struct Shoe360View: View {
    /// Nombres del zapato a probar, del más fiable (el de StockX) al menos.
    let titles: [String]
    var fallbackURL: URL?
    /// Lo que se enseña si no hay giro (por ejemplo, la foto propia del stock).
    var fallback: AnyView?

    /// Búsquedas (SKU o nombre) para preguntar a StockX su ficha si con el nombre no aparece el giro.
    var queries: [String] = []
    /// Marca del zapato: su logo sale arriba a la derecha, junto al aviso de que se puede girar.
    var brand: String?
    /// Cuánto suben el aviso y la marca: en la ficha quedan a la altura del botón de volver.
    var badgeLift: CGFloat = 0

    init(title: String, fallbackURL: URL? = nil, queries: [String] = [], brand: String? = nil, badgeLift: CGFloat = 0) {
        self.badgeLift = badgeLift
        self.titles = [title]
        self.fallbackURL = fallbackURL
        self.queries = queries
        self.brand = brand
    }

    init(titles: [String], brand: String? = nil, fallbackURL: URL? = nil, fallback: AnyView? = nil, queries: [String] = [], badgeLift: CGFloat = 0) {
        self.badgeLift = badgeLift
        self.titles = titles.filter { !$0.isEmpty }
        self.brand = brand
        self.fallbackURL = fallbackURL
        self.fallback = fallback
        self.queries = queries
    }

    @StateObject private var loader = Shoe360Loader()
    @State private var index = 0
    @State private var dragStart = 0

    private var ready: Int { loader.frames.compactMap { $0 }.count }

    var body: some View {
        ZStack(alignment: .bottom) {
            if loader.available, let image = loader.frames[index] ?? loader.frames[0] {
                Image(uiImage: image).resizable().scaledToFit()
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                let step = Int(value.translation.width / 7)
                                let count = Shoe360Loader.frameCount
                                index = ((dragStart - step) % count + count) % count
                            }
                            .onEnded { _ in dragStart = index }
                    )
            } else if let fallback {
                fallback
            } else {
                AsyncImage(url: fallbackURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else {
                        Image(systemName: "shoe.2").font(.system(size: 40)).foregroundStyle(.black.opacity(0.2))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            // Aviso de que el zapato gira (solo informa) y, a su lado, la marca.
            HStack(spacing: 8) {
                if loader.available {
                    HStack(spacing: 5) {
                        Image(systemName: "rotate.3d")
                        Text("360°")
                    }
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.7))
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(.white, in: .capsule)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityLabel("Drag to spin 360 degrees")
                }
                if let brand, !brand.isEmpty {
                    BrandLogoLabel(brand: brand, compact: true)
                        .frame(width: 34, height: 34)
                        .background(.white, in: .circle)
                        .glassEffect(.regular, in: .circle)
                }
            }
            .padding(.trailing, 0).padding(.top, 4)
            .offset(y: -badgeLift)
            .allowsHitTesting(false)
        }
        .task(id: titles + queries + [fallbackURL?.absoluteString ?? ""]) {
            await loader.load(titles: titles, imageURLs: [fallbackURL].compactMap { $0 }, queries: queries)
        }
    }
}
