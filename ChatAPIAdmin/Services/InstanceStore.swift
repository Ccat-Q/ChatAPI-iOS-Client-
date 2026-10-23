import Foundation
import Observation

@MainActor @Observable final class InstanceStore {
    private(set) var instances: [Instance] = []
    private(set) var selectedID: UUID?
    private var authenticatedID: UUID?
    private var restored = false
    private var validationID = UUID()
    private var clientGeneration = UUID()
    @ObservationIgnored private var cachedClient: APIClient?
    private(set) var sessionUser: SessionUser?
    private(set) var isCheckingSession = false
    private(set) var sessionError: String?
    var storageError: String?
    var selected: Instance? { instances.first { $0.id == selectedID } }

    func restore() {
        guard !restored else { return }
        restored = true
        do {
            guard let data = try KeychainStore.load(account: "instances") else { return }
            instances = try JSONDecoder().decode([Instance].self, from: data)
            let savedID = UserDefaults.standard.string(forKey: "selected-instance").flatMap(UUID.init(uuidString:))
            select(instances.first { $0.id == savedID }?.id ?? instances.first?.id)
        } catch { storageError = error.localizedDescription }
    }

    func select(_ id: UUID?) {
        guard id == nil || instances.contains(where: { $0.id == id }) else { return }
        guard selectedID != id else { return }
        invalidateValidation()
        selectedID = id
        UserDefaults.standard.set(id?.uuidString, forKey: "selected-instance")
    }

    func add(name: String, url: URL, allowsInsecureHTTP: Bool) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw InstanceError.emptyName }
        let url = try Instance.validatedURL(url, allowsInsecureHTTP: allowsInsecureHTTP)
        let instance = Instance(id: UUID(), name: name, baseURL: url, allowsInsecureHTTP: allowsInsecureHTTP, capabilities: nil)
        let updated = instances + [instance]
        try persist(updated)
        instances = updated
        select(instance.id)
    }

    func remove(_ instance: Instance) throws {
        let updated = instances.filter { $0.id != instance.id }
        try persist(updated)
        clearSession(for: instance)
        KeychainStore.deleteAccounts(withPrefix: "workspace-draft.\(instance.id.uuidString).")
        KeychainStore.deleteAccounts(withPrefix: "ai-assist.\(instance.id.uuidString).")
        instances = updated
        if selectedID == instance.id { select(instances.first?.id) }
    }

    func hasSession(for instance: Instance) -> Bool { authenticatedID == instance.id && sessionUser != nil }
    func hasStoredSession(for instance: Instance) -> Bool {
        (try? KeychainStore.load(account: "session-marker.\(instance.id.uuidString)")) != nil
    }

    func signIn(username: String, password: String, totp: String? = nil, to instance: Instance) async throws {
        let client = APIClient(instance: instance)
        let attempt = validationID
        try await client.login(username: username, password: password, totp: totp)
        try await acceptSession(from: client, for: instance, attempt: attempt)
    }

    func acceptBrowserSession(for instance: Instance) async throws {
        try await acceptSession(from: APIClient(instance: instance), for: instance, attempt: validationID)
    }

    private func acceptSession(from client: APIClient, for instance: Instance, attempt: UUID) async throws {
        let response = try await client.sessionInfo()
        guard response.authenticated, let user = response.user else { throw APIError.unauthorized }
        guard selectedID == instance.id, attempt == validationID, !Task.isCancelled else { return }
        try KeychainStore.save(Data("cookie-session".utf8), account: "session-marker.\(instance.id.uuidString)")
        sessionUser = user
        authenticatedID = instance.id
        sessionError = nil
    }

    func clearSession(for instance: Instance) {
        KeychainStore.delete(account: "session.\(instance.id.uuidString)")
        KeychainStore.delete(account: "session-marker.\(instance.id.uuidString)")
        // Delete only cookies applicable to this server; other hosts stay signed in.
        for cookie in HTTPCookieStorage.shared.cookies(for: instance.baseURL) ?? [] { HTTPCookieStorage.shared.deleteCookie(cookie) }
        if selectedID == instance.id { invalidateValidation() }
    }

    func invalidateValidation() {
        validationID = UUID()
        clientGeneration = UUID()
        cachedClient = nil
        authenticatedID = nil
        sessionUser = nil
        isCheckingSession = false
        sessionError = nil
    }

    func client() -> APIClient? {
        guard let instance = selected else { return nil }
        if let cachedClient { return cachedClient }
        let generation = clientGeneration
        let client = APIClient(instance: instance) { [weak self] in
            await self?.sessionExpired(for: instance, generation: generation)
        }
        cachedClient = client
        return client
    }

    private func sessionExpired(for instance: Instance, generation: UUID) {
        guard selectedID == instance.id, clientGeneration == generation else { return }
        clearSession(for: instance)
    }

    func refreshSession() async {
        guard let instance = selected, hasStoredSession(for: instance), !hasSession(for: instance), !isCheckingSession,
              let client = client() else { return }
        let attempt = UUID()
        validationID = attempt
        isCheckingSession = true
        sessionError = nil
        defer { if validationID == attempt { isCheckingSession = false } }
        do {
            let session = try await client.sessionInfo()
            guard selectedID == instance.id, validationID == attempt, !Task.isCancelled else { return }
            guard session.authenticated, let user = session.user else { clearSession(for: instance); return }
            authenticatedID = instance.id
            sessionUser = user
        } catch {
            guard selectedID == instance.id, validationID == attempt, !Task.isCancelled else { return }
            if case APIError.unauthorized = error { clearSession(for: instance) }
            else { sessionError = error.localizedDescription }
        }
    }

    private func persist(_ values: [Instance]) throws {
        try KeychainStore.save(try JSONEncoder().encode(values), account: "instances")
    }
}
