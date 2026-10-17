import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct SpotifyPlaylist: Decodable, Identifiable {
    let id: String
    let name: String
    let external_urls: [String: String]
}

private struct SpotifyPage: Decodable { let items: [SpotifyPlaylist]; let next: String? }
private struct SpotifyToken: Codable {
    var access_token: String
    var refresh_token: String?
    var expires_in: Double
    var expiresAt: Date?
}

private enum SpotifyFailure: LocalizedError {
    case configuration, callback, random, keychain, http(Int, String)
    var errorDescription: String? {
        switch self {
        case .configuration: "Configure a Spotify client ID and your associated HTTPS callback domain in Xcode first. See Docs/INTEGRATIONS.md."
        case .callback: "The sign-in callback was invalid or did not match this session."
        case .random: "Secure random generation failed. Try signing in again."
        case .keychain: "Spotify credentials could not be saved securely."
        case .http(let status, let detail): "Spotify returned \(status). \(detail)"
        }
    }
}

@MainActor
final class SpotifyClient: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var playlists: [SpotifyPlaylist] = []
    @Published var message: String?
    private var auth: ASWebAuthenticationSession?
    private var token: SpotifyToken?
    private var nextPage: String?
    private var epoch = UUID()
    private var clientID: String { Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? "" }
    private var callbackHost: String { Bundle.main.object(forInfoDictionaryKey: "SpotifyCallbackHost") as? String ?? "" }
    private var redirect: String { "https://\(callbackHost)/spotify/callback" }
    var configured: Bool { !clientID.isEmpty && !clientID.contains("YOUR_") && !callbackHost.isEmpty && !callbackHost.contains("example.invalid") }
    var hasMore: Bool { nextPage != nil }
    private var keychainQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.sonority.spotify", kSecAttrAccount as String: "oauth"] }

    override init() {
        super.init()
        var query = keychainQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let stored = try? JSONDecoder().decode(SpotifyToken.self, from: data) { token = stored; connected = true }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SpotifyFailure.random }
        return base64URL(Data(bytes))
    }
    private func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    func connect() {
        guard !busy else { return }
        guard configured else { message = SpotifyFailure.configuration.localizedDescription; return }
        do {
            let verifier = try random(), state = try random()
            let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
            var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: redirect), URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "scope", value: "playlist-read-private playlist-read-collaborative")
            ]
            busy = true; epoch = UUID(); let operation = epoch
            auth = ASWebAuthenticationSession(url: components.url!, callback: .https(host: callbackHost, path: "/spotify/callback")) { [weak self] url, error in
                Task { @MainActor in
                    guard let self, self.epoch == operation else { return }
                    defer { if self.epoch == operation { self.busy = false; self.auth = nil } }
                    do {
                        if let error { throw error }
                        guard let url, url.scheme == "https", url.host == self.callbackHost, url.path == "/spotify/callback",
                              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                              items.first(where: { $0.name == "state" })?.value == state,
                              let code = items.first(where: { $0.name == "code" })?.value else { throw SpotifyFailure.callback }
                        let value = try await self.requestToken(["grant_type": "authorization_code", "code": code, "redirect_uri": self.redirect, "code_verifier": verifier])
                        guard self.epoch == operation else { return }
                        try self.save(value)
                    } catch { self.message = error.localizedDescription }
                }
            }
            auth?.presentationContextProvider = self
            auth?.prefersEphemeralWebBrowserSession = true
            if auth?.start() != true { busy = false; auth = nil; message = "The sign-in window could not open." }
        } catch { message = error.localizedDescription }
    }
    private func requestToken(_ values: [String: String]) async throws -> SpotifyToken {
        var values = values; values["client_id"] = clientID
        var form = URLComponents(); form.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        var value = try JSONDecoder().decode(SpotifyToken.self, from: data)
        value.expiresAt = Date().addingTimeInterval(value.expires_in - 60)
        return value
    }
    private func save(_ value: SpotifyToken) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery; query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw SpotifyFailure.keychain }
        } else if status != errSecSuccess { throw SpotifyFailure.keychain }
        token = value; connected = true
    }
    private func accessToken() async throws -> String {
        guard let token else { throw SpotifyFailure.callback }
        if (token.expiresAt ?? .distantPast) > Date() { return token.access_token }
        guard let refresh = token.refresh_token else { throw SpotifyFailure.callback }
        let operation = epoch
        var value = try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh])
        guard operation == epoch else { throw CancellationError() }
        if value.refresh_token == nil { value.refresh_token = refresh }
        try save(value); return value.access_token
    }
    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw SpotifyFailure.callback }
        guard (200..<300).contains(http.statusCode) else {
            var detail = "Please try again."
            if http.statusCode == 403 { detail = "Your account or developer app may not have access to this capability." }
            if http.statusCode == 401 { detail = "Reconnect your Spotify account." }
            if http.statusCode == 429 { detail = "Rate limit reached. Wait \(http.value(forHTTPHeaderField: "Retry-After") ?? "a few") seconds before retrying." }
            throw SpotifyFailure.http(http.statusCode, detail)
        }
    }
    func loadPlaylists(more: Bool = false) async {
        guard !busy, connected else { return }
        busy = true; let operation = epoch
        defer { if epoch == operation { busy = false } }
        do {
            let bearer = try await accessToken()
            let path = more ? nextPage : "https://api.spotify.com/v1/me/playlists?limit=20"
            guard let path, let url = URL(string: path), url.scheme == "https", url.host == "api.spotify.com" else { return }
            var request = URLRequest(url: url); request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response)
            let page = try JSONDecoder().decode(SpotifyPage.self, from: data)
            guard epoch == operation else { return }
            playlists = more ? playlists + page.items : page.items; nextPage = page.next
        } catch { if epoch == operation { message = error.localizedDescription } }
    }
    func disconnect() {
        epoch = UUID(); auth?.cancel(); auth = nil
        SecItemDelete(keychainQuery as CFDictionary); token = nil; connected = false; playlists = []; nextPage = nil; busy = false
    }
}

struct SpotifyView: View {
    @EnvironmentObject private var spotify: SpotifyClient
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SectionHeading(eyebrow: "Spotify connection", title: "Another door to your music.", subtitle: "Your playlists, through Spotify’s official Web API.")
                VStack(alignment: .leading, spacing: 18) {
                    Label(spotify.connected ? "Connected to Spotify" : "Connect your Spotify account", systemImage: "antenna.radiowaves.left.and.right").font(.title2)
                    Text("Browse your playlists and open them in Spotify. Audio playback stays in Spotify; Sonority’s EQ, lyrics timeline, and local listening statistics apply to imported music.").foregroundStyle(.secondary)
                    Text("Developer access is subject to Spotify’s current quota, account, and user allowlist rules. An approved client ID and associated HTTPS callback domain are required.").font(.caption).foregroundStyle(.secondary)
                    if spotify.connected {
                        HStack { Button("Load playlists") { Task { await spotify.loadPlaylists() } }.disabled(spotify.busy); Spacer(); Button("Disconnect", role: .destructive) { spotify.disconnect() } }
                    } else { Button(spotify.configured ? "Connect Spotify" : "Spotify setup required") { spotify.connect() }.buttonStyle(.borderedProminent).disabled(spotify.busy) }
                    if spotify.busy { ProgressView() }
                }.panel()
                ForEach(spotify.playlists) { playlist in
                    Button {
                        guard let raw = playlist.external_urls["spotify"], let url = URL(string: raw), url.scheme == "https", url.host == "open.spotify.com" else { return }
                        player.pause(); openURL(url)
                    } label: { HStack { Image(systemName: "music.note.list"); Text(playlist.name); Spacer(); Text("Open in Spotify").font(.caption); Image(systemName: "arrow.up.right") }.padding(20).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18)) }
                }
                if spotify.hasMore { Button("Load more playlists") { Task { await spotify.loadPlaylists(more: true) } }.disabled(spotify.busy) }
                Link("Spotify Developer documentation", destination: URL(string: "https://developer.spotify.com/documentation/web-api")!).font(.caption)
            }.padding(28).frame(maxWidth: 1000)
        }.alert("Spotify", isPresented: Binding(get: { spotify.message != nil }, set: { if !$0 { spotify.message = nil } })) { Button("OK") { spotify.message = nil } } message: { Text(spotify.message ?? "") }
    }
}
