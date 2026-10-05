import SwiftUI

/// One-time setup, done by whoever installs the app (not the cashier).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = KeychainStore.string(for: SettingsKeys.apiKey) ?? ""
    @AppStorage(SettingsKeys.location) private var location = ""
    @AppStorage(SettingsKeys.maxResults) private var maxResults = 5
    @AppStorage(SettingsKeys.showOthers) private var showOthers = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("SerpApi key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Get a key at serpapi.com", destination: URL(string: "https://serpapi.com/manage-api-key")!)
                } header: {
                    Text("Price service")
                } footer: {
                    Text("Each scan uses 4 searches. Scanning the same item again within 15 minutes is free.")
                }

                Section {
                    TextField("e.g. Atlanta, Georgia", text: $location)
                } header: {
                    Text("Store location")
                } footer: {
                    Text("City and state, used to find nearby stores with the item in stock. Leave empty for nationwide prices.")
                }

                Section("Results") {
                    Stepper("Show up to \(maxResults) stores", value: $maxResults, in: 3...10)
                    Toggle("Also show sellers that usually can't be matched", isOn: $showOthers)
                }
            }
            .navigationTitle("Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        KeychainStore.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                          for: SettingsKeys.apiKey)
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
    }
}
