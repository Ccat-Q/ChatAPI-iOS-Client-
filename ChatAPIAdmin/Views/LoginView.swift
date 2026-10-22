import SwiftUI
import WebKit

struct LoginView: View {
    let instance: Instance
    @Environment(InstanceStore.self) private var store
    @State private var username = ""
    @State private var password = ""
    @State private var totp = ""
    @State private var browserLogin = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(localized("Instance", "实例")) { LabeledContent(instance.name, value: instance.baseURL.host() ?? instance.baseURL.absoluteString) }
                Section(localized("Account Login", "账户登录")) {
                    TextField(localized("Username", "用户名"), text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(localized("Password", "密码"), text: $password)
                    TextField(localized("TOTP code (if enabled)", "TOTP 验证码（如已启用）"), text: $totp).keyboardType(.numberPad).textContentType(.oneTimeCode)
                }
                Section { Button { Task { await login() } } label: { if isLoading { ProgressView().frame(maxWidth: .infinity) } else { Text(localized("Sign In", "登录")).frame(maxWidth: .infinity) } }.disabled(isLoading || username.isEmpty || password.isEmpty) }
                Section { Button(localized("Web Sign In / SSO", "网页登录 / SSO")) { browserLogin = true }.disabled(isLoading) }
                Section { Button(localized("Remove Instance", "移除实例"), role: .destructive) { do { try store.remove(instance) } catch { self.error = error.localizedDescription } }.disabled(isLoading) }
            }
            .navigationTitle(localized("Sign In", "登录"))
            .sheet(isPresented: $browserLogin) { BrowserLoginView(instance: instance) }
            .alert(localized("Sign In Failed", "登录失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
        }
    }

    private func login() async {
        isLoading = true
        defer { isLoading = false }
        do { try await store.signIn(username: username, password: password, totp: totp.isEmpty ? nil : totp, to: instance); password = ""; totp = "" }
        catch { self.error = error.localizedDescription }
    }
}

private struct BrowserLoginView: View {
    let instance: Instance
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var dataStore = WKWebsiteDataStore.nonPersistent()
    @State private var finishing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ServerLoginPage(instance: instance, dataStore: dataStore)
                .navigationTitle(instance.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(localized("Cancel", "取消")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(localized("Finish Sign In", "完成登录")) { Task { await finish() } }.disabled(finishing)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Text(localized("Sign in on your server, then tap Finish Sign In.", "请在服务器页面登录，然后点击“完成登录”。")).font(.caption).padding().background(.bar)
                }
                .alert(localized("Session Not Ready", "会话尚未就绪"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button(localized("OK", "好"), role: .cancel) {}
                } message: { Text(error ?? "") }
        }
    }

    private func finish() async {
        guard !finishing else { return }
        finishing = true
        defer { finishing = false }
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        guard store.selectedID == instance.id, let host = instance.baseURL.host?.lowercased() else { return }
        let serverCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }
        HTTPCookieStorage.shared.setCookies(serverCookies, for: instance.baseURL, mainDocumentURL: instance.baseURL)
        do { try await store.acceptBrowserSession(for: instance); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct ServerLoginPage: UIViewRepresentable {
    let instance: Instance
    let dataStore: WKWebsiteDataStore
    func makeCoordinator() -> Coordinator { Coordinator(instance: instance) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: instance.baseURL))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let instance: Instance
        init(instance: Instance) { self.instance = instance }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url,
                  url.user == nil, url.password == nil else { return .cancel }
            if url.scheme == "https" { return .allow }
            if instance.allowsInsecureHTTP, url.scheme == "http", url.host == instance.baseURL.host, url.port == instance.baseURL.port { return .allow }
            return .cancel
        }
    }
}
