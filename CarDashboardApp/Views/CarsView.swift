import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

struct CarsView: View {
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject private var auth: AuthViewModel

    @State private var showSortSheet = false
    @State private var showFilterSheet = false
    @State private var editingCar: Car?
    @FocusState private var browseSearchFieldFocused: Bool

    private var displayedCars: [Car] {
        carsVM.displayedBrowseCars()
    }

    private var resultCountText: String {
        displayedCars.count.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                stickyBrowseChrome

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        HStack(spacing: 6) {
                            Image(systemName: "shoeprints.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                            Text("\(resultCountText) sneakers")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.65))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        if carsVM.isLoadingVehicles && carsVM.cars.isEmpty {
                            ProgressView()
                                .tint(Color(red: 0.20, green: 0.45, blue: 0.85))
                                .padding(.vertical, 32)
                        }

                        if let err = carsVM.vehiclesError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }

                        if !carsVM.isLoadingVehicles || !carsVM.cars.isEmpty {
                            if displayedCars.isEmpty {
                                ContentUnavailableView(
                                    "Sin resultados",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text("Prueba a limpiar filtros o cambiar la búsqueda.")
                                )
                                .foregroundStyle(Color.black.opacity(0.75))
                                .symbolRenderingMode(.hierarchical)
                                .tint(Color(red: 0.20, green: 0.45, blue: 0.85))
                                .padding(.vertical, 24)
                                .padding(.horizontal, 16)
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(Array(displayedCars.enumerated()), id: \.element.id) { idx, car in
                                        SneakerListingCardLight(
                                            mock: SneakerMock.mock(for: idx)
                                        ) {
                                            carsVM.selectCar(car)
                                            editingCar = car
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity)
                            }

                            if carsVM.isLoadingMoreVehicles {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(Color(red: 0.20, green: 0.45, blue: 0.85))
                                    Text("Cargando más sneakers…")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.55))
                                }
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(.bottom, 28)
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
                .refreshable {
                    await carsVM.loadVehicles(companyId: auth.companyId)
                }
            }
            .frame(maxWidth: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    LiquidGlassKeyboardAccessoryBar {
                        browseSearchFieldFocused = false
                    }
                }
            }
            .sheet(isPresented: $showSortSheet) {
                CarsSortSheet(sort: $carsVM.browseSort)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFilterSheet) {
                CarsFilterSheet(
                    filters: $carsVM.browseFilters,
                    sourceCars: carsVM.cars,
                    resultCount: carsVM.displayedBrowseCars().count,
                    onClear: {}
                )
            }
            .sheet(item: $editingCar) { car in
                EditVehicleDictationSheet(car: car) {
                    Task { await carsVM.loadVehicles(companyId: auth.companyId) }
                }
            }
            .task {
                if carsVM.cars.isEmpty && !carsVM.isLoadingVehicles {
                    await carsVM.loadVehicles(companyId: auth.companyId)
                }
            }
            .onChange(of: auth.companyId) { oldCompanyId, newCompanyId in
                // Cuando se resuelve el company_id del usuario, recargar vehículos filtrados por empresa.
                // Evita recarga duplicada si el valor no cambió realmente.
                guard oldCompanyId != newCompanyId else { return }
                Task {
                    await carsVM.loadVehicles(companyId: newCompanyId)
                }
            }
        }
    }

    private var stickyBrowseChrome: some View {
        CarsBrowseHeaderBar(
            searchText: $carsVM.browseSearchText,
            hasActiveFilters: carsVM.browseFilters.hasActiveFilters,
            searchFieldFocused: $browseSearchFieldFocused,
            onSort: { showSortSheet = true },
            onFilter: { showFilterSheet = true }
        )
        .appChromeHeaderOuterPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.dashboardLightSurface, true)
    }
}

// MARK: - Edición por dictado (tap en tarjeta de coche)

struct EditVehicleDictationSheet: View {
    let car: Car
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var transcriber = LiveSpeechTranscriber()
    @State private var isDictating = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    @State private var brand = ""
    @State private var model = ""
    @State private var yearText = ""
    @State private var plate = ""
    @State private var priceText = ""
    @State private var mileageText = ""
    @State private var powerCvText = ""
    @State private var fuel = ""
    @State private var transmission = ""
    @State private var color = ""
    @State private var dgtLabel = ""
    @State private var listingDescription = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edita los datos del vehículo")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text("Puedes modificar campos manualmente o usar el micrófono de arriba.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if isDictating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Escuchando… toca el micrófono para terminar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }

                    if !transcriber.partialText.isEmpty {
                        Text(transcriber.partialText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(10)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    field("Marca", text: $brand)
                    field("Modelo", text: $model)
                    field("Año", text: $yearText, keyboard: .numberPad)
                    field("Matrícula", text: $plate)
                    field("Precio", text: $priceText, keyboard: .decimalPad)
                    field("Kilómetros", text: $mileageText, keyboard: .numberPad)
                    field("Potencia CV", text: $powerCvText, keyboard: .numberPad)
                    field("Combustible", text: $fuel)
                    field("Transmisión", text: $transmission)
                    field("Color", text: $color)
                    field("Etiqueta DGT", text: $dgtLabel)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Descripción")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.62))
                        TextEditor(text: $listingDescription)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }

                    if let infoMessage, !infoMessage.isEmpty {
                        Text(infoMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green.opacity(0.9))
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red.opacity(0.95))
                    }

                    Button {
                        Task { await saveChanges() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Guardando..." : "Guardar cambios")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.6 : 1)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Editar coche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await toggleDictation() }
                    } label: {
                        Image(systemName: isDictating ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isDictating ? Color.red.opacity(0.95) : Color.white.opacity(0.95))
                    }
                    .accessibilityLabel(isDictating ? "Detener dictado" : "Iniciar dictado")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { stopDictationIfNeeded() }
        .task {
            loadFromCar()
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
            TextField("", text: text)
                .keyboardType(keyboard)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @MainActor
    private func toggleDictation() async {
        if isDictating {
            stopDictationAndApply()
        } else {
            await startDictation()
        }
    }

    @MainActor
    private func startDictation() async {
        errorMessage = nil
        infoMessage = nil
        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            errorMessage = "Activa micrófono en Ajustes para dictar."
            return
        }
        let speechGranted = await transcriber.requestSpeechAuthorization()
        guard speechGranted else {
            errorMessage = "Activa reconocimiento de voz en Ajustes."
            return
        }
        do {
            isDictating = true
            try transcriber.startLiveTranscription()
        } catch {
            isDictating = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func stopDictationAndApply() {
        let spoken = transcriber.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriber.stopLiveTranscription()
        isDictating = false
        guard !spoken.isEmpty else { return }
        applyDictatedText(spoken)
    }

    private func stopDictationIfNeeded() {
        guard isDictating else { return }
        transcriber.stopLiveTranscription()
        isDictating = false
    }

    private func applyDictatedText(_ spoken: String) {
        let parsed = VehicleDictationParser.parse(spoken)
        if let v = parsed.brand { brand = v }
        if let v = parsed.model { model = v }
        if let v = parsed.year { yearText = String(v) }
        if let v = parsed.plate { plate = v }
        if let v = parsed.price { priceText = String(format: "%.0f", v) }
        if let v = parsed.mileage { mileageText = String(v) }
        if let v = parsed.powerCv { powerCvText = String(v) }
        if let v = parsed.fuelType { fuel = v }
        if let v = parsed.transmission { transmission = v }
        if let v = parsed.color { color = v }
        if let v = parsed.dgtLabel { dgtLabel = v }
        if let v = parsed.description { listingDescription = v }
        infoMessage = "Dictado aplicado. Revisa los campos antes de guardar."
    }

    @MainActor
    private func saveChanges() async {
        errorMessage = nil
        infoMessage = nil
        isSaving = true
        defer { isSaving = false }

        guard let year = Int(yearText.filter(\.isNumber)), (1950 ... 2035).contains(year) else {
            errorMessage = "Año no válido."
            return
        }
        let price = Self.parseOptionalDouble(priceText)
        let mileage = Self.parseOptionalInt(mileageText)
        let power = Self.parseOptionalInt(powerCvText)

        let payload = VehicleAppListingPayload(
            brand: brand,
            model: model,
            year: year,
            licensePlate: Self.trimmed(plate),
            salePriceUSD: price,
            purchasePriceUSD: nil,
            marketPriceUSD: nil,
            financedPriceUSD: nil,
            mileageKm: mileage,
            powerCv: power,
            fuelType: Self.trimmed(fuel),
            transmission: Self.trimmed(transmission),
            vin: nil,
            exteriorColor: Self.trimmed(color),
            listingDescription: Self.trimmed(listingDescription),
            dgtLabel: Self.trimmed(dgtLabel),
            listingExtra: nil
        )

        do {
            _ = try await VehiclesService.updateVehicleFromApp(vehicleId: car.id, payload: payload)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFromCar() {
        brand = car.brandName ?? ""
        model = car.model
        yearText = String(car.year)
        plate = car.plate == "—" ? "" : car.plate
        if let p = car.listPriceUSD {
            priceText = String(format: "%.0f", p)
        }
        if let km = car.mileageKm {
            mileageText = String(km)
        }
        if let p = car.powerCv {
            powerCvText = String(p)
        }
        fuel = car.fuelType ?? ""
        transmission = car.transmission ?? ""
        color = car.exteriorColorLabel ?? ""
        dgtLabel = car.dgtLabel ?? ""
    }

    private static func trimmed(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func parseOptionalDouble(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let normalized = t
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
        return Double(normalized)
    }

    private static func parseOptionalInt(_ raw: String) -> Int? {
        let digits = raw.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }
}

private struct VehicleDictationFields {
    var brand: String?
    var model: String?
    var year: Int?
    var plate: String?
    var price: Double?
    var mileage: Int?
    var powerCv: Int?
    var fuelType: String?
    var transmission: String?
    var color: String?
    var dgtLabel: String?
    var description: String?
}

private enum VehicleDictationParser {
    private static let stopWords = [
        "modelo", "año", "ano", "matricula", "matrícula", "precio", "kilometros", "kilómetros",
        "combustible", "transmision", "transmisión", "color", "descripcion", "descripción", "potencia", "cv", "dgt",
    ]

    static func parse(_ text: String) -> VehicleDictationFields {
        var out = VehicleDictationFields()
        out.brand = extract(after: "marca", in: text)
        out.model = extract(after: "modelo", in: text)
        if let y = extract(after: "año", in: text) ?? extract(after: "ano", in: text) {
            out.year = Int(y.filter(\.isNumber))
        }
        if let m = extract(after: "matrícula", in: text) ?? extract(after: "matricula", in: text) {
            out.plate = m.replacingOccurrences(of: " ", with: "").uppercased()
        }
        if let p = extract(after: "precio", in: text) {
            out.price = parseDouble(p)
        }
        if let km = extract(after: "kilómetros", in: text) ?? extract(after: "kilometros", in: text) {
            out.mileage = Int(km.filter(\.isNumber))
        }
        if let cv = extract(after: "potencia", in: text) ?? extract(after: "cv", in: text) {
            out.powerCv = Int(cv.filter(\.isNumber))
        }
        out.fuelType = extract(after: "combustible", in: text)
        out.transmission = extract(after: "transmisión", in: text) ?? extract(after: "transmision", in: text)
        out.color = extract(after: "color", in: text)
        out.dgtLabel = extract(after: "dgt", in: text)
        out.description = extract(after: "descripción", in: text) ?? extract(after: "descripcion", in: text)
        return out
    }

    private static func extract(after field: String, in text: String) -> String? {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let key = field.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let range = normalized.range(of: key) else { return nil }
        let start = normalized[range.upperBound...]
        var candidate = start.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix(":") || candidate.hasPrefix("-") {
            candidate.removeFirst()
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if candidate.isEmpty { return nil }
        let endIndex = firstStopWordIndex(in: candidate)
        let value = endIndex.map { String(candidate[..<$0]) } ?? String(candidate)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstStopWordIndex(in text: String) -> String.Index? {
        let lower = text.lowercased()
        var best: String.Index?
        for word in stopWords {
            guard let r = lower.range(of: " \(word)") else { continue }
            if let b = best {
                if r.lowerBound < b { best = r.lowerBound }
            } else {
                best = r.lowerBound
            }
        }
        return best
    }

    private static func parseDouble(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
        return Double(normalized)
    }
}

// MARK: - Sneaker listing card light + mock data

struct SneakerMock {
    let brand: String
    let model: String
    let colorway: String
    let size: String
    let condition: String
    let priceUSD: Int
    let badgeColor: Color
    let badgeText: String?
    /// Tinta de fondo de la imagen — da variedad visual a la lista
    let tint: Color

    static let catalog: [SneakerMock] = [
        SneakerMock(brand: "Jordan",       model: "1 Off-White",    colorway: "UNC",             size: "42",   condition: "DS",   priceUSD: 1_840, badgeColor: Color(red: 0.20, green: 0.70, blue: 0.45), badgeText: "DESTACADO", tint: Color(red: 0.65, green: 0.82, blue: 1.00)),
        SneakerMock(brand: "Yeezy",        model: "350 V2",         colorway: "Zebra",           size: "43",   condition: "DS",   priceUSD:   320, badgeColor: Color(red: 0.95, green: 0.55, blue: 0.20), badgeText: nil,         tint: Color(red: 0.90, green: 0.90, blue: 0.92)),
        SneakerMock(brand: "Nike",         model: "Dunk Low",       colorway: "Panda",           size: "41.5", condition: "VNDS", priceUSD:   180, badgeColor: Color(red: 0.20, green: 0.45, blue: 0.85), badgeText: nil,         tint: Color(red: 0.95, green: 0.95, blue: 0.96)),
        SneakerMock(brand: "Travis Scott", model: "Jordan 1 Low",   colorway: "Mocha",           size: "44",   condition: "DS",   priceUSD: 1_350, badgeColor: Color(red: 0.55, green: 0.30, blue: 0.85), badgeText: "RARO",      tint: Color(red: 0.86, green: 0.74, blue: 0.62)),
        SneakerMock(brand: "Yeezy",        model: "Foam Runner",    colorway: "MX Cream Clay",   size: "42",   condition: "DS",   priceUSD:   140, badgeColor: Color(red: 0.95, green: 0.40, blue: 0.30), badgeText: nil,         tint: Color(red: 0.94, green: 0.86, blue: 0.74)),
        SneakerMock(brand: "New Balance",  model: "550",            colorway: "White Green",     size: "43.5", condition: "DS",   priceUSD:   190, badgeColor: Color(red: 0.20, green: 0.65, blue: 0.50), badgeText: nil,         tint: Color(red: 0.78, green: 0.92, blue: 0.82)),
        SneakerMock(brand: "Adidas",       model: "Samba OG",       colorway: "White Black Gum", size: "42",   condition: "VNDS", priceUSD:   125, badgeColor: Color(red: 0.20, green: 0.45, blue: 0.85), badgeText: nil,         tint: Color(red: 0.92, green: 0.92, blue: 0.94)),
        SneakerMock(brand: "Jordan",       model: "4 Retro",        colorway: "Bred Reimagined", size: "44",   condition: "DS",   priceUSD:   280, badgeColor: Color(red: 0.85, green: 0.20, blue: 0.25), badgeText: nil,         tint: Color(red: 0.98, green: 0.75, blue: 0.75)),
    ]

    static func mock(for index: Int) -> SneakerMock {
        catalog[index % catalog.count]
    }

    var priceText: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "es_ES")
        return f.string(from: NSNumber(value: priceUSD)) ?? "$\(priceUSD)"
    }
}

struct SneakerListingCardLight: View {
    let mock: SneakerMock
    var onTap: () -> Void
    @State private var isFavorite = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                // Imagen sneaker con tint del modelo
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    mock.tint.opacity(0.55),
                                    mock.tint.opacity(0.25),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)

                    // Highlight superior gloss
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: 110, height: 110)

                    Image("AuthSneakerHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(-18))
                        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
                        .shadow(color: mock.tint.opacity(0.50), radius: 14, y: 6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let badge = mock.badgeText {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1.0)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background {
                                    Capsule().fill(mock.badgeColor)
                                }
                        }
                        Text(mock.brand.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(Color.black.opacity(0.55))
                    }

                    Text("\(mock.model) · \(mock.colorway)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(mock.priceText)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.20, green: 0.50, blue: 0.95),
                                    Color(red: 0.14, green: 0.36, blue: 0.85),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.top, 1)

                    HStack(spacing: 6) {
                        sneakerTag(icon: "ruler.fill", text: "Talla \(mock.size)")
                        sneakerTag(icon: "checkmark.seal.fill", text: mock.condition)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                // Botón favorite + chevron
                VStack {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isFavorite.toggle()
                        }
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(
                                isFavorite
                                    ? Color(red: 0.95, green: 0.30, blue: 0.40)
                                    : Color.black.opacity(0.30)
                            )
                            .scaleEffect(isFavorite ? 1.15 : 1.0)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.6)
                    }
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 5)
                    .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func sneakerTag(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.black.opacity(0.62))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color(red: 0.96, green: 0.97, blue: 1.0))
                .overlay {
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                }
        }
    }
}

#Preview {
    NavigationStack {
        CarsView()
            .environmentObject(CarsViewModel())
            .environmentObject(AuthViewModel())
    }
}

