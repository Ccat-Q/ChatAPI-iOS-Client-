import Foundation
import Observation

@Observable final class InstanceStore {
    private(set) var instances: [Instance] = []
    var selectedID: UUID?
    var selected: Instance? { instances.first { $0.id == selectedID } }

    func restore() async {
        guard let data = try? KeychainStore.load(account: "instances"), let values = try? JSONDecoder().decode([Instance].self, from: data) else { return }
        instances = values; selectedID = values.first?.id
    }

    func add(name: String, url: URL, allowsInsecureHTTP: Bool) throws {
        guard url.scheme == "https" || allowsInsecureHTTP else { throw InstanceError.insecureURL }
        let instance = Instance(id: UUID(), name: name, baseURL: url, allowsInsecureHTTP: allowsInsecureHTTP, capabilities: nil)
        instances.append(instance); selectedID = instance.id; try persist()
    }

    func remove(_ instance: Instance) { instances.removeAll { $0.id == instance.id }; KeychainStore.delete(account: "session.\(instance.id.uuidString)"); selectedID = instances.first?.id; try? persist() }
    func token(for instance: Instance) -> String? { guard let data = try? KeychainStore.load(account: "session.\(instance.id.uuidString)") else { return nil }; return String(data: data, encoding: .utf8) }
    func saveToken(_ token: String, for instance: Instance) throws { try KeychainStore.save(Data(token.utf8), account: "session.\(instance.id.uuidString)") }
    func client() -> APIClient? { guard let instance = selected else { return nil }; return APIClient(instance: instance, token: token(for: instance)) }
    private func persist() throws { try KeychainStore.save(try JSONEncoder().encode(instances), account: "instances") }
}

enum InstanceError: LocalizedError { case insecureURL; var errorDescription: String? { "Use HTTPS, or explicitly allow a development HTTP instance." } }
