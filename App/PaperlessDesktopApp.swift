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
        MenuBarExtra("Paperless", systemImage: "leaf.fill") { MenuContent() }
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
        Text("Paperless Desktop \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
        Divider()
        // Opening Finder also checks Paperless for changes, so it doubles as Refresh.
        Button("Open in Finder") {
            refresh()
            Task { await openInFinder() }
        }
        Button("Settings…", systemImage: "gearshape") {
            // A menu bar app can't take focus from the frontmost app, so act as a regular one while Settings is open.
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "settings")
            NSApp.activate()
            // activate() is only a request; raise the window even if it's turned down.
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) else { return }
                window.orderFrontRegardless()
                window.makeKey()
            }
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Paperless Desktop") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @State private var server = Config.load()?.server.absoluteString ?? ""
    @State private var connected = Config.load() != nil
    @State private var useToken = false
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var token = ""
    @State private var status = ""  // progress, or why connecting failed
    @State private var online: Bool?  // whether the saved server and token work; nil while checking
    @State private var offline = Config.load()?.offline ?? false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section {
                if connected {
                    LabeledContent("Server", value: server)
                    LabeledContent("Username", value: username)
                    // The password isn't kept, only the token.
                    LabeledContent("API token", value: "••••••••••••")
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill").font(.system(size: 8))
                                .foregroundStyle(online == nil ? .gray : online! ? .green : .red)
                            Text(online == nil ? "Checking…" : online! ? "Connected" : status)
                        }
                    }
                } else {
                    TextField("Server URL", text: $server, prompt: Text("https://paperless.example.com"))
                    Picker("Sign in with", selection: $useToken) {
                        Text("Password").tag(false)
                        Text("API token").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if useToken {
                        SecureField("API token", text: $token, prompt: Text("Paperless → My Profile → API Auth Token"))
                    } else {
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                        TextField("2FA code", text: $code, prompt: Text("If your account has one"))
                    }
                }
                HStack {
                    if !connected { Text(status).foregroundStyle(.secondary) }
                    Spacer()
                    if connected {
                        Button("Disconnect…") { confirmDisconnect = true }
                    } else {
                        Button("Connect") { Task { await connect() } }.keyboardShortcut(.defaultAction)
                    }
                }
            } header: {
                Text("Paperless Server")
            } footer: {
                if !connected { Text("Your password is used once, to get an API token that's kept in the Keychain.") }
            }
            Section {
                Toggle("Keep all documents downloaded", isOn: $offline)
                    .onChange(of: offline) {
                        guard var config = Config.load() else { return }
                        config.offline = offline
                        try? config.save()
                        refresh()
                    }
            } header: {
                Text("Finder")
            } footer: {
                Text("Otherwise a document downloads when you open it. Right-click a folder → Keep Downloaded for just that folder.")
            }
            Section("System") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) {
                        try? openAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .task(id: connected) {
            guard connected, let client = Config.load()?.client else { return }
            online = nil
            do {
                username = try await client.username()
                online = true
            } catch APIError.unauthorized {
                status = "Token rejected; disconnect and sign in again"
                online = false
            } catch {
                status = "Can't reach the server"
                online = false
            }
        }
        .confirmationDialog("Disconnect from Paperless?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { Task { await disconnect() } }
        } message: {
            Text("Paperless is removed from Finder, with any offline copies. Nothing changes in Paperless.")
        }
    }

    private func connect() async {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
            status = "Invalid server URL"
            return
        }
        status = "Checking…"
        do {
            // Only the token is saved, in the keychain; the password is used once, here.
            let key =
                token.isEmpty
                ? try await Client.token(server: url, username: username, password: password, code: code)
                : token.trimmingCharacters(in: .whitespaces)
            _ = try await Client(server: url, token: key).username()
            password = ""
            code = ""
            try Token.save(key)
            try Config(server: url, offline: offline).save()
            try await NSFileProviderManager.add(domain)
            try? SMAppService.mainApp.register()  // keep refreshing after a reboot
            refresh()
            openAtLogin = true
            connected = true
            status = ""
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
        connected = false
    }
}
