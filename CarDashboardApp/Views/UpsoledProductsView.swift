import SwiftUI

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

/// Card individual usada en la rejilla.
struct UpsoledProductCard: View {
    let product: UpsoledProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Imagen: cuadrado con aspecto 3:4. La imagen está envuelta en un
            // contenedor con tamaño fijo + clipped para que NUNCA se salga del card.
            imageBlock
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if !product.inStock {
                        Text("AGOTADO")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.6)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }

            if let brand = product.brand, !brand.isEmpty {
                Text(brand.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(product.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            Text("$\(Int(product.price.rounded()))")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var imageBlock: some View {
        GeometryReader { proxy in
            if let url = product.primaryImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color(.systemGray6)
                            ProgressView().controlSize(.small)
                        }
                    case let .success(image):
                        // .fit dentro del frame fijo → la imagen siempre cabe
                        // entera, centrada, con margen blanco si las proporciones difieren.
                        ZStack {
                            Color(.systemGray6)
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(10)
                        }
                    case .failure:
                        ZStack {
                            Color(.systemGray6)
                            placeholderContent
                        }
                    @unknown default:
                        ZStack {
                            Color(.systemGray6)
                            placeholderContent
                        }
                    }
                }
            } else {
                ZStack {
                    Color(.systemGray6)
                    placeholderContent
                }
            }
        }
    }

    private var placeholderContent: some View {
        VStack(spacing: 4) {
            Image(systemName: "photo")
                .foregroundStyle(.tertiary)
                .font(.system(size: 22))
            Text("NO IMAGE")
                .font(.system(size: 8, weight: .heavy))
                .tracking(1)
                .foregroundStyle(.tertiary)
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
                    TextField("URL de la imagen (https://…)", text: $draft.imageURL)
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
                            let ok = await viewModel.create(draft, ownerUserID: auth.session?.user.id)
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
