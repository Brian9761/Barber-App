import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Products: list, add with a photo, edit, hide and show, delete.
@MainActor
final class ProductsStoreTests: XCTestCase {
    private var harness: Harness!
    private var api: ScriptedAPI!

    override func setUp() async throws {
        harness = Harness()
        api = ScriptedAPI(base: harness.api)
    }

    private func makeStore() -> ProductsStore { ProductsStore(api: api) }

    /// Enough of a JPEG for the server's check (its first bytes).
    private func jpeg() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0x42, count: 2_000)
    }

    func testListsEveryProductIncludingHiddenOnes() async {
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.products.map(\.name), ["Sample pomade", "Sample beard oil"])
        XCTAssertEqual(store.products.map(\.visible), [true, false])
    }

    func testAddAProductWithAPhoto() async throws {
        let store = makeStore()
        await store.refresh()
        var draft = ProductDraft()
        draft.name = " Sample clay "
        draft.priceText = "$22.50"
        draft.description = "Matte finish"
        draft.newPhoto = jpeg()
        let outcome = await store.save(draft)
        guard case .saved(let product) = outcome else { return XCTFail("Expected saved, got \(outcome)") }
        XCTAssertEqual(product.name, "Sample clay")
        XCTAssertEqual(product.priceCents, 2250)
        XCTAssertEqual(product.description, "Matte finish")
        XCTAssertTrue(product.visible)
        let url = try XCTUnwrap(product.imageUrl)
        XCTAssertEqual(store.uploadedPhotos[url], draft.newPhoto, "Shown straight away from this phone")
        XCTAssertEqual(harness.server.photos[product.id], draft.newPhoto)
        XCTAssertEqual(store.products.last, product)
        XCTAssertEqual(harness.server.calls.suffix(2), ["createProduct", "uploadProductPhoto"])
    }

    func testEditClearsAnEmptyPriceAndDescription() async throws {
        let store = makeStore()
        await store.refresh()
        let pomade = try XCTUnwrap(store.products.first)
        var draft = ProductDraft(product: pomade)
        XCTAssertEqual(draft.priceText, "18")
        draft.priceText = ""
        draft.description = "   "
        draft.name = "Sample pomade, strong hold"
        let outcome = await store.save(draft)
        guard case .saved(let product) = outcome else { return XCTFail("Expected saved, got \(outcome)") }
        XCTAssertNil(product.priceCents, "No price: \"ask at the counter\"")
        XCTAssertNil(product.description)
        XCTAssertEqual(product.name, "Sample pomade, strong hold")
        XCTAssertEqual(store.products.count, 2, "Edited in place")
        XCTAssertFalse(harness.server.calls.contains("uploadProductPhoto"), "No new photo, no upload")
    }

    func testAPhotoThatFailsToUploadKeepsTheProductAndTheNextSaveUpdatesIt() async throws {
        var uploads = 0
        api.uploadHandler = { [base = api.base] id, data in
            uploads += 1
            if uploads == 1 { throw APIError.server(code: "invalid_request", message: "That photo is too big to upload. Pick a smaller one, or take it again.", status: 413) }
            return try await base.uploadProductPhoto(id: id, jpegData: data)
        }
        let store = makeStore()
        await store.refresh()
        var draft = ProductDraft()
        draft.name = "Sample comb"
        draft.newPhoto = jpeg()
        let first = await store.save(draft)
        guard case .savedWithoutPhoto(let product, let message) = first else { return XCTFail("Expected saved without photo, got \(first)") }
        XCTAssertTrue(message.contains("too big"))
        XCTAssertEqual(store.products.filter { $0.name == "Sample comb" }.count, 1)

        // The editor keeps the photo and now edits the saved product.
        draft.id = product.id
        let second = await store.save(draft)
        guard case .saved(let updated) = second else { return XCTFail("Expected saved, got \(second)") }
        XCTAssertNotNil(updated.imageUrl)
        XCTAssertEqual(store.products.filter { $0.name == "Sample comb" }.count, 1, "No duplicate product")
        XCTAssertEqual(harness.server.products.filter { $0.name == "Sample comb" }.count, 1)
    }

    func testHideShowAndDelete() async throws {
        let store = makeStore()
        await store.refresh()
        let pomade = try XCTUnwrap(store.products.first)
        await store.setVisible(false, for: pomade)
        XCTAssertEqual(store.products.first?.visible, false)
        await store.setVisible(true, for: pomade)
        XCTAssertEqual(store.products.first?.visible, true)
        let deleted = await store.delete(pomade)
        XCTAssertTrue(deleted)
        XCTAssertFalse(store.products.contains { $0.id == pomade.id })
        XCTAssertFalse(harness.server.products.contains { $0.id == pomade.id })
        XCTAssertTrue(store.busy.isEmpty)
    }

    func testAFailedChangeIsReported() async throws {
        let store = makeStore()
        await store.refresh()
        let pomade = try XCTUnwrap(store.products.first)
        harness.server.options.offline = true
        await store.setVisible(false, for: pomade)
        XCTAssertEqual(store.actionError, APIError.offline.userMessage)
        XCTAssertEqual(store.products.first?.visible, true)
        let deleted = await store.delete(pomade)
        XCTAssertFalse(deleted)
    }

    func testDraftValidationMatchesTheServer() {
        var draft = ProductDraft()
        XCTAssertEqual(draft.problem, "Give the product a name.")
        draft.name = String(repeating: "a", count: 81)
        XCTAssertEqual(draft.problem, "Keep the name to 80 characters or fewer.")
        draft.name = "Sample"
        draft.priceText = "12.345"
        XCTAssertEqual(draft.problem, "Enter the price like 18 or 18.50, or leave it empty.")
        draft.priceText = "10000.01"
        XCTAssertEqual(draft.problem, "That price is too high.")
        draft.priceText = "10000"
        XCTAssertNil(draft.problem)
        draft.description = String(repeating: "d", count: 501)
        XCTAssertEqual(draft.problem, "Keep the description to 500 characters or fewer.")
    }

    func testTheSampleServerRefusesAnythingButASmallJPEG() async throws {
        let id = try XCTUnwrap(harness.server.products.first?.id)
        do {
            _ = try await harness.api.uploadProductPhoto(id: id, jpegData: Data(repeating: 0, count: 10))
            XCTFail("A non-JPEG was accepted")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "invalid_request")
        }
    }
}
