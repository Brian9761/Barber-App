import Foundation
import IzzyClipzKit
import Observation

/// The shop's own products: every one, hidden ones too, in the shop's order.
@MainActor
@Observable
final class ProductsStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum SaveOutcome: Equatable {
        case saved(IzzyAPI.Product)
        /// The product was saved but its photo didn't upload.
        case savedWithoutPhoto(IzzyAPI.Product, String)
        case failed(String)
    }

    private(set) var products: [IzzyAPI.Product] = []
    private(set) var loadState: LoadState = .idle
    /// Products being changed right now.
    private(set) var busy: Set<String> = []
    /// A change that didn't work, for an alert.
    var actionError: String?
    /// Photos uploaded from this phone, shown straight away by URL.
    private(set) var uploadedPhotos: [URL: Data] = [:]

    @ObservationIgnored private let api: any OwnerAPI

    init(api: any OwnerAPI) {
        self.api = api
    }

    func refresh() async {
        if loadState != .loaded { loadState = .loading }
        do {
            products = try await api.allProducts()
            loadState = .loaded
        } catch is CancellationError {
            if loadState == .loading { loadState = .idle }
        } catch {
            let message = ErrorText.message(for: error)
            if loadState == .loaded {
                actionError = message
            } else {
                loadState = .failed(message)
            }
        }
    }

    /// Creates or updates a product, then uploads its new photo if there is one.
    func save(_ draft: ProductDraft) async -> SaveOutcome {
        if let problem = draft.problem { return .failed(problem) }
        var saved: IzzyAPI.Product
        do {
            if let id = draft.id {
                saved = try await api.updateProduct(id: id, IzzyAPI.ProductUpdate.replacing(
                    name: draft.name, description: draft.description, priceCents: draft.priceCents, visible: draft.visible
                ))
            } else {
                saved = try await api.createProduct(IzzyAPI.NewProduct(
                    name: draft.name, description: draft.description, priceCents: draft.priceCents, visible: draft.visible
                ))
            }
        } catch is CancellationError {
            return .failed("Saving was interrupted. Try again.")
        } catch {
            return .failed(ErrorText.message(for: error))
        }
        store(saved)
        guard let photo = draft.newPhoto else { return .saved(saved) }
        do {
            saved = try await api.uploadProductPhoto(id: saved.id, jpegData: photo)
            if let url = saved.imageUrl { uploadedPhotos[url] = photo }
            store(saved)
            return .saved(saved)
        } catch {
            return .savedWithoutPhoto(saved, "The product was saved, but its photo didn't upload: \(ErrorText.message(for: error))")
        }
    }

    /// Hides a product from the customer app, or shows it again.
    func setVisible(_ visible: Bool, for product: IzzyAPI.Product) async {
        guard !busy.contains(product.id) else { return }
        busy.insert(product.id)
        defer { busy.remove(product.id) }
        do {
            store(try await api.updateProduct(id: product.id, IzzyAPI.ProductUpdate(visible: visible)))
        } catch is CancellationError {
            return
        } catch {
            actionError = ErrorText.message(for: error)
        }
    }

    @discardableResult
    func delete(_ product: IzzyAPI.Product) async -> Bool {
        guard !busy.contains(product.id) else { return false }
        busy.insert(product.id)
        defer { busy.remove(product.id) }
        do {
            try await api.deleteProduct(id: product.id)
            products.removeAll { $0.id == product.id }
            return true
        } catch let error as APIError where error.code == IzzyAPI.ErrorCode.notFound {
            products.removeAll { $0.id == product.id }
            return true
        } catch is CancellationError {
            return false
        } catch {
            actionError = ErrorText.message(for: error)
            return false
        }
    }

    private func store(_ product: IzzyAPI.Product) {
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index] = product
        } else {
            products.append(product)
        }
    }
}

/// The product editor's fields.
struct ProductDraft: Equatable {
    var id: String?
    var name = ""
    var priceText = ""
    var description = ""
    var visible = true
    /// The photo on the server now.
    var imageURL: URL?
    /// A new photo to upload, already resized to a JPEG under the limit.
    var newPhoto: Data?

    init(product: IzzyAPI.Product? = nil) {
        guard let product else { return }
        id = product.id
        name = product.name
        priceText = product.priceCents.map(Money.editable) ?? ""
        description = product.description ?? ""
        visible = product.visible
        imageURL = product.imageUrl
    }

    var isNew: Bool { id == nil }

    /// `nil` when the price is left empty ("ask at the counter").
    var priceCents: Int? { Money.cents(from: priceText) }

    /// The server's limits: name 1–80 characters, description up to 500,
    /// price $0 to $10,000.
    var problem: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return "Give the product a name." }
        if trimmedName.count > 80 { return "Keep the name to 80 characters or fewer." }
        let typedPrice = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedPrice.isEmpty {
            guard let cents = Money.cents(from: typedPrice) else { return "Enter the price like 18 or 18.50, or leave it empty." }
            if cents > 1_000_000 { return "That price is too high." }
        }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).count > 500 {
            return "Keep the description to 500 characters or fewer."
        }
        return nil
    }
}
