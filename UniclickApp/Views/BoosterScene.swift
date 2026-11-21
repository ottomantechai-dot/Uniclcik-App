import CoreImage.CIFilterBuiltins
import SceneKit
import SwiftUI

struct BoosterPack: Decodable, Identifiable {
    let id: String
    let name: String
    let series: String
    let year: Int
    /// Precio de mercado de un sobre sellado en TCGplayer (USD), tomado el 21 nov 2026.
    /// Sin valor cuando TCGplayer no publica precio de mercado para ese sobre.
    var packPrice: Double? = nil

    static let paradoxRift = BoosterPack(id: "sv4", name: "Paradox Rift", series: "Scarlet & Violet", year: 2023,
                                         packPrice: 9.11)
    static let library = [paradoxRift] + ((try? BoosterResources.load("collections.json") as [BoosterPack]) ?? [])

    var catalog: String { id == "sv4" ? "paradox-rift.json" : "Collections/\(id)/cards.json" }
    var front: String { id == "sv4" ? "pack-front.jpg" : "Collections/\(id)/front.jpg" }
    var back: String { id == "sv4" ? "pack-back.jpg" : "Collections/back.jpg" }
    var logo: UIImage? {
        BoosterResources.image(id == "sv4" ? "paradox-rift-logo.png" : "Collections/\(id)/logo.png")
    }
}

struct BoosterCard: Decodable, Identifiable {
    let id: String
    let name: String
    let rarity: String
    let special: Bool
    let featured: Bool?
    let marketID: String?
    let referencePrice: Double?

    var isHit: Bool {
        featured ?? ["Illustration Rare", "Ultra Rare", "Special Illustration Rare", "Hyper Rare"].contains(rarity)
    }

    func image() -> UIImage? {
        BoosterResources.image("Cards/\(id).jpg")
    }
}

enum BoosterResources {
    static var folder: URL {
        Bundle.main.resourceURL!.appendingPathComponent("PackOpening", isDirectory: true)
    }

    static func load<T: Decodable>(_ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: folder.appendingPathComponent(name)))
    }

    static func image(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: folder.appendingPathComponent(name).path)
    }

    static func draw(from catalog: [BoosterCard]) throws -> [BoosterCard] {
        let standard = Dictionary(grouping: catalog.filter { !$0.special }, by: \.id)
            .values.compactMap(\.first)
        // La última carta es siempre de las más raras de la colección.
        let featured = catalog.filter { $0.featured == true }
        let top = featured.isEmpty
            ? catalog.filter { ["Special Illustration Rare", "Hyper Rare"].contains($0.rarity) }
            : featured
        guard standard.count >= 4, let hit = (top.isEmpty ? catalog.filter(\.isHit) : top).randomElement() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var cards = Array(standard.shuffled().prefix(4))
        // Las «ex» normales (Double Rare) salen de vez en cuando como una carta más, sin efecto especial.
        if Int.random(in: 0..<6) == 0, let double = catalog.filter({ $0.special && !$0.isHit }).randomElement() {
            cards[3] = double
        }
        return cards + [hit]
    }
}

/// Estado de la animación de la carta especial: giro, halo, destello y escala.
struct BoosterSpecialFX: Equatable {
    var index = -1
    var spin = 0.0
    var glow = 0.0
    var flash = 0.0
    var scale = 1.0
}

@MainActor
final class BoosterScene {
    private struct Manifest: Decodable {
        let fieldOfView: Double
        let sealHeight: Double
        let packTopHeight: Double
        let packHalfWidth: Double
        let geometry: [String: Mesh]
        let poses: [[String: Pose]]
    }

    private struct Mesh: Decodable {
        let positions: [Int]
        let normals: [Int]
        let uvs: [Int]
        let parts: [Part]
        let morphs: [Shape]
    }

    private struct Part: Decodable {
        let material: String
        let triangles: [Int]
    }

    private struct Shape: Decodable {
        let positions: [Int]
        let normals: [Int]
    }

    private struct Pose: Decodable {
        let transform: [Float]
        let weights: [Float]
        let visible: Bool

        var matrix: simd_float4x4 {
            simd_float4x4(columns: (
                SIMD4(transform[0], transform[1], transform[2], transform[3]),
                SIMD4(transform[4], transform[5], transform[6], transform[7]),
                SIMD4(transform[8], transform[9], transform[10], transform[11]),
                SIMD4(transform[12], transform[13], transform[14], transform[15])
            ))
        }
    }

    private struct Model {
        let manifest: Manifest
        let meshes: [String: ModelMesh]

        init() throws {
            manifest = try BoosterResources.load("scene.json")
            guard manifest.poses.count > 1,
                  manifest.poses.allSatisfy({ $0.values.allSatisfy { $0.transform.count == 16 } }) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let bytes = try Data(contentsOf: BoosterResources.folder.appendingPathComponent("geometry.bin"),
                                 options: .mappedIfSafe)
            func data(at span: [Int]) throws -> Data {
                guard span.count == 2, span[0] >= 0, span[0] <= bytes.count, span[1] >= 0,
                      span[1] <= (bytes.count - span[0]) / 4 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return bytes.subdata(in: span[0]..<(span[0] + span[1] * 4))
            }

            func source(_ span: [Int], _ semantic: SCNGeometrySource.Semantic, _ size: Int) throws -> SCNGeometrySource {
                let block = try data(at: span)
                return SCNGeometrySource(data: block, semantic: semantic, vectorCount: block.count / (4 * size),
                                         usesFloatComponents: true, componentsPerVector: size,
                                         bytesPerComponent: 4, dataOffset: 0, dataStride: 4 * size)
            }

            meshes = try manifest.geometry.mapValues { mesh in
                let elements = try mesh.parts.map { part in
                    let indices = try data(at: part.triangles)
                    return SCNGeometryElement(data: indices, primitiveType: .triangles,
                                              primitiveCount: indices.count / 12, bytesPerIndex: 4)
                }
                let mapping = try source(mesh.uvs, .texcoord, 2)
                func geometry(positions: [Int], normals: [Int]) throws -> SCNGeometry {
                    SCNGeometry(sources: [
                        try source(positions, .vertex, 3), try source(normals, .normal, 3), mapping
                    ], elements: elements)
                }
                return try ModelMesh(
                    geometry: geometry(positions: mesh.positions, normals: mesh.normals),
                    materials: mesh.parts.map(\.material),
                    morphs: mesh.morphs.map { try geometry(positions: $0.positions, normals: $0.normals) }
                )
            }
        }
    }

    private struct ModelMesh {
        let geometry: SCNGeometry
        let materials: [String]
        let morphs: [SCNGeometry]

        func node(materials palette: [String: SCNMaterial], morphing: Bool) throws -> SCNNode {
            guard let geometry = geometry.copy() as? SCNGeometry else {
                throw CocoaError(.fileReadCorruptFile)
            }
            geometry.materials = try materials.map {
                guard let material = palette[$0] else { throw CocoaError(.fileReadCorruptFile) }
                return material
            }
            let node = SCNNode(geometry: geometry)
            if morphing && !morphs.isEmpty {
                let morpher = SCNMorpher()
                morpher.calculationMode = .additive
                morpher.targets = morphs
                node.morpher = morpher
            }
            return node
        }
    }

    private static let model = Result { try Model() }
    private static let studio = BoosterResources.image("studio.jpg")

    @MainActor
    final class Wheel {
        let scene = SCNScene()
        let camera = SCNNode()
        private let model: Model
        private var packs: [String: SCNNode] = [:]

        init(library: [BoosterPack]) throws {
            model = try BoosterScene.model.get()
            BoosterScene.configureStage(scene, camera: camera, fieldOfView: model.manifest.fieldOfView)
            for pack in library {
                packs[pack.id] = try makePack(pack)
            }
        }

        var preparedNodes: [SCNNode] { Array(packs.values) }

        func place(_ library: [BoosterPack], layout: BoosterWheelLayout, position: Double,
                   tilt: CGSize, reduceMotion: Bool) {
            guard layout.size.width > 0 else { return }
            let sceneWidth = 12 * tan(model.manifest.fieldOfView * .pi / 360)
            let unitsPerPoint = sceneWidth / layout.size.width
            let packScale = layout.packWidth * unitsPerPoint / (2 * model.manifest.packHalfWidth)
            for (index, pack) in library.enumerated() {
                let placement = layout.placement(index: index, count: library.count, position: position)
                guard placement.isVisible else {
                    packs[pack.id]?.isHidden = true
                    continue
                }
                guard let node = packs[pack.id] else { continue }
                let inspection = reduceMotion ? 0 : max(0, 1 - placement.depth)
                let yaw = (reduceMotion ? 0 : placement.yaw) + tilt.width * inspection
                let pitch = tilt.height * inspection
                let z = -placement.depth * 0.17
                let perspective = (6 - z) / 6
                let scale = Float(packScale * placement.scale * perspective)
                node.isHidden = false
                node.opacity = placement.opacity
                node.simdScale = SIMD3(repeating: scale)
                node.simdPosition = SIMD3(
                    Float((placement.x + tilt.width * inspection * 0.55) * unitsPerPoint * perspective),
                    Float(-(placement.y + tilt.height * inspection * 0.55) * unitsPerPoint * perspective),
                    Float(z)
                )
                node.simdOrientation = simd_quatf(angle: Float(yaw) * .pi / 180, axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: Float(pitch) * .pi / 180, axis: SIMD3(1, 0, 0))
            }
        }

        private func makePack(_ pack: BoosterPack) throws -> SCNNode {
            let materials = try BoosterScene.packMaterials(for: pack)
            let root = SCNNode()
            for label in ["wrapper", "flap", "bottom"] {
                guard let mesh = model.meshes[label], let pose = model.manifest.poses[0][label] else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let node = try mesh.node(materials: materials, morphing: false)
                node.simdTransform = pose.matrix
                root.addChildNode(node)
            }
            root.isHidden = true
            scene.rootNode.addChildNode(root)
            return root
        }
    }

    let scene = SCNScene()
    let camera = SCNNode()
    private let pivot = SCNNode()
    private let sealGuide = SCNNode()
    private let sealGuideGeometry = SCNPlane(width: 1, height: 0.004)
    private let sealGlint = SCNNode()
    private let sealGlintGeometry = SCNPlane(width: 0.15, height: 0.004)
    private var sealTrim: [SCNNode] = []
    private var tearGeometries: [SCNGeometry] = []
    private let manifest: Manifest
    private let settledCardY: Double
    private var nodes: [String: SCNNode] = [:]
    private let face = SCNMaterial()
    private var cardNodes: [SCNNode] = []
    private var cardFaces: [SCNMaterial] = []
    private var handIDs: [String] = []
    private var lastFrame = -1.0
    private var lastFirstCard = -1
    private var lastSlide = 0.0
    private var lastViewport = CGSize.zero
    private var lastFocus = 0.0
    private var lastDisplayScale: CGFloat = 0
    private var lastSpecial = BoosterSpecialFX()
    private let specialEffects = SCNNode()
    private var specialMaterials: [SCNMaterial] = []

    var finalFrame: Double { Double(manifest.poses.count - 1) }
    private var sceneWidth: Double { 2 * cameraDistance * tan(manifest.fieldOfView * .pi / 360) }

    static let sealBeamWidth: CGFloat = 5
    private static let sealGlowWidth: CGFloat = 18

    private let cameraDistance = 6.0
    private let sealFront = 0.038
    private let sealEdgeOffset = 0.0035
    private let closeScale = 1.24
    private let closeTopFraction = 0.45
    private let revealedCardScale = 1.24

    private func closeDrop(in viewport: CGSize) -> Double {
        let halfHeight = viewport.height / max(1, viewport.width) * sceneWidth / 2
        let top = halfHeight * (1 - 2 * closeTopFraction)
        return manifest.packTopHeight * closeScale - top
    }

    func focusedSeal(in viewport: CGSize) -> CGRect {
        let depth = sealFront * closeScale
        let widthAtSeal = sceneWidth * (1 - depth / cameraDistance)
        let height = (manifest.sealHeight - sealEdgeOffset) * closeScale - closeDrop(in: viewport)
        let centerY = viewport.height / 2 - viewport.width * height / widthAtSeal
        let projectedHalfWidth = viewport.width * manifest.packHalfWidth * closeScale / widthAtSeal
        return CGRect(x: viewport.width / 2 - projectedHalfWidth, y: centerY,
                      width: 2 * projectedHalfWidth, height: 0)
    }

    func containsSealedPack(_ location: CGPoint, in viewport: CGSize) -> Bool {
        abs(location.x - viewport.width / 2) < viewport.width * 0.35 &&
        abs(location.y - viewport.height / 2) < viewport.width * manifest.packTopHeight / sceneWidth + 12
    }

    init(pack: BoosterPack) throws {
        let model = try Self.model.get()
        manifest = model.manifest
        settledCardY = Double(manifest.poses.last?["card"]?.matrix.columns.3.y ?? 0)

        var materials = try Self.packMaterials(for: pack)
        materials["cardBack"] = try Self.printed("card-back.jpg", metalness: 0.04)
        materials["cardTrim"] = Self.metal(.init(white: 0.52, alpha: 1), roughness: 0.47)
        Self.configurePrint(face, metalness: 0.04)
        materials["cardFace"] = face

        for (label, mesh) in model.meshes {
            let object = try mesh.node(materials: materials, morphing: true)
            object.name = label
            if label == "flap", let geometry = object.geometry {
                applyTearShader(to: geometry, heightOffset: 0)
            }
            pivot.addChildNode(object)
            nodes[label] = object
        }

        makeSealTrim()

        guard let card = nodes["card"], let geometry = card.geometry else {
            throw CocoaError(.fileReadCorruptFile)
        }
        cardNodes = [card]
        cardFaces = [face]
        for _ in 1..<5 {
            let copy = card.clone()
            guard let copyGeometry = geometry.copy() as? SCNGeometry else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let copyFace = SCNMaterial()
            Self.configurePrint(copyFace, metalness: 0.04)
            copyGeometry.materials = geometry.materials.map { $0 === face ? copyFace : $0 }
            copy.geometry = copyGeometry
            pivot.addChildNode(copy)
            cardNodes.append(copy)
            cardFaces.append(copyFace)
        }
        nodes["card"] = nil
        makeSpecialEffects(for: geometry)

        Self.configureStage(scene, camera: camera, fieldOfView: manifest.fieldOfView)
        scene.rootNode.addChildNode(pivot)

        sealGuideGeometry.materials = [Self.glowingSealMaterial(Self.sealGuideTexture())]
        sealGuide.geometry = sealGuideGeometry
        sealGuide.isHidden = true
        pivot.addChildNode(sealGuide)

        sealGlintGeometry.materials = [Self.glowingSealMaterial(Self.sealGlintTexture())]
        sealGlint.geometry = sealGlintGeometry
        sealGlint.opacity = 0
        sealGuide.addChildNode(sealGlint)

        apply(frame: 0, viewport: .zero, focus: 0, firstCard: 0, slide: 0, cut: 0, cutWeight: 0)
    }

    func show(_ hand: [BoosterCard]) {
        let incoming = hand.map(\.id)
        guard incoming != handIDs else { return }
        handIDs = incoming
        for (card, material) in zip(hand, cardFaces) {
            let image = card.image()
            material.diffuse.contents = image
            material.emission.contents = image
        }
        if let special = hand.firstIndex(where: \.isHit), cardNodes.indices.contains(special) {
            cardNodes[special].addChildNode(specialEffects)
        } else {
            specialEffects.removeFromParentNode()
        }
    }

    // MARK: Carta especial

    private static let sheenShader = """
    #pragma arguments
    float glow;
    float flash;
    #pragma transparent
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float mask = _output.color.a;
    float t = scn_frame.time;
    float sweep = fract(t * 0.30) * 2.8 - 0.9;
    float band = 1.0 - smoothstep(0.0, 0.17, abs(uv.x + uv.y * 0.55 - sweep));
    float wave = (uv.x + uv.y) * 0.8 + t * 0.14;
    float3 tint = 0.5 + 0.5 * cos(6.2831853 * (float3(wave, wave, wave) + float3(0.0, 0.33, 0.67)));
    float3 light = mix(float3(1.0, 1.0, 1.0), tint, 0.35) * band * 0.26 * glow + float3(1.0, 1.0, 1.0) * flash;
    _output.color.rgb = light * mask;
    _output.color.a = min(1.0, band * 0.26 * glow + flash) * mask;
    """

    var specialEffectNodes: [SCNNode] { [specialEffects] }
    private var cardSize = CGSize.zero

    /// Rectángulo en pantalla de la carta que está delante, ya colocada.
    func settledCardFrame(in viewport: CGSize) -> CGRect {
        guard let pose = manifest.poses.last?["card"], cardSize.width > 0, viewport.width > 0 else { return .zero }
        let position = pose.matrix.columns.3
        let visibleWidth = sceneWidth * (1 - Double(position.z) / cameraDistance)
        let scale = viewport.width / visibleWidth
        let width = cardSize.width * revealedCardScale * scale
        let height = cardSize.height * revealedCardScale * scale
        return CGRect(x: viewport.width / 2 + Double(position.x) * scale - width / 2,
                      y: viewport.height / 2 - height / 2, width: width, height: height)
    }

    private func makeSpecialEffects(for geometry: SCNGeometry) {
        let (low, high) = geometry.boundingBox
        let width = CGFloat(high.x - low.x), height = CGFloat(high.y - low.y)
        let centerX = (high.x + low.x) / 2, centerY = (high.y + low.y) / 2
        cardSize = CGSize(width: width, height: height)
        specialMaterials = []

        let mask = Self.cardMask()
        for facing in [Float(1), -1] {
            let plane = SCNPlane(width: width, height: height)
            let material = Self.effectMaterial(mask: mask, shader: Self.sheenShader, blend: .add)
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(centerX, centerY, facing > 0 ? high.z + 0.0018 : low.z - 0.0018)
            if facing < 0 { node.eulerAngles.y = .pi }
            node.renderingOrder = 11
            specialEffects.addChildNode(node)
            specialMaterials.append(material)
        }
        specialEffects.isHidden = true
    }

    private static func effectMaterial(mask: UIImage, shader: String, blend: SCNBlendMode) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = mask
        material.blendMode = blend
        material.writesToDepthBuffer = false
        material.shaderModifiers = [.fragment: shader]
        material.setValue(Float(0), forKey: "glow")
        material.setValue(Float(0), forKey: "flash")
        return material
    }

    private static func cardMask() -> UIImage {
        let size = CGSize(width: 250, height: 350)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.width * 0.058).fill()
        }
    }

    func orient(tilt: CGSize, shift: CGSize) {
        let yaw = Float(tilt.width) * .pi / 180
        let pitch = Float(tilt.height) * .pi / 180
        pivot.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        pivot.simdPosition = SIMD3(Float(shift.width), Float(shift.height), 0)
    }

    private static let tearShader = """
    #pragma arguments
    float packHalfWidth;
    float sealHeight;
    float heightOffset;
    float tearProgress;
    float tearWeight;
    #pragma body
    float lateral = clamp(0.5 + _geometry.position.x / (2.0 * packHalfWidth), 0.0, 1.0);
    float freed = (1.0 - smoothstep(tearProgress - 0.055, tearProgress + 0.014, lateral))
                  * tearWeight * smoothstep(0.0, 0.10, tearProgress);
    float aboveSeal = max(0.0, _geometry.position.y + heightOffset - sealHeight);
    float slack = smoothstep(0.0, 0.32, max(0.0, tearProgress - lateral));
    float angle = freed * (0.72 + 0.60 * slack);
    float foldSin = sin(angle);
    float foldCos = cos(angle);
    _geometry.position.y += aboveSeal * (foldCos - 1.0) + freed * 0.026;
    _geometry.position.z += aboveSeal * foldSin + freed * 0.023;
    float normalY = _geometry.normal.y;
    float normalZ = _geometry.normal.z;
    _geometry.normal.y = normalY * foldCos - normalZ * foldSin;
    _geometry.normal.z = normalY * foldSin + normalZ * foldCos;
    """

    private func applyTearShader(to geometry: SCNGeometry, heightOffset: Float) {
        geometry.shaderModifiers = [.geometry: Self.tearShader]
        geometry.setValue(Float(manifest.packHalfWidth), forKey: "packHalfWidth")
        geometry.setValue(Float(manifest.sealHeight), forKey: "sealHeight")
        geometry.setValue(heightOffset, forKey: "heightOffset")
        geometry.setValue(Float(0), forKey: "tearProgress")
        geometry.setValue(Float(0), forKey: "tearWeight")
        tearGeometries.append(geometry)
    }

    private func makeSealTrim() {
        let white = SCNMaterial()
        white.lightingModel = .constant
        white.diffuse.contents = UIColor.white
        let seamY = manifest.sealHeight - sealEdgeOffset

        for (part, distance, depth) in [("flap", 0.020, 0.0375), ("wrapper", -0.020, 0.0485)] {
            guard let parent = nodes[part] else { continue }
            let trim = SCNPlane(width: 2 * manifest.packHalfWidth * 0.983, height: 0.004)
            trim.widthSegmentCount = 54
            trim.materials = [white]

            let edge = SCNNode(geometry: trim)
            let y = Float(seamY + distance)
            edge.position = SCNVector3(0, y, Float(depth))
            edge.opacity = 0
            parent.addChildNode(edge)
            sealTrim.append(edge)

            if part == "flap" { applyTearShader(to: trim, heightOffset: y) }
        }
    }

    func apply(frame: Double, viewport: CGSize, focus: Double, firstCard: Int, slide: Double,
               cut: Double, cutWeight: Double, sealGuideProgress: Double = 0, animateSealGuide: Bool = false,
               displayScale: CGFloat = 1, special: BoosterSpecialFX = BoosterSpecialFX()) {
        let clamped = min(max(0, frame), finalFrame)
        let enlarged = 1 + (closeScale - 1) * focus
        let lowered = closeDrop(in: viewport) * focus
        updateSealGuide(viewport: viewport, scale: enlarged, lowered: lowered,
                        progress: sealGuideProgress, animate: animateSealGuide)
        for geometry in tearGeometries {
            geometry.setValue(Float(cut), forKey: "tearProgress")
            geometry.setValue(Float(cutWeight), forKey: "tearWeight")
        }

        let lit = special.glow > 0.001 || special.flash > 0.001
        if specialEffects.isHidden == lit { specialEffects.isHidden = !lit }
        for material in specialMaterials {
            material.setValue(Float(special.glow), forKey: "glow")
            material.setValue(Float(special.flash), forKey: "flash")
        }

        guard clamped != lastFrame || firstCard != lastFirstCard || slide != lastSlide || special != lastSpecial ||
                viewport != lastViewport || focus != lastFocus || displayScale != lastDisplayScale else { return }
        lastSpecial = special
        lastFrame = clamped
        lastFirstCard = firstCard
        lastSlide = slide
        lastViewport = viewport
        lastFocus = focus
        lastDisplayScale = displayScale
        for trim in sealTrim {
            trim.opacity = ease((focus - 0.72) / 0.28)
            guard viewport.width > 0, let plane = trim.geometry as? SCNPlane else { continue }
            // Convert three screen pixels to local height at the strip's depth.
            let depth = Double(trim.position.z) * enlarged
            let visibleWidth = sceneWidth * (1 - depth / cameraDistance)
            let height = 3 * visibleWidth / (viewport.width * displayScale * enlarged)
            if plane.height != height { plane.height = height }
        }

        let index = Int(clamped)
        let next = min(index + 1, manifest.poses.count - 1)
        let fraction = Float(clamped - Double(index))
        let previous = manifest.poses[index]
        let following = manifest.poses[next]

        let halfHeight = viewport.height / max(1, viewport.width) * sceneWidth / 2
        let parkedY = -halfHeight - manifest.packTopHeight * enlarged - 0.16
        let originalFall = Double(manifest.poses.last?["wrapper"]?.matrix.columns.3.y ?? -3.5)
        let fallScale = (parkedY + lowered) / min(-0.1, originalFall)

        for (name, node) in nodes {
            guard let a = previous[name], let b = following[name] else { continue }
            node.isHidden = !a.visible || (name == "flap" ? clamped >= 65 : clamped >= 96)
            var transform = interpolatedPose(from: a, to: b, fraction: fraction)
            for column in 0..<3 { transform[column] *= Float(enlarged) }
            transform.columns.3.x *= Float(enlarged)
            let verticalTravel = name == "flap" ? enlarged * 0.42 : fallScale
            transform.columns.3.y = transform.columns.3.y * Float(verticalTravel) - Float(lowered)
            node.simdTransform = transform
            for (i, value) in a.weights.enumerated() {
                node.morpher?.setWeight(CGFloat(value + (b.weights[i] - value) * fraction), forTargetAt: i)
            }
            if name == "flap", let morpher = node.morpher, morpher.targets.count > a.weights.count {
                let approachFlex = 2 * focus * (1 - focus)
                morpher.setWeight(CGFloat(approachFlex), forTargetAt: a.weights.count)
            }
        }

        guard let a = previous["card"], let b = following["card"] else { return }
        let emergence = ease((clamped - 58) / 29)
        let cardScale = Float(1 + (revealedCardScale - 1) * ease((clamped - 70) / 24))
        var front = interpolatedPose(from: a, to: b, fraction: fraction)
        let alignment = Float(ease((clamped - 80) / 18))
        for column in 0..<3 {
            let upright = matrix_identity_float4x4[column]
            front[column] = (front[column] + (upright - front[column]) * alignment) * cardScale
        }
        front.columns.3.y -= Float(lowered * (1 - emergence) + settledCardY * emergence)

        let reveal = ease(slide / 0.58)
        for (index, node) in cardNodes.enumerated() {
            node.isHidden = !a.visible || index < firstCard
            guard !node.isHidden else { continue }
            let depth = index - firstCard
            var transform = front
            if depth == 0 {
                transform.columns.3.x += Float(sceneWidth * slide)
            } else {
                let layer = Float(Double(depth) - reveal) * Float(emergence)
                transform.columns.3.y -= layer * 0.013
                transform.columns.3.z -= max(0.009, Float(Double(depth) - reveal) * 0.047)
            }
            if index == special.index, special.spin != 0 || special.scale != 1 {
                transform = transform * simd_float4x4(simd_quatf(angle: Float(special.spin), axis: SIMD3(0, 1, 0)))
                for column in 0..<3 { transform[column] *= Float(special.scale) }
            }
            node.simdTransform = transform
        }
    }

    private func interpolatedPose(from a: Pose, to b: Pose, fraction: Float) -> simd_float4x4 {
        var pose = a.matrix
        if fraction > 0, a.visible == b.visible {
            let target = b.matrix
            for column in 0..<4 { pose[column] += (target[column] - pose[column]) * fraction }
        }
        return pose
    }

    private func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private static func configureStage(_ scene: SCNScene, camera: SCNNode, fieldOfView: Double) {
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 1.04
        let lens = SCNCamera()
        lens.projectionDirection = .horizontal
        lens.fieldOfView = fieldOfView
        lens.zNear = 0.12
        lens.zFar = 30
        camera.camera = lens
        camera.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(camera)

        let lights: [(position: SCNVector3, intensity: CGFloat, color: UIColor)] = [
            (.init(-2.2, 2.4, 4.2), 560, .white),
            (.init(2.6, -0.8, 2.8), 270, .init(red: 0.71, green: 0.84, blue: 1, alpha: 1))
        ]
        for spec in lights {
            let node = SCNNode()
            let light = SCNLight()
            light.type = .directional
            light.intensity = spec.intensity
            light.color = spec.color
            node.light = light
            node.position = spec.position
            scene.rootNode.addChildNode(node)
            node.look(at: .init(0, 0, 0))
        }
    }

    private static func packMaterials(for pack: BoosterPack) throws -> [String: SCNMaterial] {
        [
            "front": try printed(pack.front, colorStrength: pack.id == "sv4" ? 1 : 0.42),
            "reverse": try printed(pack.back, colorStrength: pack.id == "sv4" ? 1 : 0),
            "crimp": metal(.init(white: 0.64, alpha: 1), roughness: 0.28),
            "edge": try brushed("foil-edge.jpg", roughness: 0.45),
            "liner": try brushed("foil-liner.jpg", roughness: 0.55)
        ]
    }

    private func updateSealGuide(viewport: CGSize, scale: Double, lowered: Double,
                                 progress: Double, animate: Bool) {
        sealGuide.isHidden = progress <= 0
        let halfWidth = manifest.packHalfWidth * scale
        if progress > 0 {
            let z = sealFront * scale
            let unitsPerPoint = sceneWidth * (1 - z / cameraDistance) / max(1, viewport.width)
            let guideY = (manifest.sealHeight - sealEdgeOffset) * scale - lowered
            sealGuideGeometry.height = Self.sealGlowWidth * unitsPerPoint
            sealGuideGeometry.width = 2 * halfWidth * progress
            sealGuide.simdPosition = SIMD3(Float(halfWidth * (progress - 1)), Float(guideY), Float(z))
        }

        let action = "sealGlint"
        guard animate, progress >= 1 else {
            sealGlint.removeAction(forKey: action)
            sealGlint.opacity = 0
            return
        }
        guard sealGlint.action(forKey: action) == nil else { return }

        sealGlintGeometry.height = sealGuideGeometry.height * 1.15
        let start = SCNVector3(Float(-halfWidth), 0, 0.001)
        let end = SCNVector3(Float(halfWidth), 0, 0.001)
        let travel = SCNAction.move(to: end, duration: 1.18)
        travel.timingMode = .easeInEaseOut
        let fade = SCNAction.sequence([.fadeIn(duration: 0.20), .wait(duration: 0.76), .fadeOut(duration: 0.22)])
        sealGlint.runAction(.repeatForever(.sequence([
            .move(to: start, duration: 0), .group([travel, fade]), .wait(duration: 0.45)
        ])), forKey: action)
    }

    private static func glowingSealMaterial(_ texture: UIImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = texture
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        return material
    }

    private static func sealGuideTexture() -> UIImage {
        let size = CGSize(width: 4, height: 96)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let halo = UIColor(red: 0.08, green: 0.51, blue: 1, alpha: 0.36)
            let blue = UIColor(red: 0.19, green: 0.75, blue: 1, alpha: 0.95)
            let core = UIColor(red: 0.62, green: 0.94, blue: 1, alpha: 1)
            let edge = halo.withAlphaComponent(0)
            let colors = [edge, halo, blue, core, blue, halo, edge].map(\.cgColor) as CFArray
            let stops: [CGFloat] = [0, 0.23, 0.37, 0.50, 0.63, 0.77, 1]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: stops) {
                renderer.cgContext.drawLinearGradient(gradient, start: .zero,
                    end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    private static func sealGlintTexture() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let tint = UIColor(red: 0.48, green: 0.89, blue: 1, alpha: 0.60)
            let colors = [UIColor.white, tint, tint.withAlphaComponent(0)].map(\.cgColor) as CFArray
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                         locations: [0, 0.34, 1]) {
                renderer.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                    endCenter: center, endRadius: size.width / 2, options: [])
            }
        }
    }

    private static func image(_ name: String) throws -> UIImage {
        guard let image = BoosterResources.image(name) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    private static func configurePrint(_ material: SCNMaterial, metalness: CGFloat) {
        material.lightingModel = .physicallyBased
        material.metalness.contents = metalness
        material.roughness.contents = metalness > 0.1 ? 0.25 : 0.40
        material.emission.intensity = metalness > 0.1 ? 0.42 : 0.35
        for channel in [material.diffuse, material.emission] {
            channel.minificationFilter = .linear
            channel.magnificationFilter = .linear
            channel.mipFilter = .linear
            channel.maxAnisotropy = 8
        }
    }

    private static let printColorContext = CIContext(options: [.cacheIntermediates: false])

    private static func vividPrint(_ image: UIImage, strength: Float) -> UIImage {
        guard let source = CIImage(image: image) else { return image }
        let color = CIFilter.colorControls()
        color.inputImage = source
        color.saturation = 1 + 0.26 * strength
        color.contrast = 1 + 0.04 * strength
        color.brightness = 0.018 * strength
        guard let output = color.outputImage,
              let corrected = printColorContext.createCGImage(output, from: source.extent) else { return image }
        return UIImage(cgImage: corrected, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func printed(_ name: String, metalness: CGFloat = 0.47, colorStrength: Float = 0) throws -> SCNMaterial {
        let material = SCNMaterial()
        configurePrint(material, metalness: metalness)
        let source = try image(name)
        let print = colorStrength > 0 ? vividPrint(source, strength: colorStrength) : source
        material.diffuse.contents = print
        material.emission.contents = print
        return material
    }

    private static func metal(_ color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.metalness.contents = 0.79
        material.roughness.contents = roughness
        return material
    }

    private static func brushed(_ name: String, roughness: CGFloat) throws -> SCNMaterial {
        let material = metal(.gray, roughness: roughness)
        let grain = try image(name)
        material.diffuse.contents = grain
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(4, 4, 1)
        return material
    }
}

struct BoosterWheelLayout {
    let size: CGSize

    var packWidth: CGFloat { min(size.width * 0.49, size.height * 0.31, 240) }
    var packHeight: CGFloat { packWidth * 1.90 }
    var spacing: CGFloat { max(1, min(size.width * 0.49, packWidth * 1.15)) }
    private var raised: CGFloat { min(28, size.height * 0.045) }

    struct Placement {
        let distance: Double
        let x: CGFloat
        let y: CGFloat

        var depth: Double { abs(distance) }
        var scale: CGFloat { 1 - min(2.5, depth) * 0.14 }
        var yaw: Double { -distance * 29 }
        var opacity: CGFloat {
            let edge = min(1, max(0, (2.65 - depth) / 1.45))
            return (1 - min(depth, 1.2) * 0.23) * edge * edge * (3 - 2 * edge)
        }
        var isVisible: Bool { depth < 2.65 }
    }

    func placement(index: Int, count: Int, position: Double) -> Placement {
        let count = Double(count)
        let raw = Double(index) - position
        let distance = raw - count * (raw / count).rounded()
        let x = sin(distance * 0.70) / sin(0.70) * spacing
        return Placement(distance: distance, x: x, y: -raised - min(2.5, abs(distance)) * 14)
    }
}

struct BoosterWheelStage: UIViewRepresentable, Animatable {
    let renderer: BoosterScene.Wheel
    let packs: [BoosterPack]
    let layout: BoosterWheelLayout
    var position: Double
    var tilt: CGSize
    let reduceMotion: Bool

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(position, .init(tilt.width, tilt.height)) }
        set {
            position = newValue.first
            tilt = .init(width: newValue.second.first, height: newValue.second.second)
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let view = BoosterStage.renderView(scene: renderer.scene, camera: renderer.camera)
        view.prepare(renderer.preparedNodes, completionHandler: nil)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        renderer.place(packs, layout: layout, position: position, tilt: tilt, reduceMotion: reduceMotion)
        let moving = tilt != .zero || position != position.rounded()
        if view.rendersContinuously != moving {
            view.rendersContinuously = moving
            view.isPlaying = moving
        }
        view.setNeedsDisplay()
    }
}

struct BoosterStage: UIViewRepresentable, Animatable {
    let renderer: BoosterScene
    let hand: [BoosterCard]
    let firstCard: Int
    let frame: Double
    var tilt: CGSize
    var shift: CGSize
    let viewport: CGSize
    let focus: Double
    let slide: Double
    let cut: Double
    let cutWeight: Double
    let sealGuideProgress: Double
    let animateSealGuide: Bool
    var special = BoosterSpecialFX()
    @Environment(\.displayScale) private var displayScale

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(tilt.width, tilt.height), .init(shift.width, shift.height)) }
        set {
            tilt = CGSize(width: newValue.first.first, height: newValue.first.second)
            shift = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    static func renderView(scene: SCNScene, camera: SCNNode) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = camera
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.isOpaque = false
        view.isUserInteractionEnabled = false
        view.rendersContinuously = false
        view.preferredFramesPerSecond = 60
        return view
    }

    func makeUIView(context: Context) -> SCNView {
        let view = Self.renderView(scene: renderer.scene, camera: renderer.camera)
        // Compila ya los brillos de la carta especial para que no haya parón al mostrarla.
        view.prepare(renderer.specialEffectNodes, completionHandler: nil)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        renderer.show(hand)
        renderer.apply(frame: frame, viewport: viewport, focus: focus, firstCard: firstCard, slide: slide,
                       cut: cut, cutWeight: cutWeight, sealGuideProgress: sealGuideProgress,
                       animateSealGuide: animateSealGuide, displayScale: displayScale, special: special)
        let playing = (animateSealGuide && sealGuideProgress >= 1) || special.glow > 0.001
        if view.rendersContinuously != playing {
            view.rendersContinuously = playing
            view.isPlaying = playing
        }
        renderer.orient(tilt: tilt, shift: shift)
        view.setNeedsDisplay()
    }
}
