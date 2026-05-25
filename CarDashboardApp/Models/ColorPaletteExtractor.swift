import UIKit

/// Extracción de color dominante local (sin red, sin IA). Ignora fondos casi blancos.
enum ColorPaletteExtractor {

    /// Devuelve hasta `count` colores `#RRGGBB` ordenados por frecuencia aproximada.
    static func extract(from image: UIImage, count: Int = 5) -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        let size = CGSize(width: 100, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let small = scaled.cgImage else { return [] }

        let width = small.width
        let height = small.height
        let bytesPerPixel = 4
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        guard let ctx = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        ctx.draw(small, in: CGRect(x: 0, y: 0, width: width, height: height))

        let bucketSize: UInt8 = 32
        var buckets: [String: Int] = [:]
        var bucketColors: [String: (r: Int, g: Int, b: Int, count: Int)] = [:]

        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            let r = rawData[i]
            let g = rawData[i + 1]
            let b = rawData[i + 2]
            let a = rawData[i + 3]
            if a < 128 { continue }
            if r > 240, g > 240, b > 240 { continue }

            let br = (r / bucketSize) * bucketSize
            let bg = (g / bucketSize) * bucketSize
            let bb = (b / bucketSize) * bucketSize
            let key = "\(br)-\(bg)-\(bb)"
            buckets[key, default: 0] += 1
            var entry = bucketColors[key] ?? (0, 0, 0, 0)
            entry.0 += Int(r)
            entry.1 += Int(g)
            entry.2 += Int(b)
            entry.3 += 1
            bucketColors[key] = entry
        }

        let top = buckets.sorted { $0.value > $1.value }.prefix(count)
        return top.compactMap { key, _ in
            guard let avg = bucketColors[key], avg.3 > 0 else { return nil }
            let r = avg.0 / avg.3
            let g = avg.1 / avg.3
            let bl = avg.2 / avg.3
            return String(format: "#%02X%02X%02X", r, g, bl)
        }
    }
}
