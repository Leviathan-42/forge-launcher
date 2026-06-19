import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct ForgeNativeApp: App {
    @NSApplicationDelegateAdaptor(ForgeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(.dark)
                .containerBackground(.clear, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

struct ContentView: View {
    @StateObject private var store = ForgeStore()
    @State private var searchText = ""
    @State private var isDropTarget = false
    @State private var editingApp: BottleAppItem?

    private var filteredApps: [BottleAppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.apps }
        return store.apps.filter { app in
            app.name.localizedCaseInsensitiveContains(query)
                || app.path.localizedCaseInsensitiveContains(query)
                || app.kind.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            LiquidBackground()

            if let bottle = store.bottle {
                appShell(bottle)
            } else {
                emptyState
                    .padding(28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Forge", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .sheet(item: $editingApp) { app in
            Group {
                if let bottle = store.bottle {
                    GameProfileEditorSheet(
                        app: app,
                        profile: store.gameProfile(for: app),
                        effectiveBackend: store.effectiveBackend(for: app, bottle: bottle),
                        canReset: store.gameProfileCanReset(app),
                        save: { backend, launchArgs, env, notes in
                            store.updateGameProfile(
                                app,
                                backendOverride: backend,
                                launchArgs: launchArgs,
                                env: env,
                                notes: notes
                            )
                            editingApp = nil
                        },
                        reset: {
                            store.resetGameProfile(app)
                            editingApp = nil
                        },
                        cancel: {
                            editingApp = nil
                        }
                    )
                } else {
                    EmptyView()
                }
            }
            .preferredColorScheme(.dark)
        }
        .task { store.reload() }
    }

    private func appShell(_ bottle: BottleEntry) -> some View {
        HStack(spacing: 16) {
            sidebar(bottle)
                .frame(width: 244)

            VStack(spacing: 14) {
                topBar
                runtimePanel(bottle)
                appsPanel(bottle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 34)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func sidebar(_ bottle: BottleEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.20), radius: 10, y: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Forge")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Windows bottles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Bottle")
                if store.bottles.count > 1 {
                    BottlePickerCard(
                        bottles: store.bottles,
                        selection: Binding(
                            get: { bottle.prefixPath },
                            set: { store.selectBottle(prefixPath: $0) }
                        )
                    )
                }
                BottleCard(bottle: bottle, statusText: store.statusText, isReady: store.prefixExists)
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Status")
                StatusLine(icon: "shippingbox.fill", title: store.prefixExists ? "Bottle ready" : "Bottle missing", value: bottle.name)
                StatusLine(icon: "app.badge.fill", title: "Launchable apps", value: "\(store.apps.count)")
                BackendPickerCard(
                    selection: Binding(
                        get: { bottle.graphicsBackend ?? store.profile(for: bottle).defaultBackend },
                        set: { store.setBackend($0) }
                    )
                )
            }

            HudToggleCard(
                isOn: Binding(
                    get: { store.config.globalHud },
                    set: { store.setMetalHud($0) }
                )
            )

            Spacer()

            Button {
                store.reload()
            } label: {
                Label("Refresh Library", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.14)))
        }
        .padding(16)
        .liquidGlass(cornerRadius: 24, opacity: 0.22)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Library")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Launch Windows apps from your Forge bottle.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isLaunching {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Launching…")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.68))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .liquidGlass(cornerRadius: 20, opacity: 0.24)
            }

            GlassSearchField(text: $searchText)
                .frame(width: 285)
        }
    }

    private func runtimePanel(_ bottle: BottleEntry) -> some View {
        HStack(spacing: 14) {
            DropExeCard(
                isTargeted: isDropTarget,
                isDisabled: store.isLaunching,
                isRunning: store.runningAppPath != nil,
                selectAction: { store.selectExe() },
                stopAction: { store.stopRunningApp() }
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
                handleExeDrop(providers)
            }

            RuntimeActionCard(
                icon: "folder.fill",
                title: "Bottle Folder",
                subtitle: bottle.prefixPath,
                primaryTitle: "Reveal",
                isDisabled: false,
                primaryAction: { store.revealBottle() }
            )

            RuntimeActionCard(
                icon: "arrow.clockwise.circle.fill",
                title: "Rescan",
                subtitle: "Refresh installed launchers and EXEs.",
                primaryTitle: "Refresh",
                isDisabled: false,
                primaryAction: { store.reload() }
            )
        }
    }

    private func handleExeDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let raw = item as? URL {
                url = raw
            } else {
                url = nil
            }

            guard let url else { return }
            Task { @MainActor in
                store.runExe(at: url)
            }
        }
        return true
    }

    private func appsPanel(_ bottle: BottleEntry) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Apps")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                Text("\(filteredApps.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
                Spacer()
                Text(backendText(for: bottle))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }

            if filteredApps.isEmpty {
                emptyAppsCard
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredApps) { app in
                            let profile = store.gameProfile(for: app)
                            LiquidAppRow(
                                app: app,
                                backend: store.effectiveBackend(for: app, bottle: bottle),
                                backendIsAppSpecific: store.gameProfileIsAppSpecific(for: app),
                                profileCanReset: store.gameProfileCanReset(app),
                                launchArgs: profile.launchArgs,
                                envKeys: profile.env.keys.sorted(),
                                notes: profile.notes,
                                hudText: store.config.globalHud ? "Metal HUD" : "Off",
                                isLaunching: store.isLaunching,
                                isRunning: store.runningAppPath == app.path,
                                setBackend: { store.setGameBackend(app, backend: $0) },
                                resetProfile: { store.resetGameProfile(app) },
                                editProfile: { editingApp = app },
                                launch: {
                                    if app.steamAppId != nil {
                                        store.launchThroughSteam(app)
                                    } else {
                                        store.launch(app)
                                    }
                                },
                                launchThroughSteam: nil,
                                stop: {
                                    store.stopRunningApp()
                                }
                            )
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(cornerRadius: 24, opacity: 0.20)
    }

    private var emptyAppsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.34))
            Text(searchText.isEmpty ? "No apps found yet" : "No apps match your search")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text(searchText.isEmpty ? "Install Steam, then install games or launchers inside this bottle." : "Try another title, path, or launcher type.")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white.opacity(0.36))
            Text("No Forge bottle configured")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Forge will look in Application Support for config.json and bottles.json.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            Button("Reload") { store.reload() }
                .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.18), foreground: .white.opacity(0.94)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .liquidGlass(cornerRadius: 34, opacity: 0.30)
    }

    private func backendText(for bottle: BottleEntry) -> String {
        let backend = bottle.graphicsBackend
            ?? store.profiles.first(where: { $0.id == bottle.runtimeProfileId })?.defaultBackend
            ?? .dxvkVkd3d
        return "Default: \(backend.displayName)"
    }
}

// MARK: - Store

@MainActor
final class ForgeStore: ObservableObject {
    @Published var config = AppConfig.defaults
    @Published var profiles: [RuntimeProfile] = []
    @Published var bottles: [BottleEntry] = []
    @Published var bottle: BottleEntry?
    @Published var gameProfiles: [String: GameCompatibilityProfile] = [:]
    @Published var apps: [BottleAppItem] = []
    @Published var steamPath: String?
    @Published var prefixExists = false
    @Published var isLaunching = false
    @Published var runningAppPath: String?
    @Published var alertMessage: String?

    var statusText: String {
        guard bottle != nil else { return "Missing" }
        if !prefixExists { return "Bottle missing" }
        return "Bottle ready"
    }

    func reload() {
        do {
            let support = Self.appSupportDir()
            config = try Self.loadConfig(from: support)
            profiles = try Self.loadProfiles(from: support, config: config)
            bottles = try Self.loadBottles(from: support, config: config)
            gameProfiles = try Self.loadGameProfiles(from: support)
            bottle = Self.selectBottle(from: bottles, config: config)
            refreshBottleState()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func selectBottle(prefixPath: String) {
        guard let selected = bottles.first(where: { $0.prefixPath == prefixPath }) else { return }
        bottle = selected
        config.defaultPrefix = selected.prefixPath
        do {
            try Self.saveConfig(config, to: Self.appSupportDir())
        } catch {
            alertMessage = "Bottle changed for this session, but Forge could not save config.json: \(error.localizedDescription)"
        }
        refreshBottleState()
    }

    func openSteam() {
        guard let steamPath else {
            alertMessage = "Windows Steam is not installed in this bottle yet."
            return
        }
        launch(BottleAppItem(name: "Steam", path: steamPath, kind: "launcher"))
    }

    func installSteam() {
        guard let bottle else { return }
        isLaunching = true
        Task.detached(priority: .userInitiated) {
            do {
                let installer = try Self.downloadSteamInstaller()
                try await Self.spawn(
                    exePath: installer.path,
                    bottle: bottle,
                    config: await MainActor.run { self.config },
                    profile: await MainActor.run { self.profile(for: bottle) },
                    extraArgs: [],
                    forceSteamMode: false,
                    steamAppId: nil,
                    backendOverride: nil,
                    gameEnvOverrides: [:],
                    steamSafeMode: true
                )
                await MainActor.run {
                    self.isLaunching = false
                    self.alertMessage = "Steam installer launched. Finish the installer, then press Refresh."
                }
            } catch {
                await MainActor.run {
                    self.isLaunching = false
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func selectExe() {
        let panel = NSOpenPanel()
        panel.title = "Select Windows EXE"
        panel.message = "Choose a Windows .exe to run in the selected Forge bottle."
        if let exeType = UTType(filenameExtension: "exe") {
            panel.allowedContentTypes = [exeType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            runExe(at: url)
        }
    }

    func runExe(at url: URL) {
        guard url.pathExtension.caseInsensitiveCompare("exe") == .orderedSame else {
            alertMessage = "Forge can only run Windows .exe files."
            return
        }
        launch(BottleAppItem(name: Self.displayName(for: url.path), path: url.path, kind: "app"))
    }

    func gameProfile(for app: BottleAppItem) -> GameCompatibilityProfile {
        let key = Self.gameProfileKey(for: app)
        if let profile = gameProfiles[key] { return profile }
        return GameCompatibilityProfile(id: key, displayName: app.name, backendOverride: nil, launchArgs: [], env: [:], notes: nil)
    }

    func gameProfileIsAppSpecific(for app: BottleAppItem) -> Bool {
        let profile = gameProfile(for: app)
        return profile.backendOverride != nil || !profile.launchArgs.isEmpty || !profile.env.isEmpty || profile.notes != nil
    }

    func gameProfileCanReset(_ app: BottleAppItem) -> Bool {
        Self.gameProfileCanReset(gameProfiles, key: Self.gameProfileKey(for: app))
    }

    func effectiveBackend(for app: BottleAppItem, bottle: BottleEntry) -> GraphicsBackend {
        gameProfile(for: app).backendOverride ?? bottle.graphicsBackend ?? profile(for: bottle).defaultBackend
    }

    func launchArgs(for app: BottleAppItem) -> [String] {
        let key = Self.gameProfileKey(for: app)
        if let profile = gameProfiles[key] {
            return profile.launchArgs
        }
        return app.steamAppId == nil ? [] : ["-screen-fullscreen", "1"]
    }

    func gameEnv(for app: BottleAppItem) -> [String: String] {
        gameProfile(for: app).env
    }

    func setGameBackend(_ app: BottleAppItem, backend: GraphicsBackend) {
        var profile = gameProfile(for: app)
        profile.backendOverride = backend
        saveGameProfile(profile)
    }

    func updateGameProfile(
        _ app: BottleAppItem,
        backendOverride: GraphicsBackend?,
        launchArgs: [String],
        env: [String: String],
        notes: String?
    ) {
        let key = Self.gameProfileKey(for: app)
        var profile = GameCompatibilityProfile(
            id: key,
            displayName: app.name,
            backendOverride: backendOverride,
            launchArgs: launchArgs,
            env: env,
            notes: notes
        )

        if let existing = gameProfiles[key] {
            profile.displayName = existing.displayName.isEmpty ? app.name : existing.displayName
        }

        if profile.backendOverride == nil,
           profile.launchArgs.isEmpty,
           profile.env.isEmpty,
           profile.notes == nil,
           Self.seededGameProfile(forKey: key) == nil {
            gameProfiles.removeValue(forKey: key)
            persistGameProfiles()
            return
        }

        saveGameProfile(profile)
    }

    func resetGameProfile(_ app: BottleAppItem) {
        gameProfiles = Self.resetGameProfiles(gameProfiles, key: Self.gameProfileKey(for: app))
        persistGameProfiles()
    }

    private func saveGameProfile(_ profile: GameCompatibilityProfile) {
        gameProfiles[profile.id] = profile
        persistGameProfiles()
    }

    private func persistGameProfiles() {
        do {
            try Self.saveGameProfiles(gameProfiles, to: Self.appSupportDir())
        } catch {
            alertMessage = "Compatibility profile changed for this session, but Forge could not save it: \(error.localizedDescription)"
        }
    }

    func launch(_ app: BottleAppItem) {
        launch(app, throughSteam: false)
    }

    func launchThroughSteam(_ app: BottleAppItem) {
        launch(app, throughSteam: true)
    }

    private func launch(_ app: BottleAppItem, throughSteam: Bool) {
        guard let bottle else { return }
        isLaunching = true
        Task.detached(priority: .userInitiated) {
            do {
                let launchConfig = await MainActor.run { self.config }
                let launchProfile = await MainActor.run { self.profile(for: bottle) }
                let appBackend = await MainActor.run { self.effectiveBackend(for: app, bottle: bottle) }
                let appLaunchArgs = await MainActor.run { self.launchArgs(for: app) }
                let appEnv = await MainActor.run { self.gameEnv(for: app) }
                let targetPath: String
                let forceSteamMode: Bool
                let steamAppId: String?
                let extraArgs: [String]

                if throughSteam {
                    guard let appId = app.steamAppId else {
                        throw ForgeError.message("This app is not linked to a Steam manifest.")
                    }
                    guard let steamPath = await MainActor.run(body: { self.steamPath }) else {
                        throw ForgeError.message("Windows Steam is not installed in this bottle yet.")
                    }
                    targetPath = steamPath
                    forceSteamMode = true
                    steamAppId = appId
                    extraArgs = ["-applaunch", appId] + appLaunchArgs
                } else {
                    targetPath = app.path
                    forceSteamMode = app.isSteamClient
                    steamAppId = app.steamAppId
                    extraArgs = appLaunchArgs
                }

                if app.name.caseInsensitiveCompare("PEAK") == .orderedSame
                    || app.name.caseInsensitiveCompare("Against the Storm") == .orderedSame {
                    try? Self.stopWineSession(bottle: bottle, config: launchConfig, profile: launchProfile)
                }

                if throughSteam, appBackend == .d3dMetal {
                    // D3DMetal is still launched directly for Steam games so Steam's
                    // Chromium helpers do not interfere with the game's graphics DLLs.
                    // D3DMetal's PE DLLs and Unix modules must come from the same Wine
                    // build, so this path uses GPTK Wine against the Forge bottle.
                    try await Self.spawn(
                        exePath: app.path,
                        bottle: bottle,
                        config: launchConfig,
                        profile: launchProfile,
                        extraArgs: appLaunchArgs,
                        forceSteamMode: false,
                        steamAppId: steamAppId,
                        backendOverride: .d3dMetal,
                        gameEnvOverrides: appEnv,
                        steamSafeMode: false
                    )
                } else {
                    try await Self.spawn(
                        exePath: targetPath,
                        bottle: bottle,
                        config: launchConfig,
                        profile: launchProfile,
                        extraArgs: extraArgs,
                        forceSteamMode: forceSteamMode,
                        steamAppId: steamAppId,
                        backendOverride: appBackend,
                        gameEnvOverrides: appEnv,
                        // Always keep steam.exe itself in safe UI mode. For Steam-owned
                        // game launches, -applaunch is still passed through while Forge's
                        // FORGE_GAME_* env advertises the selected game backend.
                        steamSafeMode: true
                    )
                }
                await MainActor.run {
                    self.isLaunching = false
                    self.runningAppPath = app.path
                }
            } catch {
                await MainActor.run {
                    self.isLaunching = false
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func stopRunningApp() {
        guard let bottle else { return }
        let profile = profile(for: bottle)
        let config = config
        Task.detached(priority: .userInitiated) {
            do {
                try Self.stopWineSession(bottle: bottle, config: config, profile: profile)
                await MainActor.run {
                    self.runningAppPath = nil
                    self.isLaunching = false
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func revealBottle() {
        guard let bottle else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bottle.prefixPath)])
    }

    func setBackend(_ backend: GraphicsBackend) {
        guard var current = bottle else { return }
        current.graphicsBackend = backend
        bottle = current
        do {
            try Self.saveBottle(current, to: Self.appSupportDir(), config: config)
        } catch {
            alertMessage = "Backend changed for this session, but Forge could not save bottles.json: \(error.localizedDescription)"
        }
    }

    func setMetalHud(_ enabled: Bool) {
        config.globalHud = enabled
        do {
            try Self.saveConfig(config, to: Self.appSupportDir())
            try Self.setMetalHudDefaults(enabled)
        } catch {
            alertMessage = "Metal HUD changed for this session, but Forge could not save config: \(error.localizedDescription)"
        }
    }

    private func refreshBottleState() {
        guard let bottle else {
            apps = []
            steamPath = nil
            prefixExists = false
            return
        }
        prefixExists = FileManager.default.fileExists(atPath: bottle.prefixPath)
        steamPath = Self.findSteam(prefixPath: bottle.prefixPath)
        apps = Self.scanApps(prefixPath: bottle.prefixPath)
    }

    func profile(for bottle: BottleEntry) -> RuntimeProfile {
        profiles.first(where: { $0.id == bottle.runtimeProfileId })
            ?? profiles.first
            ?? RuntimeProfile.defaultProfile(config: config)
    }

    // MARK: Launch

    nonisolated static func spawn(
        exePath: String,
        bottle: BottleEntry,
        config: AppConfig,
        profile: RuntimeProfile,
        extraArgs: [String],
        forceSteamMode: Bool,
        steamAppId: String?,
        backendOverride: GraphicsBackend?,
        gameEnvOverrides: [String: String],
        steamSafeMode: Bool
    ) async throws {
        let configuredWinePath = profile.wine64Path.isEmpty ? config.wine64Path : profile.wine64Path
        let isSteam = forceSteamMode || URL(fileURLWithPath: exePath).lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame
        let gameBackend = backendOverride ?? bottle.graphicsBackend ?? profile.defaultBackend
        let launchBackend: GraphicsBackend = (isSteam && steamSafeMode) ? .wineBuiltin : gameBackend
        let gptkLibPath = profile.gptkLibPath ?? config.gptkLibPath
        var winePath = configuredWinePath
        if launchBackend == .d3dMetal, let gptkWine = gptkWinePath(gptkLibPath: gptkLibPath) {
            // Do not mix GPTK's D3DMetal modules with Forge Wine: Wine's builtin
            // PE DLLs and Unix-side .so modules are ABI-coupled to their Wine build.
            winePath = gptkWine
        }
        let runtimeLibPath = URL(fileURLWithPath: winePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("lib")
            .path
        guard FileManager.default.fileExists(atPath: winePath) else {
            throw ForgeError.message("wine not found at \(winePath)")
        }

        try ensurePrefix(prefixPath: bottle.prefixPath, winePath: winePath)
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        if launchBackend == .d3dMetal {
            env["DYLD_LIBRARY_PATH"] = buildDyldPath(
                gptkLibPath: gptkLibPath,
                existing: dedupePathParts([runtimeLibPath, env["DYLD_LIBRARY_PATH"] ?? ""]).joined(separator: ":")
            )
            env["DYLD_FALLBACK_LIBRARY_PATH"] = dedupePathParts([
                runtimeLibPath,
                "/opt/homebrew/lib",
                "/usr/local/lib",
                env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
            ]).joined(separator: ":")
            if !gptkLibPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                env["DYLD_FRAMEWORK_PATH"] = URL(fileURLWithPath: gptkLibPath).path
            }
        } else {
            // DXVK/VKD3D should use Forge/Homebrew MoltenVK. Do not let GPTK's
            // older external libMoltenVK shadow the Vulkan 1.3+ ICD needed by DXVK.
            env["DYLD_LIBRARY_PATH"] = dedupePathParts([runtimeLibPath, env["DYLD_LIBRARY_PATH"] ?? ""]).joined(separator: ":")
            env["DYLD_FALLBACK_LIBRARY_PATH"] = dedupePathParts([
                runtimeLibPath,
                "/opt/homebrew/lib",
                "/usr/local/lib",
                env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
            ]).joined(separator: ":")
            env.removeValue(forKey: "DYLD_FRAMEWORK_PATH")
        }
        env["WINEDEBUG"] = config.suppressWineDebug ? "fixme-all" : ""
        env["WINEDBG"] = "-all"
        env["GST_DEBUG"] = "1"
        env["MTL_HUD_ENABLED"] = config.globalHud ? "1" : "0"
        env["MTL_HUD_LAYER"] = config.globalHud ? "1" : "0"
        if config.globalHud {
            try? setMetalHudDefaults(true)
        }
        env["WINE_MOUSE_WARP"] = "1"
        env["WINEESYNC"] = "1"
        env["WINEMSYNC"] = "1"
        if let steamAppId {
            env["SteamAppId"] = steamAppId
            env["SteamGameId"] = steamAppId
        }
        if launchBackend == .dxvk || launchBackend == .vkd3d || launchBackend == .dxvkVkd3d {
            configureMoltenVK(profile: profile, config: config, env: &env)
        }

        switch launchBackend {
        case .d3dMetal:
            if let gptkBase = gptkWineLibBase(gptkLibPath: gptkLibPath) {
                let dllPaths = [
                    gptkBase.appendingPathComponent("wine/x86_64-windows").path,
                    gptkBase.appendingPathComponent("wine/x86_64-unix").path,
                    gptkBase.appendingPathComponent("wine/i386-windows").path,
                    gptkBase.appendingPathComponent("wine/x86_32on64-unix").path
                ].filter { FileManager.default.fileExists(atPath: $0) }
                if !dllPaths.isEmpty {
                    env["WINEDLLPATH"] = dedupePathParts(dllPaths + [env["WINEDLLPATH"] ?? ""]).joined(separator: ":")
                }
            }
            try removeStagedD3DMetalDlls(exePath: exePath)
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,d3d12=b;user32=n,b;mscoree,mshtml="
            if let frameworkPath = d3dMetalFrameworkPath(gptkLibPath: gptkLibPath) {
                env["D3DMETAL_FRAMEWORK_PATH"] = frameworkPath
            }
            env["D3DM_MTL4"] = env["D3DM_MTL4"] ?? "0"
            env["D3DM_SUPPORT_DXR"] = env["D3DM_SUPPORT_DXR"] ?? "0"
            env["D3DM_ENABLE_METALFX"] = env["D3DM_ENABLE_METALFX"] ?? "0"
            env["FORGE_D3DMETAL_RUNTIME"] = "gptk-wine-d3dmetal"
        case .dxvk:
            try ensureDXVKInstalled(exePath: exePath, prefixPath: bottle.prefixPath, steamAppId: steamAppId)
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,user32=n,b;mscoree,mshtml="
            env["DXVK_ASYNC"] = "1"
        case .vkd3d:
            env["WINEDLLOVERRIDES"] = "d3d12,dxgi,user32=n,b;mscoree,mshtml="
        case .dxvkVkd3d:
            try ensureDXVKInstalled(exePath: exePath, prefixPath: bottle.prefixPath, steamAppId: steamAppId)
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b;mscoree,mshtml="
            env["DXVK_ASYNC"] = "1"
        case .wineBuiltin:
            try removeStagedD3DMetalDlls(exePath: exePath)
            env["WINEDLLOVERRIDES"] = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            env["WINE_D3D_CONFIG"] = "renderer=gl"
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        case .dxmt:
            try ensureDXMTInstalled(winePath: winePath, prefixPath: bottle.prefixPath)
            try removeStagedD3DMetalDlls(exePath: exePath)
            env["WINEDLLOVERRIDES"] = "dd3d11,d3d11,dxgi,d3d10core=b;user32=n,b;mscoree,mshtml="
            env["DXMT_LOG_LEVEL"] = env["DXMT_LOG_LEVEL"] ?? "info"
            env["DXMT_LOG_PATH"] = env["DXMT_LOG_PATH"] ?? appSupportDir().appendingPathComponent("Logs", isDirectory: true).path
        case .none:
            break
        }

        for (key, value) in config.env { env[key] = value }
        for (key, value) in profile.env { env[key] = value }
        for (key, value) in bottle.envOverrides { env[key] = value }
        for (key, value) in gameEnvOverrides { env[key] = value }

        if (env["WINE_D3D_CONFIG"] ?? "").localizedCaseInsensitiveContains("renderer=vulkan") {
            // WineD3D's Vulkan renderer must not inherit the GL software fallback
            // used for Steam's Chromium UI / older WineD3D fallback launches.
            env.removeValue(forKey: "LIBGL_ALWAYS_SOFTWARE")
        }

        if !isSteam {
            // Steam safe mode intentionally sets this to an impossible value to keep
            // DXVK out of Steam's Chromium helpers. Direct game launches must always
            // clear it or DXVK reports "No adapters found" and Unity games crash.
            env.removeValue(forKey: "DXVK_FILTER_DEVICE_NAME")
        }

        if launchBackend == .dxmt {
            env.removeValue(forKey: "VK_ICD_FILENAMES")
            env.removeValue(forKey: "VK_DRIVER_FILES")
            env.removeValue(forKey: "DXVK_ASYNC")
            env.removeValue(forKey: "DXVK_FILTER_DEVICE_NAME")
        }

        if launchBackend == .d3dMetal {
            // D3DMetal must not inherit Vulkan/DXVK profile settings. If VK_ICD or
            // DXVK variables survive here, Wine can load DXVK instead of GPTK's
            // builtin D3DMetal DLLs and Unity games crash before rendering.
            env.removeValue(forKey: "VK_ICD_FILENAMES")
            env.removeValue(forKey: "VK_DRIVER_FILES")
            env.removeValue(forKey: "DXVK_ASYNC")
            env.removeValue(forKey: "DXVK_FILTER_DEVICE_NAME")
        }

        // This win32u workaround is only for Steam's Chromium helper. Do not let
        // a shell/profile value leak into direct game launches.
        env.removeValue(forKey: "FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP")

        if isSteam && steamSafeMode {
            if gameBackend == .dxvk || gameBackend == .vkd3d || gameBackend == .dxvkVkd3d {
                configureMoltenVK(profile: profile, config: config, env: &env)
            }
            let gameVkIcd = env["VK_ICD_FILENAMES"] ?? ""
            let gameVkDriverFiles = env["VK_DRIVER_FILES"] ?? gameVkIcd
            let preserveWineD3DEnv = gameBackend == .wineBuiltin || gameBackend == .none
            let gameWineD3DConfig = preserveWineD3DEnv ? (env["WINE_D3D_CONFIG"] ?? "") : ""
            let gameLibGLAlwaysSoftware = preserveWineD3DEnv ? (env["LIBGL_ALWAYS_SOFTWARE"] ?? "") : ""
            let gameMetalHudEnabled = config.globalHud ? "1" : "0"
            let gameMetalHudLayer = config.globalHud ? "1" : "0"
            let gameDXVKAsync = (gameBackend == .dxvk || gameBackend == .dxvkVkd3d) ? (env["DXVK_ASYNC"] ?? "1") : ""
            let gameDyldPath = gameBackend == .d3dMetal ? buildDyldPath(
                gptkLibPath: gptkLibPath,
                existing: dedupePathParts([runtimeLibPath, env["DYLD_LIBRARY_PATH"] ?? ""]).joined(separator: ":")
            ) : (env["DYLD_LIBRARY_PATH"] ?? "")
            var gameWineDllPath = ""
            if gameBackend == .d3dMetal, let gptkBase = gptkWineLibBase(gptkLibPath: gptkLibPath) {
                gameWineDllPath = [
                    gptkBase.appendingPathComponent("wine/x86_64-windows").path,
                    gptkBase.appendingPathComponent("wine/x86_64-unix").path,
                    gptkBase.appendingPathComponent("wine/i386-windows").path,
                    gptkBase.appendingPathComponent("wine/x86_32on64-unix").path
                ].filter { FileManager.default.fileExists(atPath: $0) }.joined(separator: ":")
            }
            let gameDllOverrides: String
            switch gameBackend {
            case .d3dMetal:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,d3d12=b;user32=n,b;mscoree,mshtml="
            case .dxvk:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,user32=n,b;mscoree,mshtml="
            case .vkd3d:
                gameDllOverrides = "d3d12,dxgi,user32=n,b;mscoree,mshtml="
            case .dxvkVkd3d:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b;mscoree,mshtml="
            case .wineBuiltin:
                gameDllOverrides = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            case .dxmt:
                gameDllOverrides = "dd3d11,d3d11,dxgi,d3d10core=b;user32=n,b;mscoree,mshtml="
            case .none:
                gameDllOverrides = ""
            }

            // Steam's Chromium UI is stable in this safe backend, but games launched
            // from Steam must not inherit these variables. Forge Wine detects this
            // marker and restores the FORGE_GAME_* values for non-Steam child EXEs.
            env["FORGE_STEAM_SAFE_MODE"] = "1"
            env["FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP"] = "steamwebhelper.exe"
            env["FORGE_GAME_WINEDLLOVERRIDES"] = gameDllOverrides
            env["FORGE_GAME_WINE_D3D_CONFIG"] = gameWineD3DConfig
            env["FORGE_GAME_LIBGL_ALWAYS_SOFTWARE"] = gameLibGLAlwaysSoftware
            env["FORGE_GAME_VK_ICD_FILENAMES"] = gameVkIcd
            env["FORGE_GAME_VK_DRIVER_FILES"] = gameVkDriverFiles
            env["FORGE_GAME_MTL_HUD_ENABLED"] = gameMetalHudEnabled
            env["FORGE_GAME_MTL_HUD_LAYER"] = gameMetalHudLayer
            env["FORGE_GAME_DXVK_ASYNC"] = gameDXVKAsync
            env["FORGE_GAME_DYLD_LIBRARY_PATH"] = gameDyldPath
            env["FORGE_GAME_WINEDLLPATH"] = gameWineDllPath
            env["MOLTENVK_CONFIG_LOG_LEVEL"] = env["MOLTENVK_CONFIG_LOG_LEVEL"] ?? "0"

            // Do not put D3D/Vulkan-disabling overrides in the Unix environment:
            // Steam-launched games inherit that Unix env before Wine's Windows env
            // block exists. Steam UI safety is handled by CEF flags and Wine
            // AppDefaults; the process env stays compatible with the child game.
            env["WINEDLLOVERRIDES"] = "user32=n,b;mscoree,mshtml="
            env.removeValue(forKey: "DXVK_FILTER_DEVICE_NAME")
            env["MTL_HUD_ENABLED"] = "0"
            env["MTL_HUD_LAYER"] = "0"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: winePath)
        // Launch the PE executable directly instead of through `wine start /unix`.
        // `start` detaches through explorer and can lose/flatten macOS-only env like
        // MTL_HUD_ENABLED before the Unix-side Metal module is loaded. Direct launch
        // keeps Forge's environment on the actual Wine process tree.
        process.arguments = [exePath] + ((isSteam && steamSafeMode) ? steamSafeArgs(extraArgs) : extraArgs)
        process.currentDirectoryURL = URL(fileURLWithPath: exePath).deletingLastPathComponent()
        process.environment = env

        let log = try launchLogHandle()
        let launchSummary = """
        Forge Native launch
        wine=\(winePath)
        prefix=\(bottle.prefixPath)
        exe=\(exePath)
        isSteam=\(isSteam)
        backend=\(launchBackend.rawValue)
        steamSafeMode=\(isSteam && steamSafeMode)
        steamGameBackend=\(isSteam ? gameBackend.rawValue : "")
        args=\(process.arguments?.joined(separator: " ") ?? "")
        WINEDLLOVERRIDES=\(env["WINEDLLOVERRIDES"] ?? "")
        WINE_D3D_CONFIG=\(env["WINE_D3D_CONFIG"] ?? "")
        VK_ICD_FILENAMES=\(env["VK_ICD_FILENAMES"] ?? "")
        DYLD_LIBRARY_PATH=\(env["DYLD_LIBRARY_PATH"] ?? "")
        DYLD_FALLBACK_LIBRARY_PATH=\(env["DYLD_FALLBACK_LIBRARY_PATH"] ?? "")
        MTL_HUD_ENABLED=\(env["MTL_HUD_ENABLED"] ?? "")
        MTL_HUD_LAYER=\(env["MTL_HUD_LAYER"] ?? "")
        WINEDLLPATH=\(env["WINEDLLPATH"] ?? "")
        DXVK_FILTER_DEVICE_NAME=\(env["DXVK_FILTER_DEVICE_NAME"] ?? "")
        FORGE_D3DMETAL_RUNTIME=\(env["FORGE_D3DMETAL_RUNTIME"] ?? "")
        D3DMETAL_FRAMEWORK_PATH=\(env["D3DMETAL_FRAMEWORK_PATH"] ?? "")
        SteamAppId=\(env["SteamAppId"] ?? "")
        FORGE_STACK_GUARANTEE_BYTES=\(env["FORGE_STACK_GUARANTEE_BYTES"] ?? "")
        FORGE_STEAM_SAFE_MODE=\(env["FORGE_STEAM_SAFE_MODE"] ?? "")
        FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP=\(env["FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP"] ?? "")
        FORGE_GAME_WINEDLLOVERRIDES=\(env["FORGE_GAME_WINEDLLOVERRIDES"] ?? "")
        FORGE_GAME_WINE_D3D_CONFIG=\(env["FORGE_GAME_WINE_D3D_CONFIG"] ?? "")
        FORGE_GAME_LIBGL_ALWAYS_SOFTWARE=\(env["FORGE_GAME_LIBGL_ALWAYS_SOFTWARE"] ?? "")
        FORGE_GAME_VK_ICD_FILENAMES=\(env["FORGE_GAME_VK_ICD_FILENAMES"] ?? "")
        FORGE_GAME_VK_DRIVER_FILES=\(env["FORGE_GAME_VK_DRIVER_FILES"] ?? "")
        FORGE_GAME_MTL_HUD_ENABLED=\(env["FORGE_GAME_MTL_HUD_ENABLED"] ?? "")
        FORGE_GAME_MTL_HUD_LAYER=\(env["FORGE_GAME_MTL_HUD_LAYER"] ?? "")
        FORGE_GAME_DXVK_ASYNC=\(env["FORGE_GAME_DXVK_ASYNC"] ?? "")
        FORGE_GAME_DYLD_LIBRARY_PATH=\(env["FORGE_GAME_DYLD_LIBRARY_PATH"] ?? "")
        FORGE_GAME_WINEDLLPATH=\(env["FORGE_GAME_WINEDLLPATH"] ?? "")

        """
        if let data = launchSummary.data(using: .utf8) {
            log.write(data)
        }
        process.standardOutput = log
        process.standardError = log
        try process.run()
    }

}
