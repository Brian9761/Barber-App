import SwiftUI

/// "Your details" in a sheet, from Book: change the name and number the app fills in, or forget
/// them. Appointments already booked keep the details they were booked with; the booking being
/// made takes the new ones.
struct CustomerDetailsSheet: View {
    @Environment(CustomerDetailsStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var showsProblems = false
    @State private var isConfirmingForget = false

    private var details: CustomerDetails { CustomerDetails(name: name, phone: phone) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("detailsSheetName")
                    if showsProblems, let problem = details.nameProblem {
                        Text(problem)
                            .textRole(.caption)
                            .foregroundStyle(Theme.caution)
                    }
                    TextField("Mobile number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .accessibilityIdentifier("detailsSheetPhone")
                    if showsProblems, let problem = details.phoneProblem {
                        Text(problem)
                            .textRole(.caption)
                            .foregroundStyle(Theme.caution)
                    }
                } footer: {
                    Text("Filled in when you book. They're sent to \(AppData.shop.name) only with a booking.")
                }
                Section {
                    Button("Forget my details", role: .destructive) {
                        isConfirmingForget = true
                    }
                    .accessibilityIdentifier("forgetDetailsButton")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink2.ignoresSafeArea())
            .navigationTitle("Your details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveDetailsButton")
                }
            }
            .confirmationDialog("Forget your name and number?", isPresented: $isConfirmingForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) {
                    store.forget()
                    router.rememberedDetailsChanged(to: nil)
                    dismiss()
                }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("You'll type them again next time you book.")
            }
        }
        .onAppear {
            name = store.saved?.name ?? ""
            phone = store.saved?.phone ?? ""
        }
    }

    private func save() {
        guard details.isValid else {
            showsProblems = true
            return
        }
        store.remember(details)
        router.rememberedDetailsChanged(to: store.saved)
        dismiss()
    }
}
