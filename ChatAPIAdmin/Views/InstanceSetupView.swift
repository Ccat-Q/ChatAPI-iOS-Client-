import SwiftUI

struct InstanceSetupView: View {
    @Environment(InstanceStore.self) private var store
    @State private var name = ""
    @State private var address = "https://"
    @State private var allowsHTTP = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Instance") {
                    TextField("Name", text: $name)
                    TextField("HTTPS URL", text: $address).textInputAutocapitalization(.never).keyboardType(.URL)
                    Toggle("Allow HTTP for development", isOn: $allowsHTTP)
                }
                Section { Button("Save Instance") { save() }.frame(maxWidth: .infinity) }
                footer: { Text("QR import can populate this form with a non-secret instance URL.") }
            }
            .navigationTitle("ChatAPI Admin")
            .alert("Cannot Add Instance", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard let url = URL(string: address), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter an instance name and valid URL."; return }
        do { try store.add(name: name, url: url, allowsInsecureHTTP: allowsHTTP) } catch { self.error = error.localizedDescription }
    }
}
