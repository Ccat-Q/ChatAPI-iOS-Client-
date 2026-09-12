import Foundation

enum APIError: LocalizedError { case unauthorized, invalidResponse, server(String), transport(Error)
    var errorDescription: String? { switch self { case .unauthorized: "Your device session has expired."; case .invalidResponse: "The server returned an invalid response."; case .server(let message): message; case .transport(let error): error.localizedDescription } }
}

actor APIClient {
    private let instance: Instance
    private var token: String?

    init(instance: Instance, token: String?) { self.instance = instance; self.token = token }

    func setToken(_ value: String?) { token = value }

    func login(username: String, password: String) async throws {
        struct Credentials: Encodable { let username: String; let password: String }
        struct LoginResponse: Decodable { let ok: Bool }
        let _: LoginResponse = try await request("/api/auth/login", method: "POST", body: Credentials(username: username, password: password))
    }

    func get<T: Decodable>(_ path: String) async throws -> T { try await request(path, method: "GET", body: EmptyBody()) }
    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T { try await request(path, method: "POST", body: body) }
    func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T { try await request(path, method: "PATCH", body: body) }

    private func request<T: Decodable, Body: Encodable>(_ path: String, method: String, body: Body?) async throws -> T {
        guard let url = URL(string: path, relativeTo: instance.baseURL) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let scheme = url.scheme, let host = url.host {
            let port = url.port.map { ":\($0)" } ?? ""
            request.setValue("\(scheme)://\(host)\(port)", forHTTPHeaderField: "Origin")
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw APIError.server(String(data: data, encoding: .utf8) ?? "Request failed (\(http.statusCode)).") }
            return try JSONDecoder.chatAPI.decode(T.self, from: data)
        } catch let error as APIError { throw error } catch { throw APIError.transport(error) }
    }
}

private struct EmptyBody: Encodable {}

extension JSONDecoder {
    static var chatAPI: JSONDecoder { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.dateDecodingStrategy = .iso8601; return decoder }
}
