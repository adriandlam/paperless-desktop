import FileProvider
import PaperlessCore
import ServiceManagement
import SwiftUI

let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier("paperless"), displayName: "Paperless")

@main
struct PaperlessDesktopApp: App {
    init() {
        // ponytail: polls every 5 minutes while the app runs; Paperless has no push to listen to
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in refresh() }
        refresh()
    }

    var body: some Scene {
        MenuBarExtra("Paperless", systemImage: "doc.text.magnifyingglass") { MenuContent() }
        Window("Paperless Desktop", id: "settings") { SettingsView() }
            .windowResizability(.contentSize)
            .defaultLaunchBehavior(Config.load() == nil ? .presented : .suppressed)
    }
}

/// Tells the Finder extension to check Paperless for changes.
func refresh() {
    NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet) { _ in }
}

@MainActor func openInFinder() async {
    guard let url = try? await NSFileProviderManager(for: domain)?.getUserVisibleURL(for: .rootContainer) else { return }
    // The URL is security-scoped; the sandbox refuses to open it without this.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    NSWorkspace.shared.open(url)
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Refresh Now", action: refresh)
        Button("Open in Finder") { Task { await openInFinder() } }
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        Button("Quit") { NSApp.terminate(nil) }
    }
}

struct SettingsView: View {
    @State private var server = Config.load()?.server.absoluteString ?? ""
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var token = ""
    @State private var status = Config.load() == nil ? "Not connected" : "Connected"
    @State private var offline = Config.load()?.offline ?? false

    var body: some View {
        Form {
            TextField("Server", text: $server, prompt: Text("https://paperless.example.com"))
            TextField("Username", text: $username)
            SecureField("Password", text: $password)
            TextField("2FA code", text: $code, prompt: Text("only if your account has one"))
            Toggle("Keep all documents downloaded for offline use", isOn: $offline)
                .onChange(of: offline) {
                    guard var config = Config.load() else { return }
                    config.offline = offline
                    try? config.save()
                    refresh()
                }
            DisclosureGroup("Use an API token instead") {
                SecureField("API token", text: $token)
                Text("In Paperless: My Profile → API Auth Token").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Connect") { Task { await connect() } }.keyboardShortcut(.defaultAction)
                Button("Disconnect") { Task { await disconnect() } }
                Spacer()
                Text(status).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 440)
    }

    private func connect() async {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
            status = "Invalid server URL"
            return
        }
        status = "Checking…"
        do {
            // Only the token is saved, in the keychain; the password is used once, here.
            let key = token.isEmpty
                ? try await Client.token(server: url, username: username, password: password, code: code)
                : token.trimmingCharacters(in: .whitespaces)
            try await Client(server: url, token: key).check()
            password = ""
            code = ""
            try Token.save(key)
            try Config(server: url, offline: offline).save()
            try await NSFileProviderManager.add(domain)
            try? SMAppService.mainApp.register()  // keep refreshing after a reboot
            refresh()
            status = "Connected"
            await openInFinder()
        } catch APIError.rejected(let message) {
            status = message
        } catch APIError.unauthorized {
            status = "Token rejected"
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func disconnect() async {
        try? await NSFileProviderManager.remove(domain)
        Config.delete()
        status = "Not connected"
    }
}
