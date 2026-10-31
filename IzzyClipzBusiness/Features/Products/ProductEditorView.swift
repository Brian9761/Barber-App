import IzzyClipzKit
import PhotosUI
import SwiftUI

/// Add or edit a product: photo (library or camera, made smaller on the
/// phone), name, optional price and description, and whether the customer
/// app shows it.
struct ProductEditorView: View {
    let store: ProductsStore
    let allowsTestPhoto: Bool
    @State private var draft: ProductDraft
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var isProcessingPhoto = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmsDelete = false
    @Environment(\.dismiss) private var dismiss

    init(store: ProductsStore, product: IzzyAPI.Product?, allowsTestPhoto: Bool = false) {
        self.store = store
        self.allowsTestPhoto = allowsTestPhoto
        _draft = State(initialValue: ProductDraft(product: product))
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                Section("Details") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .accessibilityIdentifier("productName")
                    HStack {
                        Text("$").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("Price (optional)", text: $draft.priceText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Price in dollars, optional")
                            .accessibilityIdentifier("productPrice")
                    }
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    TextField("Description (optional)", text: $draft.description, axis: .vertical)
                        .lineLimit(2...6)
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .accessibilityIdentifier("productDescription")
                }
                Section {
                    Toggle("Show in the customer app", isOn: $draft.visible)
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .accessibilityIdentifier("productVisible")
                } footer: {
                    Text(draft.visible
                        ? "Clients see it in the Shop tab as available at the shop."
                        : "Hidden: it stays here but clients don't see it.")
                }
                if let error {
                    Section {
                        InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                            .accessibilityIdentifier("productError")
                    }
                }
                if !draft.isNew {
                    Section {
                        Button("Delete product", role: .destructive) { confirmsDelete = true }
                            .frame(minHeight: BusinessTheme.minimumTapSize)
                            .accessibilityIdentifier("deleteProduct")
                    }
                }
            }
            .navigationTitle(draft.isNew ? "New product" : "Edit product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(isProcessingPhoto)
                            .accessibilityIdentifier("saveProduct")
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                loadPicked(item)
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in
                    showsCamera = false
                    if let image { useCameraPhoto(image) }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete product", role: .destructive) { delete() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("It disappears from the customer app.")
            }
        }
        .accessibilityIdentifier("productEditor")
    }

    // MARK: Photo

    private var photoSection: some View {
        Section {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .frame(minHeight: BusinessTheme.minimumTapSize)
            }
            .accessibilityIdentifier("choosePhoto")
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showsCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                }
                .accessibilityIdentifier("takePhoto")
            }
            if allowsTestPhoto {
                Button {
                    useCameraPhoto(Self.testPhoto())
                } label: {
                    Label("Use a test photo", systemImage: "photo.badge.checkmark")
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                }
                .accessibilityIdentifier("useTestPhoto")
            }
            if draft.newPhoto != nil {
                Button("Don't use the new photo", role: .destructive) { draft.newPhoto = nil }
                    .frame(minHeight: BusinessTheme.minimumTapSize)
            }
        } header: {
            Text("Photo")
        } footer: {
            Text(photoFooter)
        }
    }

    private var photoFooter: String {
        if let data = draft.newPhoto {
            return "New photo ready (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). It uploads when you save."
        }
        return "Photos are made smaller (up to 1600 pixels) on this iPhone before they upload."
    }

    @ViewBuilder
    private var preview: some View {
        if isProcessingPhoto {
            ProgressView("Preparing the photo…")
        } else if let data = draft.newPhoto, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("New product photo")
                .accessibilityIdentifier("newPhotoPreview")
        } else if draft.imageURL != nil {
            ProductThumbnail(url: draft.imageURL, localData: draft.imageURL.flatMap { store.uploadedPhotos[$0] })
                .scaledToFit()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No photo yet").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) {
        isProcessingPhoto = true
        error = nil
        Task {
            defer {
                isProcessingPhoto = false
                pickerItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ProductPhoto.Failure.unreadable
                }
                draft.newPhoto = try await ProductPhoto.jpeg(fromImageData: data)
            } catch {
                self.error = (error as? ProductPhoto.Failure)?.errorDescription ?? "That photo couldn't be opened. Pick another one."
            }
        }
    }

    private func useCameraPhoto(_ image: UIImage) {
        do {
            draft.newPhoto = try ProductPhoto.jpeg(from: image)
            error = nil
        } catch {
            self.error = (error as? ProductPhoto.Failure)?.errorDescription ?? "That photo couldn't be used. Take it again."
        }
    }

    /// A plain gradient, for UI tests and the sample server only.
    static func testPhoto() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800), format: format).image { context in
            let colors = [UIColor.systemRed.cgColor, UIColor.systemBlue.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 2400, y: 1800), options: [])
            }
        }
    }

    // MARK: Saving

    private func save() {
        guard !isSaving else { return }
        if let problem = draft.problem {
            error = problem
            return
        }
        isSaving = true
        error = nil
        Task {
            let outcome = await store.save(draft)
            isSaving = false
            switch outcome {
            case .saved:
                dismiss()
            case .savedWithoutPhoto(let product, let message):
                // Saved: from now on Save updates this product instead of adding another.
                draft.id = product.id
                draft.imageURL = product.imageUrl
                error = message
            case .failed(let message):
                error = message
            }
        }
    }

    private func delete() {
        guard let id = draft.id, let product = store.products.first(where: { $0.id == id }) else {
            dismiss()
            return
        }
        Task {
            if await store.delete(product) { dismiss() }
        }
    }
}

/// The camera, for a product photo. Calls back with the photo, or `nil` when
/// the owner cancels.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
