import SwiftUI
import UIKit

// MARK: - Zapato en 360°
// StockX publica 36 fotos de cada zapato girando, en su servidor público de imágenes. La dirección
// sale del nombre del producto. Si ese producto no tiene giro, se enseña la foto normal.

@MainActor
final class Shoe360Loader: ObservableObject {
    static let frameCount = 36
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
        URL(string: String(format: "https://images.stockx.com/360/%@/Images/%@/Lv2/img%02d.jpg?w=700&q=60&fm=jpg", slug, slug, frame + 1))
    }

    /// Prueba cada nombre (el de StockX primero) hasta dar con uno que tenga giro.
    func load(titles: [String]) async {
        let key = titles.joined(separator: "|")
        guard key != loadedTitle else { return }
        loadedTitle = key
        frames = Array(repeating: nil, count: Self.frameCount)
        available = false
        var slugs: [String] = []
        for title in titles {
            for option in [Self.slug(title), Self.slug(title.replacingOccurrences(of: "Adidas", with: "adidas"))] where !option.isEmpty && !slugs.contains(option) {
                slugs.append(option)
            }
        }
        var found: (slug: String, image: UIImage)?
        for slug in slugs.prefix(6) {
            if let first = await Self.image(slug: slug, frame: 0) { found = (slug, first); break }
        }
        guard let found, loadedTitle == key else { return }
        frames[0] = found.image
        available = true
        let slug = found.slug
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for frame in 1..<Self.frameCount {
                group.addTask { (frame, await Self.image(slug: slug, frame: frame)) }
            }
            for await (frame, image) in group where loadedTitle == key {
                frames[frame] = image
            }
        }
    }

    private nonisolated static func image(slug: String, frame: Int) async -> UIImage? {
        guard let url = url(slug: slug, frame: frame) else { return nil }
        if let hit = cache.object(forKey: url.absoluteString as NSString) { return hit }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url.absoluteString as NSString)
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

    init(title: String, fallbackURL: URL? = nil) {
        self.titles = [title]
        self.fallbackURL = fallbackURL
    }

    init(titles: [String], fallbackURL: URL? = nil, fallback: AnyView? = nil) {
        self.titles = titles.filter { !$0.isEmpty }
        self.fallbackURL = fallbackURL
        self.fallback = fallback
    }

    @StateObject private var loader = Shoe360Loader()
    @State private var index = 0
    @State private var dragStart = 0
    @State private var didIntro = false

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
                HStack(spacing: 6) {
                    Image(systemName: "rotate.3d")
                    Text(ready < Shoe360Loader.frameCount ? "Cargando giro…" : "Arrastra para girar · 360°")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black.opacity(0.65))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 8)
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
        .task(id: titles) { await loader.load(titles: titles) }
        .onChange(of: ready) { _, count in
            // Cuando están todas las fotos, da una vuelta sola para enseñar que gira.
            guard count == Shoe360Loader.frameCount, !didIntro else { return }
            didIntro = true
            Task {
                for step in 1...Shoe360Loader.frameCount {
                    try? await Task.sleep(for: .milliseconds(45))
                    index = step % Shoe360Loader.frameCount
                }
                dragStart = index
            }
        }
    }
}
