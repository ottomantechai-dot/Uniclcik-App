import SwiftUI
import PhotosUI

/// Pestaña/vista de productos Upsoled. Lee del catálogo compartido
/// `public.upsoled_products` (mismo backend que la web Sneak Peek Miami)
/// y permite crear nuevos productos que aparecen al instante en la web.
struct UpsoledProductsView: View {
    @StateObject private var vm = UpsoledProductsViewModel()
    @State private var showingAdd: Bool = false

    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                content
            }
            .navigationTitle("Marketplace")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.20, green: 0.45, blue: 0.85),
                                        Color(red: 0.14, green: 0.36, blue: 0.75),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .accessibilityLabel("Añadir producto")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddUpsoledProductSheet(viewModel: vm)
            }
            .task { await vm.reload() }
            .refreshable { await vm.reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            searchAndFilterBar
            if vm.isLoading && vm.products.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Spacer()
            } else if let error = vm.errorMessage, vm.products.isEmpty {
                emptyOrErrorState(message: error)
            } else if vm.filtered.isEmpty {
                emptyOrErrorState(message: "Aún no hay productos en este catálogo.")
            } else {
                gridList
            }
        }
    }

    private var searchAndFilterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar nombre, marca o SKU", text: $vm.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                if !vm.searchText.isEmpty {
                    Button { vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.availableCategories, id: \.value) { cat in
                        Button {
                            vm.selectedCategory = cat.value.isEmpty ? nil : cat.value
                            Task { await vm.reload() }
                        } label: {
                            Text(cat.label)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background {
                                    let active = (vm.selectedCategory ?? "") == cat.value
                                    Capsule().fill(
                                        active
                                            ? Color(red: 0.20, green: 0.45, blue: 0.85)
                                            : Color(.systemGray6)
                                    )
                                }
                                .foregroundStyle(
                                    (vm.selectedCategory ?? "") == cat.value
                                        ? Color.white
                                        : Color.primary
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func emptyOrErrorState(message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                showingAdd = true
            } label: {
                Text("Añadir el primero")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.20, green: 0.45, blue: 0.85), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var gridList: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.filtered) { product in
                    UpsoledProductCard(product: product)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
    }
}

/// Card individual usada en la rejilla (Tu stock + Marketplace).
struct UpsoledProductCard: View {
    let product: UpsoledProduct
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil && !selectionMode)
    }

    private var cardContent: some View {
        VStack(spacing: 9) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.white

                    StockCachedRemoteImage(url: product.primaryImageURL)
                        .padding(4)

                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            if let size = product.cardSizeLabel {
                                Text(size)
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.78)))
                            }
                            Spacer(minLength: 4)
                            if let price = product.cardPriceLabel {
                                Text(price)
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.78)))
                            }
                        }
                        .padding(8)
                    }
                    .allowsHitTesting(false)

                    if selectionMode {
                        Color.black.opacity(isSelected ? 0.12 : 0)
                            .animation(.easeInOut(duration: 0.18), value: isSelected)
                        VStack {
                            HStack {
                                Spacer()
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? Color.black : Color.white.opacity(0.95))
                                        .frame(width: 28, height: 28)
                                        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
                                    if !isSelected {
                                        Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.5)
                                            .frame(width: 28, height: 28)
                                    } else {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Color.white)
                                    }
                                }
                                .padding(8)
                            }
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.18), value: isSelected)
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                if product.hasPricingForProfit, !selectionMode {
                    StockProfitCornerBadge(
                        usdLabel: product.cardProfitUSDLabel,
                        pctLabel: product.cardProfitPercentLabel,
                        isLoss: product.isProjectedLoss
                    )
                    .offset(x: 2, y: -10)
                }
            }
            .frame(maxWidth: .infinity)

            let brandLine = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Text(brandLine.isEmpty ? "Unknown Brand" : brandLine.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if let sku = product.cardSKULabel {
                Text(sku)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }

            Text(product.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)
        }
    }
}

/// Hoja modal para crear un producto. Inserta directamente en `upsoled_products`.
struct AddUpsoledProductSheet: View {
    @ObservedObject var viewModel: UpsoledProductsViewModel
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ProductDraft()
    @State private var priceText: String = ""

    // Foto seleccionada desde la galería/cámara (se sube a Storage al guardar).
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImageData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("Información básica") {
                    TextField("Nombre del producto", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    TextField("Marca", text: $draft.brand)
                        .textInputAutocapitalization(.words)
                    TextField("SKU / Style code (opcional)", text: $draft.sku)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                }

                Section("Precio") {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .onChange(of: priceText) { _, new in
                                draft.price = Double(new.replacingOccurrences(of: ",", with: ".")) ?? 0
                            }
                    }
                }

                Section("Categoría") {
                    Picker("Categoría", selection: $draft.category) {
                        Text("Shoes").tag("shoes")
                        Text("Clothing").tag("clothing")
                        Text("Accessories").tag("accessories")
                        Text("Vintage").tag("vintage")
                        Text("New Drops").tag("new-drops")
                    }
                    Picker("Condición", selection: $draft.condition) {
                        Text("Nuevo").tag("new")
                        Text("Usado").tag("used")
                        Text("Vintage").tag("vintage")
                        Text("Rare").tag("rare")
                    }
                }

                Section {
                    TextField("8, 9, 10, 11.5", text: $draft.sizes)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Tallas disponibles")
                } footer: {
                    Text("Separadas por coma. Ej. \"8, 9, 10, 11\".")
                        .font(.caption2)
                }

                Section("Imagen") {
                    PhotosPicker(
                        selection: $pickedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(pickedImageData == nil ? "Elegir foto" : "Cambiar foto")
                        }
                    }
                    .onChange(of: pickedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                pickedImageData = data
                            }
                        }
                    }

                    if let data = pickedImageData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(8)
                        Button(role: .destructive) {
                            pickedItem = nil
                            pickedImageData = nil
                        } label: {
                            Label("Quitar foto", systemImage: "trash")
                        }
                    }

                    TextField("…o pega una URL (https://…)", text: $draft.imageURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                }

                Section("Descripción") {
                    TextEditor(text: $draft.description)
                        .frame(minHeight: 80)
                }

                if let err = viewModel.errorMessage {
                    Section {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red)
                    }
                }
            }
            .navigationTitle("Nuevo producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            // Re-codifica la foto elegida a JPEG antes de subir.
                            let jpeg: Data? = {
                                guard let d = pickedImageData else { return nil }
                                if let ui = UIImage(data: d) {
                                    return ui.jpegData(compressionQuality: 0.85)
                                }
                                return d
                            }()
                            let ok = await viewModel.create(
                                draft,
                                ownerUserID: auth.session?.user.id,
                                imageJPEG: jpeg
                            )
                            if ok { dismiss() }
                        }
                    } label: {
                        if viewModel.isCreating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Guardar").fontWeight(.semibold)
                        }
                    }
                    .disabled(!draft.isValid || viewModel.isCreating)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isCreating)
    }
}
