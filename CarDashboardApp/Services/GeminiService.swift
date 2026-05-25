import Foundation
import UIKit

/// Llamadas REST a Gemini desde el dispositivo (MVP). La clave sale de `GeminiAPIKey` en Info.
actor GeminiService {
    static let shared = GeminiService()

    private let apiKey: String
    /// Detección / JSON rápido.
    private let session: URLSession
    /// `gemini-2.5-flash-image`: payloads grandes (varias fotos ref) + respuesta lenta → timeouts amplios y una sola petición activa por flujo (el lookbook ya no lanza 10 en paralelo).
    private let imageSession: URLSession

    private init() {
        let key = (Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.apiKey = key
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        let img = URLSessionConfiguration.default
        img.timeoutIntervalForRequest = 300
        img.timeoutIntervalForResource = 900
        img.waitsForConnectivity = true
        img.httpMaximumConnectionsPerHost = 2
        self.imageSession = URLSession(configuration: img)
    }

    /// Reintentos ante timeout / socket (habitual con payloads grandes o red inestable).
    private func imageGenerationData(for req: URLRequest, consoleTag: String) async throws -> (Data, URLResponse) {
        let maxAttempts = 3
        var lastErr: URLError?
        for attempt in 0 ..< maxAttempts {
            if attempt > 0 {
                let sec: UInt64 = attempt == 1 ? 4 : 12
                try await Task.sleep(nanoseconds: sec * 1_000_000_000)
            }
            do {
                return try await imageSession.data(for: req)
            } catch let urlErr as URLError {
                lastErr = urlErr
                let retryable: [URLError.Code] = [
                    .timedOut, .networkConnectionLost, .cannotConnectToHost,
                    .dnsLookupFailed, .notConnectedToInternet,
                ]
                if retryable.contains(urlErr.code), attempt < maxAttempts - 1 {
                    print(
                        "🟡 [\(consoleTag)] Reintento \(attempt + 2)/\(maxAttempts): \(urlErr.code.rawValue) \(urlErr.localizedDescription.prefix(72))…"
                    )
                    continue
                }
                throw urlErr
            }
        }
        throw lastErr ?? GeminiError.apiError("Red: sin respuesta")
    }

    // MARK: - Detección (box_2d 0–1000, orden [ymin, xmin, ymax, xmax])

    /// Resultado intermedio: crop ya guardado en disco.
    struct DetectedGarment: Sendable {
        let id: UUID
        let name: String
        let category: ClothingCategory?
        let originalCropRelativePath: String
        let boundingBox: NormalizedRect
    }

    func detectItems(in image: UIImage) async throws -> [DetectedGarment] {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiError("Falta GeminiAPIKey en Info.plist / xcconfig.")
        }

        let bitmap = image.closetBitmapForVision()
        guard let jpeg = bitmap.jpegData(compressionQuality: 0.9) else {
            throw GeminiError.encodingFailed
        }
        let base64 = jpeg.base64EncodedString()

        let prompt = """
        Detect every distinct wearable clothing item or accessory in this photo (shirts, t-shirts, blouses, jackets, blazers, coats, sweaters, dresses, jumpsuits, pants, jeans, skirts, shorts, shoes, sneakers, boots, ties, belts, hats, bags, watches, scarves, sunglasses).

        For EACH item return:
        - "name": short English product description, max 6 words
        - "category": one of exactly: tops, dresses_jumpsuits, pants_skirts, coats, shoes, accessories, bags, underwear
        - "box_2d": tight bounding box as [ymin, xmin, ymax, xmax] each integer from 0 to 1000 (NOT 0.0–1.0 floats).

        Skip skin, hair, background. Do not invent items not visible.

        Footwear: classify sneakers, athletic shoes, boots, sandals and similar as category "shoes".
        If two different shoes appear as separate wearable items (e.g. left and right spaced apart),
        output two distinct items each with category "shoes" and tight box_2d; if clearly one pair as a single worn unit, one entry is acceptable.
        The app captures four horizontal studio angles per shoe item afterward (front, sides, heel; no top-down view).
        """

        let responseSchema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "items": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "name": ["type": "STRING"],
                            "category": ["type": "STRING"],
                            "box_2d": [
                                "type": "ARRAY",
                                "items": ["type": "INTEGER"],
                            ],
                        ],
                        "required": ["name", "category", "box_2d"],
                    ],
                ],
            ],
            "required": ["items"],
        ]

        let generationConfig: [String: Any] = [
            "temperature": 0.2,
            "responseMimeType": "application/json",
            "responseSchema": responseSchema,
        ]

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt],
                ],
            ]],
            "generationConfig": generationConfig,
        ]

        let url = URL(
            string:
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        )!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: (response as? HTTPURLResponse)?.statusCode, body: bodyStr))
        }

        let jsonText = try Self.extractAllTextFromGeminiData(data)
        guard let jsonData = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let rawItems = root["items"] as? [[String: Any]]
        else { throw GeminiError.parsingFailed }

        var out: [DetectedGarment] = []
        for item in rawItems {
            guard let name = item["name"] as? String,
                  let catStr = item["category"] as? String,
                  let box = Self.parseGeminiBox2D(item["box_2d"]), box.count == 4
            else { continue }
            let yminV = box[0]
            let xminV = box[1]
            let ymaxV = box[2]
            let xmaxV = box[3]
            // Heurística: si el modelo devolvió ya fracciones 0–1, no dividir entre 1000.
            let maxVal = max(xminV, yminV, xmaxV, ymaxV)
            let scale = maxVal > 1.5 ? 1000.0 : 1.0
            var ymin = yminV / scale
            var xmin = xminV / scale
            var ymax = ymaxV / scale
            var xmax = xmaxV / scale
            if ymin > ymax { swap(&ymin, &ymax) }
            if xmin > xmax { swap(&xmin, &xmax) }
            var nx = xmin
            var ny = ymin
            var nw = xmax - xmin
            var nh = ymax - ymin
            nx = min(max(nx, 0), 1)
            ny = min(max(ny, 0), 1)
            nw = min(max(nw, 0.001), 1 - nx)
            nh = min(max(nh, 0.001), 1 - ny)
            let rect = NormalizedRect(x: nx, y: ny, width: nw, height: nh)

            guard let cropped = bitmap.closetCropped(normalized: rect),
                  let cropData = cropped.jpegData(compressionQuality: 0.9)
            else { continue }

            let fname = "\(UUID().uuidString.lowercased()).jpg"
            let rel: String = try ImageStore.save(cropData, inFolder: "crops", filename: fname)
            let cat = ClothingCategory.parsing(catStr)

            out.append(
                DetectedGarment(
                    id: UUID(),
                    name: name,
                    category: cat,
                    originalCropRelativePath: rel,
                    boundingBox: rect
                ))
        }
        return out
    }

    // MARK: - Prettify (imagen producto, fondo blanco)

    func prettify(cropRelativePath: String, category: String, itemName: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiError("Falta GeminiAPIKey.")
        }
        guard let image = ImageStore.load(cropRelativePath),
              let jpeg = image.jpegData(compressionQuality: 0.95)
        else { throw GeminiError.encodingFailed }

        let base64 = jpeg.base64EncodedString()
        let prompt = """
        TASK: Generate a brand new photorealistic studio product photograph of the clothing item shown in the input image. This is a generation task, NOT a description task. The output MUST be an image, not text.

        STYLE REFERENCE (replicate this aesthetic exactly):
        Professional fashion e-commerce catalog photography in the style of Zara, Massimo Dutti, COS, Uniqlo, Net-a-Porter, Mr Porter. Think: a single garment perfectly isolated on a clean white seamless background, the way you see clothes on a brand's product detail page. Like a strapless red ruffled dress photographed alone on pure white with a soft natural shadow beneath it.

        OUTPUT SPECIFICATIONS (mandatory):
        - Background: pure solid white #FFFFFF, seamless infinity cyclorama. No gradients, no textures, no other objects, no patterns.
        - Lighting: bright soft even studio softbox lighting from front and slightly above. Shadowless on the background. The garment is well-lit and clearly visible.
        - Contact shadow: ONE single subtle realistic shadow directly beneath the garment, 10–15% opacity, soft feathered edges, grounding the item naturally on the surface.
        - Composition: garment perfectly centered, presented as if floating or laid flat, fully visible top-to-bottom, ~10% padding margin on all sides. Vertical/portrait orientation for most items.
        - Camera: straight-on flat-lay or ghost-mannequin catalog angle, tack-sharp focus, high resolution, no distortion.
        - Aspect ratio: square 1:1 (1024x1024 minimum).

        FIDELITY REQUIREMENTS (CRITICAL — do not violate):
        - Preserve EXACTLY the original color (down to the exact hue and saturation), fabric texture, weave, pattern, print, stitching, buttons, zippers, hardware, ruffles, lace, and material of the input garment. The output must be 100% recognizable as the same physical garment.
        - Do NOT recolor. Do NOT restyle. Do NOT change the cut, length, neckline, sleeve length, or silhouette.
        - Do NOT add brand logos, tags, labels, swing tickets, or text that were not visible in the input.
        - If the input is partially occluded (hidden by an arm, another garment, etc.), realistically reconstruct ONLY the hidden parts to complete the garment, while keeping all visible parts pixel-faithful.

        REMOVE from the output (must NOT appear):
        - Any skin, hands, faces, hair, body parts, arms, legs, torso.
        - Any other garments that were adjacent or layered.
        - Any background props, walls, floors, furniture, mirrors, doorways from the original photo.
        - Hangers, mannequin parts, clips, hooks, pins.
        - Any people, even partially.

        DELIVERABLE:
        A single clean square product photograph of the garment alone on pure white. No text overlays, no watermarks, no borders, no captions.

        Item category: \(category)
        Item description: \(itemName)

        Now generate the image.
        """

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt],
                ],
            ]],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"],
                "temperature": 0.4,
            ],
        ]

        /// Modelo con salida multimodal imagen (`gemini-2.5-flash` texto no devuelve inline image).
        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.parsingFailed }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🟡 [Prettify] Llamando Gemini gemini-2.5-flash-image (\(cropRelativePath)) para \(itemName) (\(category))…")

        let backoffSeconds: [UInt64] = [5, 15, 45]
        var lastData: Data?
        var lastResponse: URLResponse?

        attempts: for attempt in 0 ..< backoffSeconds.count + 1 {
            let pair = try await imageGenerationData(for: req, consoleTag: "Prettify")
            lastData = pair.0
            lastResponse = pair.1
            let httpOpt = pair.1 as? HTTPURLResponse

            if let http = httpOpt, (200 ..< 300).contains(http.statusCode) {
                let data = pair.0
                Self.logGeminiMultimodalResponseParts(data, tag: "[Prettify]")

                guard let b64data = Self.extractFirstInlineImageBase64(from: data),
                      let imgData = Self.decodeGeminiImageBase64(b64data)
                else {
                    let raw = String(data: data, encoding: .utf8) ?? "<binary>"
                    print(
                        "🔴 [Prettify] Sin imagen en la respuesta. Revisa model + responseModalities [TEXT,IMAGE]. Raw: \(raw.prefix(400))"
                    )
                    throw GeminiError.apiError(
                        "Gemini no devolvió imagen (revisa consola Xcode filtrando [Prettify]). Comprueba modelo gemini-2.5-flash-image y modalities."
                    )
                }

                let fname = "\(UUID().uuidString.lowercased()).jpg"
                let rel = try ImageStore.save(imgData, inFolder: "prettified", filename: fname)
                print("✅ [Prettify] Imagen guardada: \(rel)")
                return rel
            }

            let bodyStr = String(data: pair.0, encoding: .utf8) ?? ""
            let code = httpOpt?.statusCode ?? 0
            print("🔴 [Prettify] HTTP \(code): \(bodyStr.prefix(500))")

            if attempt < backoffSeconds.count, code == 429 {
                let sec = backoffSeconds[attempt]
                print("🟡 [Prettify] Reintentando tras \(sec)s por 429…")
                try await Task.sleep(nanoseconds: sec * 1_000_000_000)
                continue attempts
            }

            throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: code, body: bodyStr))
        }

        let bodyStr = String(data: lastData ?? Data(), encoding: .utf8) ?? ""
        throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: (lastResponse as? HTTPURLResponse)?.statusCode, body: bodyStr))
    }

    // MARK: - Lookbook (5 refs → variantes studio / lifestyle por llamada)

    func generateLookbookStudio(
        referenceRelativePaths: [String],
        variant: LookbookStudioShot,
        itemName: String
    ) async throws -> String {
        let prompt = Self.lookbookStudioPrompt(for: variant, itemName: itemName)
        return try await executeLookbookFlashImageGeneration(
            referenceRelativePaths: referenceRelativePaths,
            faceRelativePath: nil,
            prompt: prompt,
            temperature: 0.45,
            folder: "lookbook_studio",
            logTag: "Studio-\(variant.rawValue)",
            catalogItemLabel: itemName
        )
    }

    func generateLookbookLifestyle(
        referenceRelativePaths: [String],
        variant: LookbookLifestyleShot,
        itemName: String,
        faceReferenceRelativePath: String?
    ) async throws -> String {
        let faceTrim = faceReferenceRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasFace = !faceTrim.isEmpty && ImageStore.load(faceTrim) != nil
        let prompt = Self.lookbookLifestylePrompt(for: variant, itemName: itemName, hasFace: hasFace)
        let temperature = hasFace ? 0.38 : 0.52
        return try await executeLookbookFlashImageGeneration(
            referenceRelativePaths: referenceRelativePaths,
            faceRelativePath: hasFace ? faceTrim : nil,
            prompt: prompt,
            temperature: temperature,
            folder: "lookbook_lifestyle",
            logTag: "Life-\(variant.rawValue)",
            catalogItemLabel: itemName
        )
    }

    /// Multi-imagen entrada + texto; guarda JPG en `lookbook_studio` o `lookbook_lifestyle`.
    private func executeLookbookFlashImageGeneration(
        referenceRelativePaths: [String],
        faceRelativePath: String?,
        prompt: String,
        temperature: Double,
        folder: String,
        logTag: String,
        catalogItemLabel: String
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiError("Falta GeminiAPIKey.")
        }
        var multimodalParts: [[String: Any]] = []

        if let faceRel = faceRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !faceRel.isEmpty,
           let fi = ImageStore.load(faceRel),
           let jpeg = fi.jpegData(compressionQuality: 0.92)
        {
            multimodalParts.append([
                "inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()],
            ])
        }

        for rel in referenceRelativePaths where !rel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let img = ImageStore.load(rel),
                  let jpeg = img.jpegData(compressionQuality: 0.88)
            else { continue }
            multimodalParts.append([
                "inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()],
            ])
        }
        multimodalParts.append(["text": prompt])

        guard multimodalParts.count >= 2 else {
            throw GeminiError.encodingFailed
        }

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": multimodalParts]],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"],
                "temperature": temperature,
            ],
        ]

        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.parsingFailed }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let faceLogSuffix = ({
            guard let fp = faceRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !fp.isEmpty
            else { return "" }
            return "+face"
        })()
        print(
            "🟡 [Lookbook-\(logTag)] Llamando gemini-2.5-flash-image — \(catalogItemLabel) (\(referenceRelativePaths.count) refs\(faceLogSuffix))…"
        )

        let backoffSeconds: [UInt64] = [5, 15, 45]
        var lastData: Data?
        var lastResponse: URLResponse?

        attempts: for attempt in 0 ..< backoffSeconds.count + 1 {
            let pair = try await imageGenerationData(for: req, consoleTag: "Lookbook-\(logTag)")
            lastData = pair.0
            lastResponse = pair.1
            let httpOpt = pair.1 as? HTTPURLResponse

            if let http = httpOpt, (200 ..< 300).contains(http.statusCode) {
                Self.logGeminiMultimodalResponseParts(pair.0, tag: "[Lookbook-\(logTag)]")
                guard let b64data = Self.extractFirstInlineImageBase64(from: pair.0),
                      let imgData = Self.decodeGeminiImageBase64(b64data)
                else {
                    print(
                        "🔴 [Lookbook-\(logTag)] Sin imagen multimodal — revisa model + responseModalities [TEXT,IMAGE].")
                    throw GeminiError.apiError("Lookbook sin imagen de salida (consola `[Lookbook-\(logTag)]`).")
                }
                let fname = "\(UUID().uuidString.lowercased()).jpg"
                let rel = try ImageStore.save(imgData, inFolder: folder, filename: fname)
                print("✅ [Lookbook-\(logTag)] Guardado: \(rel)")
                return rel
            }

            let bodyStr = String(data: pair.0, encoding: .utf8) ?? ""
            let code = httpOpt?.statusCode ?? 0
            print("🔴 [Lookbook-\(logTag)] HTTP \(code): \(bodyStr.prefix(400))")

            if attempt < backoffSeconds.count, code == 429 {
                let sec = backoffSeconds[attempt]
                print("🟡 [Lookbook-\(logTag)] Reintentando tras \(sec)s por 429…")
                try await Task.sleep(nanoseconds: sec * 1_000_000_000)
                continue attempts
            }

            throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: code, body: bodyStr))
        }

        let bodyStr = String(data: lastData ?? Data(), encoding: .utf8) ?? ""
        throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: (lastResponse as? HTTPURLResponse)?.statusCode, body: bodyStr))
    }

    nonisolated fileprivate static func lookbookStudioPrompt(for variant: LookbookStudioShot, itemName: String) -> String {
        let core = """
        TASK: Generate a brand new photorealistic professional studio product photograph of the garment shown in the input reference images. The output MUST be an image, not text.

        STYLE: Zara / Net-a-Porter / SSENSE catalog product photography. Pure solid white #FFFFFF seamless background. Soft studio softbox lighting from front-top. One subtle contact shadow under the item (10–15% opacity, soft edges).

        FIDELITY (CRITICAL):
        - All input reference images show the SAME physical garment from different angles.
        - Preserve EXACTLY the colors, fabric texture, print, graphic, stitching, label, and material.
        - Do NOT recolor. Do NOT add logos or text not visible in the references.
        - Reconstruct any hidden detail realistically using the cross-reference photos.

        REMOVE: skin, hands, faces, mannequin bodies, hangers, other garments, original backgrounds, props.

        Item description: \(itemName)
        """
        let angle: String
        switch variant {
        case .frontWhite:
            angle =
                "ANGLE: Front view — garment fully visible, ghost-mannequin or floating lay-flat, square 1:1."
        case .backWhite:
            angle =
                "ANGLE: Back view — fully visible showing back graphic/print when present; square 1:1."
        case .angledThreeQuarter:
            angle =
                "ANGLE: Three-quarter from front-right, slight perspective showing depth; square 1:1."
        case .flatLay:
            angle = "ANGLE: Overhead flat lay on white straight from above; square 1:1."
        case .detailMacro:
            angle =
                "ANGLE: Macro fill-frame on dominant print/logo/texture showing fabric fidelity; square 1:1."
        }
        return core + "\n\n" + angle + "\n\nGenerate the image now."
    }

    nonisolated fileprivate static func lookbookLifestylePrompt(
        for variant: LookbookLifestyleShot,
        itemName: String,
        hasFace: Bool
    ) -> String {
        let identityClause: String =
            hasFace
            ? """
            CRITICAL — IDENTITY:
            The FIRST input image is a reference portrait of the model's face. The output MUST match the SAME facial likeness (features, skin tone, hair colour/style and eye colour). The following inputs are garment references only.

            """
            : """
            The garment reference images describe ONE item from multiple viewpoints—compose the outfit exactly from them.

            """
        let core =
            identityClause + """
            TASK: Generate a brand new photorealistic lifestyle fashion photograph — model wearing the garment. Output MUST be an image, not text.

            FIDELITY (CRITICAL):
            The worn garment MUST match references: identical colour, print, silhouette, trims and hardware shown in refs.
            No logos/text not visible in refs. Natural proportions.

            REMOVE: watermarks, captions, extra people.

            Item description: \(itemName)

            """

        let scene: String
        switch variant {
        case .urbanNeonFront:
            scene =
                "SCENE: Editorial nightlife — model near vintage car outside a motel vibe with saturated red neon; front-on showing the garment; cinematic neon rim-light; portrait 2:3."
        case .urbanNeonBack:
            scene =
                "SCENE: Same neon motel ambience at night — model angled away, back emphasised presenting rear graphics; cinematic; portrait 2:3."
        case .industrialDay:
            scene =
                "SCENE: Editorial day — masculine presenting model inside industrial garage/mechanic bays, soft skylight leak; frontal relaxed stance showing upper outfit; portrait 2:3."
        case .interiorMirror:
            scene =
                "SCENE: Crisp mirrored elevator corridor — symmetrical reflections reinforcing garment folds; frontal or three-quarter; portrait 2:3."
        case .portraitClose:
            scene =
                "SCENE: Tight runway-style portrait torso-up emphasising neckline/shoulder detail; softened background blur; square 1:1."
        }
        return core + scene + "\n\nGenerate the image now."
    }

    /// Varias imágenes de prendas + texto (y opcionalmente una primera imagen de rostro como referencia de identidad). Devuelve ruta relativa en `avatars/`.
    func generateLookAvatar(
        garmentRelativePaths: [String],
        itemDescriptionLines: [String],
        gender: AvatarGender,
        faceReferenceRelativePath: String? = nil,
    )
        async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiError("Falta GeminiAPIKey.")
        }
        let cappedPaths = Array(garmentRelativePaths.prefix(8))
        let cappedLines = Array(itemDescriptionLines.prefix(8))
        guard cappedPaths.count >= 1 else {
            throw GeminiError.apiError("No hay imágenes válidas para el avatar.")
        }

        var partsPayload: [[String: Any]] = []
        partsPayload.reserveCapacity(cappedPaths.count + 2)

        var hasFace = false
        if let faceRel = faceReferenceRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !faceRel.isEmpty,
           let faceImg = ImageStore.load(faceRel),
           let faceJpeg = faceImg.jpegData(compressionQuality: 0.92)
        {
            partsPayload.append([
                "inline_data": ["mime_type": "image/jpeg", "data": faceJpeg.base64EncodedString()],
            ])
            hasFace = true
        }

        for rel in cappedPaths {
            guard let image = ImageStore.load(rel),
                  let jpeg = image.jpegData(compressionQuality: 0.9)
            else { continue }
            let base64 = jpeg.base64EncodedString()
            partsPayload.append(["inline_data": ["mime_type": "image/jpeg", "data": base64]])
        }
        guard partsPayload.count > (hasFace ? 1 : 0) else {
            throw GeminiError.encodingFailed
        }

        let genderText =
            gender == .male
                ? "young adult male model"
                : "young adult female model"

        let dressingList = cappedLines.isEmpty
            ? "(use every garment shown in the images in order)."
            : cappedLines.joined(separator: "\n")

        let faceClause = hasFace
            ? """
            CRITICAL — IDENTITY:
            The FIRST input image is a reference photo of the model's face. The generated avatar MUST closely match the SAME person's facial features, face shape, skin tone, hair color and hair style, eye color, and overall likeness as in that reference. Treat this as a styled studio portrait of THE SAME PERSON, now dressed in the garments from the following images.
            Keep natural ethnicity, approximate age, hair texture, and characteristic features. Use a neutral pleasant catalog expression.
            All images AFTER the first are clothing items only (no face to copy from those).

            """
            : ""

        let promptText = """
        TASK: Generate a brand new photorealistic full-body studio fashion photograph of a \(genderText) wearing ALL of the clothing items shown in the input images. The output MUST be an image, not text.

        \(faceClause)DRESS THE MODEL EXACTLY WITH THESE ITEMS:
        \(dressingList)

        Compose the outfit on a single person. If multiple items belong to the same category (e.g. two shirts), use only the first. Coordinate the items as a complete styled outfit.

        STYLE REQUIREMENTS (mandatory):
        - Background: ONLY flat pure #FFFFFF seamless studio cyclorama covering the FULL frame edges. Absolutely no vignette, no gradient panels, no light grey margins, no paper texture.
        - NO SHADOWS ON THE WHITE SET: forbid floor contact shadow/disc, soft grey oval beneath feet, AO halos behind legs, mirrored reflection band, pedestal shadow blob, or directional cast shadow touching the backdrop. The garments and body may naturally shade themselves internally, but the backdrop must remain a clean uninterrupted white (#FFFFFF outside the clothed silhouette should read as identical white everywhere).
        - Lighting: ultra-soft even frontal-top fashion softbox ONLY to shape the figure; neutral white balance — without painting cast shadows onto the infinity wall.
        - Composition: VERTICAL TikTok/Reels/full-body SHORT-FORM cover — FULL-BODY HEAD-TO-TOE in frame, centered runway stance, fashionable catalog pose facing camera enough to recognize the outfit symmetrically at a neutral eye-level (~50 mm lens feel).
        - Aspect & crop intent — CRITICAL OUTPUT SHAPE:
          The final IMAGE MUST be VERTICAL portrait 9:16 (width:height = 9:16). Treat this as TikTok/Reels/mobile cover proportions (conceptual canonical 1080×1920). Do NOT produce 2:3, 4:5, 3:4, or square 1:1; never letterbox portrait artboard into widescreen.
        - Negative space: purposeful tall negative white margin above helmet/hair clearance and below soles while keeping silhouette fully enclosed with comfortable safe margins (do NOT tightly crop ankles or hairstyle).
        - Model: \(genderText), pleasantly neutral catalog gaze, realistically attractive 22–29 y/o (no uncanny/over-beautifying filter skin).

        FIDELITY (CRITICAL):
        - Each garment shown in the input images must appear on the model as faithfully as possible: same color, same pattern, same cut, same material. Do not invent new garments.
        - If a garment in input has a print, ruffle, sequin or hardware, preserve it.
        - Do NOT add brand logos that were not visible in the inputs.

        REMOVE / DO NOT INCLUDE:
        - Text overlays, watermarks, captions.
        - Other people, animals, busy backgrounds.
        - The original photo backgrounds from the input images.

        Now generate the avatar image.
        """

        let temperature = hasFace ? 0.35 : 0.6
        /// Partes de imagen antes de añadir el texto (prendas + opcional rostro).
        let garmentImageSlots = partsPayload.count - (hasFace ? 1 : 0)

        partsPayload.append(["text": promptText])

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": partsPayload,
            ]],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"],
                "temperature": temperature,
            ],
        ]

        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.parsingFailed }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print(
            "🟡 [Avatar] Generando \(gender.rawValue) con \(garmentImageSlots) prenda(s)\(hasFace ? " + rostro" : "") (gemini-2.5-flash-image)…")

        let (data, response) = try await imageGenerationData(for: req, consoleTag: "Avatar")
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            print(
                "🔴 [Avatar] HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(bodyStr.prefix(500))")
            let lower = bodyStr.lowercased()
            if lower.contains("prohibited_content") || (lower.contains("safety") && lower.contains("block")) {
                throw GeminiError.apiError(
                    "Gemini rechazó la imagen por políticas de seguridad. Prueba otra foto de rostro o desactiva «Usar mi rostro».")
            }
            throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: (response as? HTTPURLResponse)?.statusCode, body: bodyStr))
        }

        Self.logGeminiMultimodalResponseParts(data, tag: "[Avatar]")

        guard let b64data = Self.extractFirstInlineImageBase64(from: data),
              let imgData = Self.decodeGeminiImageBase64(b64data)
        else {
            print("🔴 [Avatar] Gemini no devolvió imagen — revisa [Avatar] y responseModalities [TEXT,IMAGE].")
            throw GeminiError.apiError(
                "Gemini no devolvió imagen de avatar (filtro Xcode: `[Avatar]`).")
        }

        guard let uiDecoded = UIImage(data: imgData) else {
            let fnameFallback = "\(UUID().uuidString.lowercased()).jpg"
            let relSavedFallback = try ImageStore.save(imgData, inFolder: "avatars", filename: fnameFallback)
            print("✅ [Avatar] Guardado sin recomposición TikTok (decode fallido): \(relSavedFallback)")
            return relSavedFallback
        }

        let composedUIImage = await MainActor.run {
            ClosetPhotoExports.tikTokWhitePortraitComposite(image: uiDecoded)
        }
        guard let outData = composedUIImage.jpegData(compressionQuality: 0.92) else {
            throw GeminiError.apiError("No se pudo recomponer el avatar 9:16.")
        }

        let fname = "\(UUID().uuidString.lowercased()).jpg"
        let relSaved = try ImageStore.save(outData, inFolder: "avatars", filename: fname)
        print("✅ [Avatar] Guardado TikTok 9:16 sobre blanco: \(relSaved)")
        return relSaved
    }

    /// Prettify por ángulo para vista 360°: conserva orientación del zapato, solo limpia fondo/luz.
    func prettifyShoeAngle(cropRelativePath: String, angle: ShoeAngle, itemName: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiError("Falta GeminiAPIKey.")
        }
        guard let image = ImageStore.load(cropRelativePath),
              let jpeg = image.jpegData(compressionQuality: 0.95)
        else { throw GeminiError.encodingFailed }

        let anglePrompt = Self.englishPromptForShoeAngle(angle)
        let prompt = """
        TASK: Generate a brand new photorealistic studio product photograph of the shoe shown in the input image, viewed \(anglePrompt). This is for an interactive 360° viewer, so the SHOE ORIENTATION must be preserved exactly as in the input — do NOT rotate, flip, mirror, or change the viewing angle. Only clean up background and lighting.

        REQUIREMENTS:
        - Background: pure solid white #FFFFFF, seamless. Remove any background from the original photo.
        - Lighting: soft even studio softbox; show laces, logos, stitching, sole, labels clearly.
        - Contact shadow: ONE subtle natural shadow beneath the shoe (~10–15% opacity), soft edges.
        - Composition: shoe centered with ~10% padding, fully visible, same pose/orientation as input.
        - Format: square 1:1, high resolution.
        - Style reference: StockX, Stadium Goods, GOAT catalog photography.

        ROTATION-SERIES ALIGNMENT (critical for interactive 360°):
        - Keep the SAME apparent scale across the whole set — the shoe should fill about the SAME fraction of frame width/height every time (same camera distance/zoom metaphor).
        - Same vertical grounding: imaginary floor line and vertical center stable; avoid shifting the shoe up/down between renders.
        - Same horizontal framing: symmetric side margins (~10%) relative to the shoe silhouette across angles.

        FIDELITY (CRITICAL):
        - Preserve the exact viewing angle and perspective from the input.
        - Preserve colors, materials, printed text, hardware, zip-ties, tags 100%.

        REMOVE:
        - Hands, feet, legs, scenery, furniture, other shoes.

        Item: \(itemName)
        Angle label: \(angle.displayName)

        Generate the image now.
        """

        let base64 = jpeg.base64EncodedString()
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt],
                ],
            ]],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"],
                "temperature": 0.3,
            ],
        ]

        guard let url = URL(
            string:
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key=\(apiKey)"
        ) else { throw GeminiError.parsingFailed }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🟡 [Shoe360] Llamando Gemini (\(cropRelativePath)) ángulo \(angle.displayName) — \(itemName)…")

        let backoffSeconds: [UInt64] = [5, 15, 45]
        var lastData: Data?
        var lastResponse: URLResponse?

        attempts: for attempt in 0 ..< backoffSeconds.count + 1 {
            let pair = try await imageGenerationData(for: req, consoleTag: "Shoe360")
            lastData = pair.0
            lastResponse = pair.1
            let httpOpt = pair.1 as? HTTPURLResponse

            if let http = httpOpt, (200 ..< 300).contains(http.statusCode) {
                Self.logGeminiMultimodalResponseParts(pair.0, tag: "[Shoe360]")
                guard let b64data = Self.extractFirstInlineImageBase64(from: pair.0),
                      let imgData = Self.decodeGeminiImageBase64(b64data)
                else {
                    print("🔴 [Shoe360] Sin imagen en la respuesta (modelo / modalities).")
                    throw GeminiError.apiError(
                        "Gemini no devolvió imagen para vista 360° (consola `[Shoe360]`).")
                }
                let fname = "\(UUID().uuidString.lowercased()).jpg"
                let rel = try ImageStore.save(imgData, inFolder: "shoe360", filename: fname)
                print("✅ [Shoe360] Imagen guardada: \(rel)")
                return rel
            }

            let bodyStr = String(data: pair.0, encoding: .utf8) ?? ""
            let code = httpOpt?.statusCode ?? 0
            print("🔴 [Shoe360] HTTP \(code): \(bodyStr.prefix(500))")

            if attempt < backoffSeconds.count, code == 429 {
                let sec = backoffSeconds[attempt]
                print("🟡 [Shoe360] Reintentando tras \(sec)s por 429…")
                try await Task.sleep(nanoseconds: sec * 1_000_000_000)
                continue attempts
            }

            throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: code, body: bodyStr))
        }

        let bodyStr = String(data: lastData ?? Data(), encoding: .utf8) ?? ""
        throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: (lastResponse as? HTTPURLResponse)?.statusCode, body: bodyStr))
    }

    /// Spin 360° desde vídeo (~36 frames): mismo encuadre que el fotograma, fondo blanco catálogo (StockX / Zara sneaker).
    func prettifyShoeSpin360Frame(
        cropRelativePath: String,
        itemName: String,
        frameOneBasedIndex: Int,
        totalFrames: Int
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiError("Falta GeminiAPIKey.")
        }
        guard let image = ImageStore.load(cropRelativePath),
              let jpeg = image.jpegData(compressionQuality: 0.95)
        else { throw GeminiError.encodingFailed }

        let prompt = """
        TASK: Generate a brand new photorealistic studio product photograph of the shoe in the input image. This frame is part of a turntable / 360° spin sequence (frame \(frameOneBasedIndex) of \(totalFrames)). The camera viewpoint and the shoe’s rotation relative to the camera MUST match the input exactly — do NOT rotate, flip, mirror, or “correct” the angle. Only replace the environment with a professional studio look.

        BACKGROUND & LIGHTING (match premium sneaker e‑commerce):
        - Background: pure solid white #FFFFFF, seamless infinity look. No floor texture, no gradient, no props.
        - Lighting: bright, soft, even softbox from front and slightly above; no harsh clipped highlights.
        - Contact shadow: ONE subtle, soft shadow under the sole only (~10–15% opacity, feathered) to ground the shoe — no dark patches on the white field.

        FRAMING (critical for a smooth spin when scrubbed):
        - Keep the shoe filling roughly the SAME proportion of the frame as the input (same perceived scale).
        - Center the shoe; ~10% padding on all sides; entire shoe visible.
        - Square 1:1, high resolution, tack sharp.

        FIDELITY (CRITICAL):
        - Preserve exact colors, materials, swooshes, printed text (“AIR”), zip-ties, tags, stitching, soles, tread.
        - Do NOT invent logos or lettering not visible in the input.

        REMOVE:
        - Hands, feet, legs, floor from the original, furniture, clutter, second shoes.

        Item: \(itemName)

        Generate the image now.
        """

        let base64 = jpeg.base64EncodedString()
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt],
                ],
            ]],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"],
                "temperature": 0.28,
            ],
        ]

        guard let url = URL(
            string:
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key=\(apiKey)"
        ) else { throw GeminiError.parsingFailed }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print(
            "🟡 [360ProStudio] Frame \(frameOneBasedIndex)/\(totalFrames) — \(cropRelativePath) (\(itemName))…")

        let backoffSeconds: [UInt64] = [5, 15, 45]
        var lastData: Data?
        var lastResponse: URLResponse?

        attempts: for attempt in 0 ..< backoffSeconds.count + 1 {
            let pair = try await imageGenerationData(for: req, consoleTag: "360ProStudio")
            lastData = pair.0
            lastResponse = pair.1
            let httpOpt = pair.1 as? HTTPURLResponse

            if let http = httpOpt, (200 ..< 300).contains(http.statusCode) {
                Self.logGeminiMultimodalResponseParts(pair.0, tag: "[360ProStudio]")
                guard let b64data = Self.extractFirstInlineImageBase64(from: pair.0),
                      let imgData = Self.decodeGeminiImageBase64(b64data)
                else {
                    print("🔴 [360ProStudio] Sin imagen en la respuesta.")
                    throw GeminiError.apiError(
                        "Gemini no devolvió imagen para 360° Pro (consola `[360ProStudio]`).")
                }
                let fname = "\(UUID().uuidString.lowercased()).jpg"
                let rel = try ImageStore.save(imgData, inFolder: "shoe360_pro_studio", filename: fname)
                print("✅ [360ProStudio] Guardado: \(rel)")
                return rel
            }

            let bodyStr = String(data: pair.0, encoding: .utf8) ?? ""
            let code = httpOpt?.statusCode ?? 0
            print("🔴 [360ProStudio] HTTP \(code): \(bodyStr.prefix(500))")

            if attempt < backoffSeconds.count, code == 429 {
                let sec = backoffSeconds[attempt]
                print("🟡 [360ProStudio] Reintentando tras \(sec)s por 429…")
                try await Task.sleep(nanoseconds: sec * 1_000_000_000)
                continue attempts
            }

            throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: code, body: bodyStr))
        }

        let bodyStr = String(data: lastData ?? Data(), encoding: .utf8) ?? ""
        throw GeminiError.apiError(Self.humanGeminiHTTPError(statusCode: (lastResponse as? HTTPURLResponse)?.statusCode, body: bodyStr))
    }

    private nonisolated static func englishPromptForShoeAngle(_ angle: ShoeAngle) -> String {
        switch angle {
        case .front:
            return "from a frontal angle (toe pointing toward the camera)"
        case .right:
            return "from the right side—outer lateral"
        case .back:
            return "from the rear (heel facing the camera)"
        case .left:
            return "from the left side—inner lateral"
        }
    }

    enum GeminiError: Error, LocalizedError {
        case encodingFailed
        case parsingFailed
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "No se pudo codificar la imagen."
            case .parsingFailed: return "Respuesta de IA inválida."
            case .apiError(let msg): return msg
            }
        }
    }

    /// Resume el JSON típico de error de Google (evita pegar blobs enormes en toasts/UI).
    private nonisolated static func humanGeminiHTTPError(statusCode: Int?, body: String) -> String {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = b.lowercased()
        if statusCode == 429
            || lowered.contains("\"code\": 429")
            || lowered.contains("resource_exhausted")
            || (lowered.contains("quota") && lowered.contains("exceeded")) {
            // Métricas de cuota pueden decir `gemini-2.5-flash-preview-image` aunque la URL sea `gemini-2.5-flash-image`.
            if lowered.contains("limit: 0") {
                return "Gemini: este proyecto tiene cupo 0 para imágenes (free tier / sin facturación). Activa facturación y cuota para la API Generative Language o usa otro proyecto. Guía: ai.google.dev/gemini-api/docs/rate-limits"
            }
            return "Gemini: cuota temporalmente agotada o demasiadas peticiones; revisa tu plan en Google AI Studio y reintenta en unos minutos."
        }
        if lowered.contains("api_key_invalid") || lowered.contains("api key not valid") {
            return "Gemini rechazó la clave API: debe ser solo la cadena AIza… que copias de Google AI Studio (no una ruta de archivo ni otros textos después del igual)."
        }
        if let d = b.data(using: .utf8),
           let top = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let err = top["error"] as? [String: Any] {
            let msg = ((err["message"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !msg.isEmpty {
                let codeSuffix = statusCode.map { " (HTTP \($0))" } ?? ""
                return "Gemini\(codeSuffix): \(msg)"
            }
        }
        return "Gemini HTTP \(statusCode ?? 0): \(String(b.prefix(220)))"
    }

    /// `box_2d` viene como lista de números (Int/Double/NSNumber mezclados).
    private nonisolated static func parseGeminiBox2D(_ raw: Any?) -> [Double]? {
        guard let arr = raw as? [Any], arr.count == 4 else { return nil }
        var out: [Double] = []
        for el in arr {
            if let d = el as? Double {
                out.append(d)
            } else if let i = el as? Int {
                out.append(Double(i))
            } else if let n = el as? NSNumber {
                out.append(n.doubleValue)
            } else {
                return nil
            }
        }
        return out
    }

    // MARK: - Parse helpers (respuesta Gemini flexible)

    private nonisolated static func extractAllTextFromGeminiData(_ data: Data) throws -> String {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let pf = obj?["promptFeedback"] as? [String: Any],
           let reason = pf["blockReason"] as? String, !reason.isEmpty {
            throw GeminiError.apiError("La petición fue bloqueada (\(reason)). Prueba con otra imagen.")
        }
        let candidates = obj?["candidates"] as? [[String: Any]] ?? []
        guard let first = candidates.first else {
            let errSummary = Self.topLevelGeminiSummary(obj)
            throw GeminiError.apiError("Gemini no devolvió candidatos.\(errSummary)")
        }
        if let fr = first["finishReason"] as? String {
            let upper = fr.uppercased()
            if upper.contains("SAFETY") {
                throw GeminiError.apiError("Respuesta bloqueada (seguridad). Prueba con otra foto.")
            }
        }
        let content = first["content"] as? [String: Any] ?? [:]
        let parts = content["parts"] as? [[String: Any]] ?? []
        var texts: [String] = []
        for p in parts {
            if let t = p["text"] as? String { texts.append(t) }
        }
        let joined = texts.joined()
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let finish = (first["finishReason"] as? String) ?? "(desconocido)"
            throw GeminiError.apiError("Gemini no devolvió JSON de texto (finish: \(finish)).")
        }
        return Self.stripCodeFences(trimmed)
    }

    /// Fragmento opcional útil cuando `error` aparece sin `candidates`.
    private nonisolated static func topLevelGeminiSummary(_ obj: [String: Any]?) -> String {
        guard let obj,
              let topErr = obj["error"] as? [String: Any] else { return "" }
        let raw = topErr["message"] ?? topErr["status"]
        let msg = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return "" }
        return " \(msg.prefix(280))"
    }

    private nonisolated static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func logGeminiMultimodalResponseParts(_ data: Data, tag: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]], !candidates.isEmpty
        else {
            print("🔴 \(tag) Respuesta sin candidates válidos")
            return
        }
        for (ci, cand) in candidates.enumerated() {
            guard let content = cand["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]]
            else {
                print("🔴 \(tag) candidate[\(ci)] sin content/parts")
                continue
            }
            for (i, p) in parts.enumerated() {
                if let t = p["text"] as? String, !t.isEmpty {
                    print("🟡 \(tag) c[\(ci)] part[\(i)] TEXT: \(t.prefix(200))…")
                }
                if let inline = (p["inlineData"] as? [String: Any]) ?? (p["inline_data"] as? [String: Any]),
                   let d = inline["data"] as? String {
                    let mime =
                        ((inline["mimeType"] as? String) ?? (inline["mime_type"] as? String)) ?? "?"
                    print("🟢 \(tag) c[\(ci)] part[\(i)] IMAGE \(mime) (\(d.count) chars b64)")
                }
            }
        }
    }

    private nonisolated static func decodeGeminiImageBase64(_ raw: String) -> Data? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Data(base64Encoded: trimmed) { return d }
        if let d = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]) { return d }
        print("🔴 [Prettify] Base64 de imagen no decodifica (chars: \(trimmed.count))")
        return nil
    }

    private nonisolated static func extractFirstInlineImageBase64(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]]
        else { return nil }

        for cand in candidates {
            guard let content = cand["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]]
            else { continue }
            for p in parts {
                if let inline = p["inlineData"] as? [String: Any],
                   let d = inline["data"] as? String, !d.isEmpty { return d }
                if let inline = p["inline_data"] as? [String: Any],
                   let d = inline["data"] as? String, !d.isEmpty { return d }
            }
        }
        return nil
    }
}

extension GeminiService {
    /// `true` cuando `GeminiAPIKey` está en el bundle (detección + Prettify con modelo imagen Gemini).
    nonisolated static var apiKeyConfigured: Bool {
        let key = (Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }
}

// MARK: - UIImage (bitmap estable + recorte normalizado)

extension UIImage {
    /// Alinea orientación y escala para que `cgImage` y coords normalizadas coincidan con la foto mostrada.
    func closetBitmapForVision() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func closetCropped(normalized rect: NormalizedRect) -> UIImage? {
        let img = closetBitmapForVision()
        guard let cg = img.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        var cropRect = CGRect(
            x: rect.x * w,
            y: rect.y * h,
            width: rect.width * w,
            height: rect.height * h
        )
        cropRect = cropRect.integral
        cropRect.origin.x = min(max(cropRect.origin.x, 0), w - 1)
        cropRect.origin.y = min(max(cropRect.origin.y, 0), h - 1)
        cropRect.size.width = min(cropRect.size.width, w - cropRect.origin.x)
        cropRect.size.height = min(cropRect.size.height, h - cropRect.origin.y)
        guard cropRect.width >= 2, cropRect.height >= 2,
              let cut = cg.cropping(to: cropRect)
        else { return nil }

        return UIImage(cgImage: cut, scale: 1.0, orientation: .up)
    }
}
