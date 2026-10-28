import FileProvider
import PaperlessCore
import ServiceManagement
import SwiftUI

let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier("paperless"), displayName: "Paperless")

@main
struct PaperlessDesktopApp: App {
    init() {
        scheduleSync()
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

private var syncTimer: Timer?

/// Polls at the interval picked in Settings (seconds; 0 is manual only). Paperless has no push to listen to.
func scheduleSync() {
    syncTimer?.invalidate()
    let interval = UserDefaults.standard.object(forKey: "syncInterval") as? Double ?? 300
    syncTimer = interval > 0 ? Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in refresh() } : nil
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
    @State private var status = Config.load() == nil ? "Not connected" : "Connected"
    @State private var online: Bool?  // whether the last check worked; nil before one
    @State private var checking = false
    @State private var offline = Config.load()?.offline ?? false
    @AppStorage("syncInterval") private var syncInterval = 300.0
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $server, prompt: Text("https://paperless.example.com"))
                Picker("Authentication", selection: $useToken) {
                    Text("Password").tag(false)
                    Text("API token").tag(true)
                }
                // Once connected, the dots stand for the saved token; leaving the field empty keeps it.
                if useToken {
                    SecureField("API token", text: $token, prompt: Text(connected ? "••••••••••••" : "From My Profile in Paperless"))
                } else {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password, prompt: Text(connected ? "••••••••" : ""))
                    TextField("2FA code", text: $code, prompt: Text("Optional"))
                }
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        // The spinner takes the dot's place, so nothing moves while checking.
                        ZStack {
                            Image(systemName: "circle.fill").font(.system(size: 8))
                                .foregroundStyle(online == nil ? .gray : online! ? .green : .red)
                                .opacity(checking ? 0 : 1)
                            if checking { ProgressView().controlSize(.mini) }
                        }
                        .frame(width: 12, height: 12)
                        Text(status).lineLimit(1).help(status)
                    }
                }
                HStack {
                    Spacer()
                    Button("Test Connection") { Task { await check() } }
                    Button("Save") { Task { await save() } }.keyboardShortcut(.defaultAction)
                }
                .disabled(checking)
            } header: {
                Text("Paperless Server")
            } footer: {
                Text("Your password is used once, to get an API token that's kept in the Keychain.")
            }
            Section("Sync") {
                Toggle(isOn: $offline) {
                    Text("Make all documents available offline")
                    Text("By default, documents are downloaded when you open them.")
                }
                .onChange(of: offline) {
                    guard var config = Config.load() else { return }
                    config.offline = offline
                    try? config.save()
                    refresh()
                }
                // Mail's "Check for new messages" choices.
                Picker("Check for changes", selection: $syncInterval) {
                    Text("Every minute").tag(60.0)
                    Text("Every 5 minutes").tag(300.0)
                    Text("Every 15 minutes").tag(900.0)
                    Text("Every 30 minutes").tag(1800.0)
                    Text("Every hour").tag(3600.0)
                    Text("Manually").tag(0.0)
                }
                .onChange(of: syncInterval) { scheduleSync() }
            }
            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) {
                        try? openAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            } header: {
                Text("System")
            } footer: {
                // Apart from Save, like Sign Out… at the bottom of Apple Account.
                if connected {
                    HStack {
                        Button("Disconnect…") { confirmDisconnect = true }
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
        }
        .formStyle(.grouped)
        // Fixed, like System Settings, so switching Authentication doesn't resize the window.
        .frame(width: 460, height: 640)
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .task { if connected { await check() } }
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
    private func check() async -> (URL, String)? {
        checking = true
        defer { checking = false }
        do {
            let (url, key) = try await credentials()
            username = try await Client(server: url, token: key).username()
            online = true
            status = "Connected"
            return (url, key)
        } catch {
            online = false
            status = reason(error)
            return nil
        }
    }

    private func save() async {
        guard let (url, key) = await check() else { return }
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
        status = "Connected"
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
