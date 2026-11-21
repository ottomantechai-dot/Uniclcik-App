import Foundation

enum ShoeGTIN {
    static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func normalize(_ input: String) -> String? {
        let digits = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [8, 12, 13, 14].contains(digits.count), isNumeric(digits),
              digits.contains(where: { $0 != "0" }) else { return nil }
        let checksum = digits.utf8.reversed().enumerated().reduce(0) { sum, entry in
            sum + Int(entry.element - 48) * (entry.offset.isMultiple(of: 2) ? 1 : 3)
        }
        guard checksum.isMultiple(of: 10) else { return nil }
        return String(repeating: "0", count: 14 - digits.count) + digits
    }
}

enum ShoeSizeSystem: String, Decodable, Hashable, Sendable {
    case usMen = "us_m"
    case usWomen = "us_w"
    case usYouth = "us_y"

    var label: String {
        switch self {
        case .usMen: "US M"
        case .usWomen: "US W"
        case .usYouth: "US Y"
        }
    }
}

struct ShoeCatalogModel: Decodable {
    let slug: String
    let title: String
    let brand: String?
    let styleCode: String?
    let imageURL: String?
    let sizeSystem: ShoeSizeSystem?

    enum CodingKeys: String, CodingKey {
        case slug, title, brand
        case styleCode = "style_code"
        case imageURL = "image_url"
        case sizeSystem = "size_system"
    }
}

struct ShoeCatalogVariant: Decodable {
    let usSize: String
    let model: ShoeCatalogModel

    enum CodingKeys: String, CodingKey {
        case usSize = "us_size"
        case model
    }

    // Verified from the barcode example and the matching listing. Available offline as well.
    static let lostAndFoundGTIN = "00196154478656"
    static let lostAndFound = ShoeCatalogVariant(usSize: "10", model: ShoeCatalogModel(
        slug: "jordan-1-retro-high-og-chicago-lost-and-found",
        title: "Jordan 1 Retro High OG Chicago Lost and Found", brand: "Jordan",
        styleCode: "DZ5485-612",
        imageURL: "https://cdn.snkrdunk.com/upload_bg_removed/20221012010050-0.webp?size=l",
        sizeSystem: .usMen
    ))
}

struct ShoeSizeChart {
    enum Scale: String, CaseIterable {
        case us = "US"
        case otherUS = "Other US"
        case uk = "UK"
        case cm = "CM"
        case eu = "EU"
    }

    let brand: String
    let system: ShoeSizeSystem

    private var isNike: Bool {
        ["nike", "jordan", "air jordan"].contains(brand.lowercased())
    }

    private var isAsics: Bool { brand.caseInsensitiveCompare("ASICS") == .orderedSame }

    var scales: [Scale] {
        (isNike || isAsics) && system != .usYouth ? Scale.allCases : [.us]
    }

    func header(_ scale: Scale) -> String {
        switch scale {
        case .us: system.label
        case .otherUS: system == .usWomen ? "US M" : "US W"
        default: scale.rawValue
        }
    }

    func label(for size: String, scale: Scale) -> String? {
        guard scale != .us else { return "\(system.label) \(size)" }
        guard scales.contains(scale), let number = Double(size), number.isFinite, (1...22).contains(number) else { return nil }
        let mens = system == .usWomen ? number - 1.5 : number
        let conversion: (uk: Double, eu: Double, cm: Double)?
        if isNike {
            conversion = Self.nikeChart[mens]
        } else {
            conversion = Self.asicsChart[mens]
        }
        guard let conversion else { return nil }
        let converted: Double
        switch scale {
        case .us: return nil
        case .otherUS: converted = system == .usWomen ? mens : mens + 1.5
        case .uk: converted = conversion.uk
        case .eu: converted = conversion.eu
        case .cm: converted = conversion.cm
        }
        return "\(header(scale)) \(converted.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US"))))"
    }

    func marketSize(from raw: String, among availableSizes: [String]) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let scale = scales.first(where: { value.hasPrefix(header($0) + " ") }) {
            let matches = availableSizes.filter { label(for: $0, scale: scale) == value }
            return matches.count == 1 ? matches.first : nil
        }
        return availableSizes.contains(value) ? value : nil
    }

    // Manufacturer's adult size charts. CM uses the label size, not measured foot length.
    private static let nikeChart: [Double: (Double, Double, Double)] = [
        3.5:(3,35.5,22.5), 4:(3.5,36,23), 4.5:(4,36.5,23.5), 5:(4.5,37.5,23.5),
        5.5:(5,38,24), 6:(5.5,38.5,24), 6.5:(6,39,24.5), 7:(6,40,25),
        7.5:(6.5,40.5,25.5), 8:(7,41,26), 8.5:(7.5,42,26.5), 9:(8,42.5,27),
        9.5:(8.5,43,27.5), 10:(9,44,28), 10.5:(9.5,44.5,28.5), 11:(10,45,29),
        11.5:(10.5,45.5,29.5), 12:(11,46,30), 12.5:(11.5,47,30.5), 13:(12,47.5,31),
        13.5:(12.5,48,31.5), 14:(13,48.5,32), 14.5:(13.5,49,32.5), 15:(14,49.5,33),
        15.5:(14.5,50,33.5), 16:(15,50.5,34), 17:(16,51.5,35), 18:(17,52.5,36)
    ]

    private static let asicsChart: [Double: (Double, Double, Double)] = [
        4:(3,36,22.5), 5:(4,37.5,23.5), 5.5:(4.5,38,24), 6:(5,39,24.5),
        6.5:(5.5,39.5,25), 7:(6,40,25.5), 7.5:(6.5,40.5,25.75), 8:(7,41.5,26),
        8.5:(7.5,42,26.5), 9:(8,42.5,27), 9.5:(8.5,43.5,27.5), 10:(9,44,28),
        10.5:(9.5,44.5,28.25), 11:(10,45,28.5), 11.5:(10.5,46,29), 12:(11,46.5,29.5),
        12.5:(11.5,47,30), 13:(12,48,30.5), 13.5:(12.5,48.5,30.75), 14:(13,49,31),
        15:(14,50.5,32), 16:(15,51.5,33)
    ]
}
