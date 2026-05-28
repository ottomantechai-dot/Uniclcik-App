import AVFoundation
import SwiftUI

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

// MARK: - Search bar (reference: pill + barcode inside)

struct StockBrowseSearchBar: View {
    @Binding var searchText: String
    @Binding var layoutMode: StockLayoutMode
    var onScan: () -> Void
    @FocusState.Binding var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
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

                Button(action: onScan) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.72))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("closet.scanBarcode"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                LiquidGlassSearchPillBackground()
            }

            HStack(spacing: 4) {
                ForEach(StockLayoutMode.allCases) { mode in
                    Button {
                        layoutMode = mode
                    } label: {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(layoutMode == mode ? Color.white : Color.black.opacity(0.55))
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .fill(layoutMode == mode ? Color.black : Color.black.opacity(0.06))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.accessibilityLabel)
                }
            }
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
