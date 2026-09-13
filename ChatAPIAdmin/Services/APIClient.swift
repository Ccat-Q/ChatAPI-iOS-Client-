import Foundation

enum APIError: LocalizedError { case unauthorized, invalidResponse, server(String), transport(Error)
    var errorDescription: String? { switch self { case .unauthorized: localized("Your device session has expired.", "设备会话已过期。"); case .invalidResponse: localized("The server returned an invalid response.", "服务器返回了无效响应。"); case .server(let message): message; case .transport(let error): error.localizedDescription } }
}

actor APIClient {
    private let instance: Instance
    private var token: String?
    private let session: URLSession

    init(instance: Instance, token: String?) {
        self.instance = instance
        self.token = token
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

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
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let scheme = url.scheme, let host = url.host {
            let port = url.port.map { ":\($0)" } ?? ""
            request.setValue("\(scheme)://\(host)\(port)", forHTTPHeaderField: "Origin")
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let (fileURL, response) = try await session.download(for: request)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 < 1_048_576 else {
                throw APIError.server(localized("The server response exceeded the 1 MiB safety limit.", "服务器响应超过了 1 MiB 安全限制。"))
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
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
