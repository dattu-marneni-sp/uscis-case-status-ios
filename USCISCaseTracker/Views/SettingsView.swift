import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var useProduction = false
    @State private var showSecret = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    clientIdField
                    if showSecret {
                        clientSecretTextField
                    } else {
                        clientSecretSecureField
                    }
                    Button(showSecret ? "Hide Secret" : "Show Secret") {
                        showSecret.toggle()
                    }
                    Toggle("Use Production API", isOn: $useProduction)
                } header: {
                    Text("USCIS API Credentials")
                } footer: {
                    Text(useProduction ? "Production: real case data. Requires production access from USCIS." : "Sandbox: test data only (e.g. EAC9999103402). Get credentials from developer.uscis.gov.")
                }

                Section {
                    Button("Save") {
                        saveCredentials()
                    }
                    .disabled(clientId.trimmingCharacters(in: .whitespaces).isEmpty || clientSecret.isEmpty)
                    if KeychainService.hasCredentials {
                        Button("Clear Credentials", role: .destructive) {
                            KeychainService.clearCredentials()
                            clientId = ""
                            clientSecret = ""
                            saved = true
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                clientId = KeychainService.clientId ?? ""
                clientSecret = KeychainService.clientSecret ?? ""
                useProduction = KeychainService.useProduction
            }
            .onChange(of: useProduction) { _, newValue in
                KeychainService.useProduction = newValue
            }
        }
    }

    private var clientIdField: some View {
        TextField("Client ID", text: $clientId)
            .textContentType(.username)
            .autocorrectionDisabled()
    }

    private var clientSecretTextField: some View {
        TextField("Client Secret", text: $clientSecret)
            .textContentType(.password)
            .autocorrectionDisabled()
    }

    private var clientSecretSecureField: some View {
        SecureField("Client Secret", text: $clientSecret)
            .textContentType(.password)
            .autocorrectionDisabled()
    }

    private func saveCredentials() {
        let id = clientId.trimmingCharacters(in: .whitespaces)
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !secret.isEmpty else { return }
        KeychainService.clientId = id
        KeychainService.clientSecret = secret
        KeychainService.useProduction = useProduction
        saved = true
        dismiss()
    }
}
