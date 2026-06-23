import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

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
            alertMessage = Self.sessionOnlyChangeMessage(
                change: "Bottle",
                destination: "config.json",
                error: error
            )
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
                let appDirectPath = await MainActor.run { self.directLaunchPath(for: app, bottle: bottle) }
                let targetPath: String
                let forceSteamMode: Bool
                let steamAppId: String?
                let extraArgs: [String]
                let steamBootstrapPath: String?

                if throughSteam {
                    guard let appId = app.steamAppId else {
                        throw ForgeError.message("This app is not linked to a Steam manifest.")
                    }
                    guard let steamPath = await MainActor.run(body: { self.steamPath }) else {
                        throw ForgeError.message("Windows Steam is not installed in this bottle yet.")
                    }
                    if let appDirectPath {
                        // Some Steam builds advertise a launcher stub in the manifest,
                        // but the actual game is a nested Win64 shipping executable.
                        // Start Steam first for Steamworks, then launch that executable
                        // directly with the compatibility profile's backend/env.
                        steamBootstrapPath = steamPath
                        targetPath = appDirectPath
                        forceSteamMode = false
                        steamAppId = appId
                        extraArgs = appLaunchArgs
                    } else {
                        steamBootstrapPath = nil
                        targetPath = steamPath
                        forceSteamMode = true
                        steamAppId = appId
                        extraArgs = ["-applaunch", appId] + appLaunchArgs
                    }
                } else {
                    steamBootstrapPath = nil
                    targetPath = app.path
                    forceSteamMode = app.isSteamClient
                    steamAppId = app.steamAppId
                    extraArgs = appLaunchArgs
                }

                if app.name.caseInsensitiveCompare("PEAK") == .orderedSame
                    || app.name.caseInsensitiveCompare("Against the Storm") == .orderedSame {
                    try? Self.stopWineSession(bottle: bottle, config: launchConfig, profile: launchProfile)
                }

                if let steamBootstrapPath {
                    try await Self.spawn(
                        exePath: steamBootstrapPath,
                        bottle: bottle,
                        config: launchConfig,
                        profile: launchProfile,
                        extraArgs: [],
                        forceSteamMode: true,
                        steamAppId: nil,
                        backendOverride: .wineBuiltin,
                        gameEnvOverrides: [:],
                        steamSafeMode: true
                    )
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                }

                if throughSteam, appBackend == .d3dMetal, appDirectPath == nil {
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

    func setRuntimeProfile(_ profileId: String) {
        guard var current = bottle,
              profiles.contains(where: { $0.id == profileId }) else { return }
        current.runtimeProfileId = profileId
        bottle = current
        do {
            try Self.saveBottle(current, to: Self.appSupportDir(), config: config)
        } catch {
            alertMessage = Self.sessionOnlyChangeMessage(
                change: "Runtime",
                destination: "bottles.json",
                error: error
            )
        }
        refreshBottleState()
    }

    func setBackend(_ backend: GraphicsBackend) {
        guard var current = bottle else { return }
        current.graphicsBackend = backend
        bottle = current
        do {
            try Self.saveBottle(current, to: Self.appSupportDir(), config: config)
        } catch {
            alertMessage = Self.sessionOnlyChangeMessage(
                change: "Backend",
                destination: "bottles.json",
                error: error
            )
        }
    }

    func setMetalHud(_ enabled: Bool) {
        config.globalHud = enabled
        do {
            try Self.saveConfig(config, to: Self.appSupportDir())
            try Self.setMetalHudDefaults(enabled)
        } catch {
            alertMessage = Self.sessionOnlyChangeMessage(
                change: "Metal HUD",
                destination: "config",
                error: error
            )
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

    func defaultBackend(for bottle: BottleEntry) -> GraphicsBackend {
        bottle.graphicsBackend ?? profile(for: bottle).defaultBackend
    }

    private nonisolated static func sessionOnlyChangeMessage(
        change: String,
        destination: String,
        error: Error
    ) -> String {
        "\(change) changed for this session, but Forge could not save \(destination): \(error.localizedDescription)"
    }
}
