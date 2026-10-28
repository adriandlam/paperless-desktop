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

/// "today at 11:40 AM", like Time Machine's "Latest Backup".
private let syncTime = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    f.formattingContext = .middleOfSentence
    return f
}()

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    // Written by the extension; @AppStorage redraws the menu when it changes.
    @AppStorage("lastSync", store: LastSync.defaults) private var lastSync = 0.0
    @AppStorage("lastSyncError", store: LastSync.defaults) private var syncError: String?

    var body: some View {
        Text("Paperless Desktop \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
        Text(lastSynced())
        Button("Sync Now", action: refresh)
        Divider()
        Button("Open in Finder") { Task { await openInFinder() } }
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

    private func lastSynced() -> String {
        if let syncError { return "Sync failed: \(syncError)" }
        guard lastSync > 0 else { return "Not synced yet" }
        return "Last synced " + syncTime.string(from: Date(timeIntervalSince1970: lastSync))
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
    @State private var status = ""
    @State private var online: Bool?  // whether the last check worked; nil while checking or before one
    @State private var offline = Config.load()?.offline ?? false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $server, prompt: Text("https://paperless.example.com"))
                Picker("Sign in with", selection: $useToken) {
                    Text("Password").tag(false)
                    Text("API token").tag(true)
                }
                .pickerStyle(.segmented)
                // Once connected, leaving these empty keeps the saved token.
                if useToken {
                    SecureField(
                        "API token", text: $token, prompt: Text(connected ? "Unchanged" : "Paperless → My Profile → API Auth Token"))
                } else {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password, prompt: Text(connected ? "Unchanged" : ""))
                    TextField("2FA code", text: $code, prompt: Text("If your account has one"))
                }
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 8))
                            .foregroundStyle(online == nil ? .gray : online! ? .green : .red)
                        Text(status)
                    }
                }
                HStack {
                    if connected { Button("Disconnect…") { confirmDisconnect = true } }
                    Spacer()
                    Button("Test Connection") { Task { await test() } }
                    Button("Save") { Task { await save() } }.keyboardShortcut(.defaultAction)
                }
            } header: {
                Text("Paperless Server")
            } footer: {
                Text("Your password is used once, to get an API token that's kept in the Keychain.")
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
        .task {
            guard connected else { return status = "Not connected" }
            await check { "Connected as \($0)" }
        }
        .confirmationDialog("Disconnect from Paperless?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { Task { await disconnect() } }
        } message: {
            Text("Paperless is removed from Finder, with any offline copies. Nothing changes in Paperless.")
        }
    }

    /// The server and token in the form: new credentials if any were entered, otherwise the saved token.
    private func credentials() async throws -> (URL, String) {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
            throw APIError.rejected("Invalid server URL")
        }
        if useToken, !token.isEmpty { return (url, token.trimmingCharacters(in: .whitespaces)) }
        // Only the token is saved, in the keychain; the password is used once, here.
        if !useToken, !password.isEmpty {
            return (url, try await Client.token(server: url, username: username, password: password, code: code))
        }
        guard connected, let saved = Token.load() else { throw APIError.rejected(useToken ? "Enter an API token" : "Enter your password") }
        return (url, saved)
    }

    /// Signs in with the form's credentials and shows the result; returns them if it worked.
    @discardableResult
    private func check(_ success: (String) -> String) async -> (URL, String)? {
        online = nil
        status = "Checking…"
        do {
            let (url, key) = try await credentials()
            username = try await Client(server: url, token: key).username()
            online = true
            status = success(username)
            return (url, key)
        } catch {
            online = false
            status = reason(error)
            return nil
        }
    }

    private func test() async {
        await check { "Works, signed in as \($0)" }
    }

    private func save() async {
        guard let (url, key) = await check({ "Connected as \($0)" }) else { return }
        let previous = Config.load()?.server
        do {
            // Another server's documents shouldn't stay in Finder.
            if let previous, previous != url { await disconnect() }
            try Token.save(key)
            try Config(server: url, offline: offline).save()
            try await NSFileProviderManager.add(domain)
        } catch {
            online = false
            status = reason(error)
            return
        }
        if previous == nil { openAtLogin = true }  // keep syncing after a reboot
        password = ""
        code = ""
        token = ""
        connected = true
        online = true
        status = "Connected as \(username)"
        refresh()
        if previous != url { await openInFinder() }
    }

    private func disconnect() async {
        try? await NSFileProviderManager.remove(domain)
        Config.delete()
        connected = false
        online = nil
        status = "Not connected"
    }
}
