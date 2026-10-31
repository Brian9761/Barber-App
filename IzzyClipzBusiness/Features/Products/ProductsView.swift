import IzzyClipzKit
import SwiftUI

/// The shop's own products: add, edit, hide or show in the customer app,
/// delete. The customer app shows the visible ones as "available at the shop".
struct ProductsView: View {
    let store: ProductsStore
    /// The sample server's "Use a test photo" button, for UI tests.
    var allowsTestPhoto = false
    @State private var editing: EditorItem?
    @State private var productToDelete: IzzyAPI.Product?

    var body: some View {
        NavigationStack {
            List {
                content
            }
            .navigationTitle("Products")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = EditorItem(product: nil)
                    } label: {
                        Label("Add product", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addProduct")
                }
            }
            .refreshable { await store.refresh() }
            // Every time the tab shows: what's on screen stays while it reloads.
            .task { await store.refresh() }
            .sheet(item: $editing) { item in
                ProductEditorView(store: store, product: item.product, allowsTestPhoto: allowsTestPhoto)
            }
            .confirmationDialog(
                "Delete this product?",
                isPresented: Binding(get: { productToDelete != nil }, set: { if !$0 { productToDelete = nil } }),
                titleVisibility: .visible,
                presenting: productToDelete
            ) { product in
                Button("Delete \(product.name)", role: .destructive) {
                    Task { await store.delete(product) }
                }
                .accessibilityIdentifier("confirmDeleteProduct")
                Button("Keep it", role: .cancel) {}
            } message: { _ in
                Text("It disappears from the customer app. To take it off the app for a while instead, hide it.")
            }
            .alert(
                "That didn't work",
                isPresented: Binding(get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.actionError ?? "")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading:
            if store.products.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading products…")
                    Spacer()
                }
                .padding(.vertical, 24)
            } else {
                rows
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load the products", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            if store.products.isEmpty {
                ContentUnavailableView {
                    Label("No products yet", systemImage: "bag")
                } description: {
                    Text("Add the shop's own products with a photo and a price. Clients see them in the Izzy Clipz app.")
                } actions: {
                    Button("Add a product") { editing = EditorItem(product: nil) }
                        .buttonStyle(.borderedProminent)
                }
                .accessibilityIdentifier("productsEmpty")
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        Section {
            ForEach(store.products) { product in
                Button {
                    editing = EditorItem(product: product)
                } label: {
                    ProductRow(product: product, store: store)
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { productToDelete = product }
                    Button(product.visible ? "Hide" : "Show") {
                        Task { await store.setVisible(!product.visible, for: product) }
                    }
                    .tint(product.visible ? .orange : .green)
                }
                .contextMenu {
                    Button(product.visible ? "Hide from the app" : "Show in the app", systemImage: product.visible ? "eye.slash" : "eye") {
                        Task { await store.setVisible(!product.visible, for: product) }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { productToDelete = product }
                }
                .accessibilityIdentifier("product-\(product.name)")
                .accessibilityAction(named: product.visible ? "Hide from the app" : "Show in the app") {
                    Task { await store.setVisible(!product.visible, for: product) }
                }
                .accessibilityAction(named: "Delete") { productToDelete = product }
            }
        } footer: {
            Text("Swipe left to hide or delete. Hidden products stay here but aren't in the customer app.")
        }
    }
}

private struct EditorItem: Identifiable {
    let id = UUID()
    let product: IzzyAPI.Product?
}

struct ProductRow: View {
    let product: IzzyAPI.Product
    let store: ProductsStore

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(url: product.imageUrl, localData: product.imageUrl.flatMap { store.uploadedPhotos[$0] })
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name).font(.body.weight(.semibold))
                Text(product.priceCents.map(Money.amount) ?? "No price shown")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !product.visible {
                    Badge(text: "Hidden", color: .orange)
                }
            }
            Spacer(minLength: 0)
            if store.busy.contains(product.id) {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([product.name, product.priceCents.map(Money.amount) ?? "no price", product.visible ? nil : "hidden"].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens the editor.")
    }
}

/// A product's photo: one just uploaded from this phone, the one on the
/// server, or a placeholder.
struct ProductThumbnail: View {
    let url: URL?
    var localData: Data?

    var body: some View {
        Group {
            if let localData, let image = UIImage(data: localData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    default: ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill))
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }
}
