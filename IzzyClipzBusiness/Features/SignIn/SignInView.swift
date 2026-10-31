import SwiftUI

/// Sign in with the owner key: pasted once, checked with the server, then
/// kept in this iPhone's keychain.
struct SignInView: View {
    let model: AppModel
    @State private var key = ""
    @FocusState private var keyFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220)
                            .accessibilityHidden(true)
                        Text("Izzy Clipz Business")
                            .font(.title2.bold())
                        Text("The shop's schedule, walk-ins, products and card payments.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }

                if let notice = model.notice {
                    Section {
                        InlineMessage(text: notice, systemImage: "info.circle.fill", color: .blue)
                            .accessibilityIdentifier("signInNotice")
                    }
                }

                Section {
                    SecureField("Owner key", text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($keyFocused)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .accessibilityIdentifier("ownerKeyField")
                    // The system Paste button reads the clipboard without iOS asking
                    // for permission, since the owner tapped it.
                    PasteButton(payloadType: String.self) { strings in
                        if let pasted = strings.first {
                            key = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("pasteKeyButton")
                } header: {
                    Text("Owner key")
                } footer: {
                    Text("The long secret set as OWNER_KEY on the shop's server. Paste it once; this iPhone keeps it in its keychain.")
                }

                if let error = model.signInError {
                    Section {
                        InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                            .accessibilityIdentifier("signInError")
                    }
                }

                Section {
                    Button(action: signIn) {
                        HStack {
                            if model.isSigningIn {
                                ProgressView().tint(.white)
                            }
                            Text(model.isSigningIn ? "Checking the key…" : "Sign in")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isSigningIn)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("signInButton")
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func signIn() {
        keyFocused = false
        Task { await model.signIn(key: key) }
    }
}
