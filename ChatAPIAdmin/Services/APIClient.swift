import Foundation

enum APIError: LocalizedError { case unauthorized, invalidResponse, server(String), transport(Error)
    var errorDescription: String? { switch self { case .unauthorized: localized("Your device session has expired.", "设备会话已过期。"); case .invalidResponse: localized("The server returned an invalid response.", "服务器返回了无效响应。"); case .server(let message): message; case .transport(let error): error.localizedDescription } }
}

actor APIClient {
    private let instance: Instance
    private let session: URLSession
    private let onUnauthorized: (@Sendable () async -> Void)?

    init(instance: Instance, onUnauthorized: (@Sendable () async -> Void)? = nil) {
        self.instance = instance
        self.onUnauthorized = onUnauthorized
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration, delegate: APIRedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func sessionInfo() async throws -> SessionResponse {
        let response: SessionResponse = try await request("/api/auth/session", method: "GET", body: EmptyBody(), timeout: 15)
        if !response.authenticated || response.user == nil { await onUnauthorized?() }
        return response
    }

    func workspaceRequest() -> URLRequest? {
        guard var components = URLComponents(url: instance.baseURL, resolvingAgainstBaseURL: true) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/ws"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = true
        if let cookies = HTTPCookieStorage.shared.cookies(for: instance.baseURL) {
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) { request.setValue(value, forHTTPHeaderField: field) }
        }
        request.setValue(instance.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        return request
    }

    func workspaceSocket() -> URLSessionWebSocketTask? {
        guard let request = workspaceRequest() else { return nil }
        return session.webSocketTask(with: request)
    }

    func workspaceSessionRejected() async { await onUnauthorized?() }

    func absoluteURL(for pathOrURL: String) -> URL? {
        guard let url = URL(string: pathOrURL, relativeTo: instance.baseURL)?.absoluteURL,
              url.user == nil, url.password == nil,
              url.scheme == "https" || (instance.allowsInsecureHTTP && url.scheme == "http" && url.host == instance.baseURL.host && url.port == instance.baseURL.port) else { return nil }
        return url
    }

    func login(username: String, password: String, totp: String? = nil) async throws {
        struct Credentials: Encodable, Sendable { let username: String; let password: String; let totp: String? }
        struct LoginResponse: Decodable, Sendable { let ok: Bool }
        let response: LoginResponse = try await request("/api/auth/login", method: "POST", body: Credentials(username: username, password: password, totp: totp))
        guard response.ok else { throw APIError.unauthorized }
    }

    func get<T: Decodable & Sendable>(_ path: String) async throws -> T { try await request(path, method: "GET", body: EmptyBody()) }
    func post<T: Decodable & Sendable, Body: Encodable & Sendable>(_ path: String, body: Body) async throws -> T { try await request(path, method: "POST", body: body) }
    func patch<T: Decodable & Sendable, Body: Encodable & Sendable>(_ path: String, body: Body) async throws -> T { try await request(path, method: "PATCH", body: body) }
    func put<T: Decodable & Sendable, Body: Encodable & Sendable>(_ path: String, body: Body) async throws -> T { try await request(path, method: "PUT", body: body) }
    func delete<T: Decodable & Sendable>(_ path: String) async throws -> T { try await request(path, method: "DELETE", body: EmptyBody()) }

    private func request<T: Decodable & Sendable, Body: Encodable & Sendable>(_ path: String, method: String, body: Body?, timeout: TimeInterval = 60) async throws -> T {
        guard let url = URL(string: path, relativeTo: instance.baseURL)?.absoluteURL,
              url.scheme == instance.baseURL.scheme, url.host == instance.baseURL.host, url.port == instance.baseURL.port,
              url.user == nil, url.password == nil else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = method
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let scheme = url.scheme, let host = url.host {
            let port = url.port.map { ":\($0)" } ?? ""
            request.setValue("\(scheme)://\(host)\(port)", forHTTPHeaderField: "Origin")
        }
        if method != "GET", method != "DELETE", let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let (fileURL, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 < 1_048_576 else {
                throw APIError.server(localized("The server response exceeded the 1 MiB safety limit.", "服务器响应超过了 1 MiB 安全限制。"))
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            if http.statusCode == 401 { await onUnauthorized?(); throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw APIError.server(String(data: data, encoding: .utf8) ?? "Request failed (\(http.statusCode)).") }
            if data.isEmpty, let success = SuccessResponse(ok: true) as? T { return success }
            return try JSONDecoder.chatAPI.decode(T.self, from: data)
        } catch let error as APIError { throw error } catch { throw APIError.transport(error) }
    }
}

private struct EmptyBody: Encodable, Sendable {}

private final class APIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              target.scheme == original.scheme, target.host == original.host, target.port == original.port,
              target.user == nil, target.password == nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

extension JSONDecoder {
    static var chatAPI: JSONDecoder {
        let decoder = JSONDecoder()
        // Wire keys are declared explicitly in Models.swift, including acronym IDs.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 timestamp: \(value)")
        }
        return decoder
    }
}
