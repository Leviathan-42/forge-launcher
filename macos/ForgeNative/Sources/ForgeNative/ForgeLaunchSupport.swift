import Foundation

private let launchSummaryEnvironmentKeys = [
    "WINEDLLOVERRIDES",
    "WINE_D3D_CONFIG",
    "VK_ICD_FILENAMES",
    "DYLD_LIBRARY_PATH",
    "DYLD_FALLBACK_LIBRARY_PATH",
    "MTL_HUD_ENABLED",
    "MTL_HUD_LAYER",
    "WINEDLLPATH",
    "DXVK_FILTER_DEVICE_NAME",
    "FORGE_D3DMETAL_RUNTIME",
    "D3DMETAL_FRAMEWORK_PATH",
    "SteamAppId",
    "FORGE_STACK_GUARANTEE_BYTES",
    "FORGE_STEAM_SAFE_MODE",
    "FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP",
    "FORGE_GAME_WINEDLLOVERRIDES",
    "FORGE_GAME_WINE_D3D_CONFIG",
    "FORGE_GAME_LIBGL_ALWAYS_SOFTWARE",
    "FORGE_GAME_VK_ICD_FILENAMES",
    "FORGE_GAME_VK_DRIVER_FILES",
    "FORGE_GAME_MTL_HUD_ENABLED",
    "FORGE_GAME_MTL_HUD_LAYER",
    "FORGE_GAME_DXVK_ASYNC",
    "FORGE_GAME_DYLD_LIBRARY_PATH",
    "FORGE_GAME_WINEDLLPATH"
]

extension ForgeStore {
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
        let isSteam = isSteamExecutable(exePath, forceSteamMode: forceSteamMode)
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
        let runtimeDyldPath = runtimeLibrarySearchPath(
            runtimeLibPath: runtimeLibPath,
            existing: env["DYLD_LIBRARY_PATH"]
        )
        let runtimeFallbackDyldPath = runtimeFallbackLibrarySearchPath(
            runtimeLibPath: runtimeLibPath,
            existing: env["DYLD_FALLBACK_LIBRARY_PATH"]
        )
        env["WINEPREFIX"] = bottle.prefixPath
        if launchBackend == .d3dMetal {
            env["DYLD_LIBRARY_PATH"] = buildDyldPath(
                gptkLibPath: gptkLibPath,
                existing: runtimeDyldPath
            )
            env["DYLD_FALLBACK_LIBRARY_PATH"] = runtimeFallbackDyldPath
            if !gptkLibPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                env["DYLD_FRAMEWORK_PATH"] = URL(fileURLWithPath: gptkLibPath).path
            }
        } else {
            // DXVK/VKD3D should use Forge/Homebrew MoltenVK. Do not let GPTK's
            // older external libMoltenVK shadow the Vulkan 1.3+ ICD needed by DXVK.
            env["DYLD_LIBRARY_PATH"] = runtimeDyldPath
            env["DYLD_FALLBACK_LIBRARY_PATH"] = runtimeFallbackDyldPath
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
        if backendUsesMoltenVK(launchBackend) {
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
            env["WINEDLLOVERRIDES"] = wineDllOverrides(for: launchBackend)
            if let frameworkPath = d3dMetalFrameworkPath(gptkLibPath: gptkLibPath) {
                env["D3DMETAL_FRAMEWORK_PATH"] = frameworkPath
            }
            env["D3DM_MTL4"] = env["D3DM_MTL4"] ?? "0"
            env["D3DM_SUPPORT_DXR"] = env["D3DM_SUPPORT_DXR"] ?? "0"
            env["D3DM_ENABLE_METALFX"] = env["D3DM_ENABLE_METALFX"] ?? "0"
            env["FORGE_D3DMETAL_RUNTIME"] = "gptk-wine-d3dmetal"
        case .dxvk:
            try ensureDXVKInstalled(exePath: exePath, prefixPath: bottle.prefixPath, steamAppId: steamAppId)
            env["WINEDLLOVERRIDES"] = wineDllOverrides(for: launchBackend)
            env["DXVK_ASYNC"] = "1"
        case .vkd3d:
            env["WINEDLLOVERRIDES"] = wineDllOverrides(for: launchBackend)
        case .dxvkVkd3d:
            try ensureDXVKInstalled(exePath: exePath, prefixPath: bottle.prefixPath, steamAppId: steamAppId)
            env["WINEDLLOVERRIDES"] = wineDllOverrides(for: launchBackend)
            env["DXVK_ASYNC"] = "1"
        case .wineBuiltin:
            try removeStagedD3DMetalDlls(exePath: exePath)
            env["WINEDLLOVERRIDES"] = wineDllOverrides(for: launchBackend)
            env["WINE_D3D_CONFIG"] = "renderer=gl"
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        case .dxmt:
            try ensureDXMTInstalled(winePath: winePath, prefixPath: bottle.prefixPath)
            try removeStagedD3DMetalDlls(exePath: exePath)
            env["WINEDLLOVERRIDES"] = wineDllOverrides(for: launchBackend)
            env["DXMT_LOG_LEVEL"] = env["DXMT_LOG_LEVEL"] ?? "info"
            env["DXMT_LOG_PATH"] = env["DXMT_LOG_PATH"] ??
                appSupportDir().appendingPathComponent("Logs", isDirectory: true).path
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
            clearVulkanBackendEnvironment(&env)
        }

        if launchBackend == .d3dMetal {
            // D3DMetal must not inherit Vulkan/DXVK profile settings. If VK_ICD or
            // DXVK variables survive here, Wine can load DXVK instead of GPTK's
            // builtin D3DMetal DLLs and Unity games crash before rendering.
            clearVulkanBackendEnvironment(&env)
        }

        // This win32u workaround is only for Steam's Chromium helper. Do not let
        // a shell/profile value leak into direct game launches.
        env.removeValue(forKey: "FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP")

        if isSteam && steamSafeMode {
            if backendUsesMoltenVK(gameBackend) {
                configureMoltenVK(profile: profile, config: config, env: &env)
            }
            let gameVkIcd = env["VK_ICD_FILENAMES"] ?? ""
            let gameVkDriverFiles = env["VK_DRIVER_FILES"] ?? gameVkIcd
            let preserveWineD3DEnv = backendPreservesWineD3DEnvironment(gameBackend)
            let gameWineD3DConfig = preserveWineD3DEnv ? (env["WINE_D3D_CONFIG"] ?? "") : ""
            let gameLibGLAlwaysSoftware = preserveWineD3DEnv ? (env["LIBGL_ALWAYS_SOFTWARE"] ?? "") : ""
            let gameMetalHudEnabled = config.globalHud ? "1" : "0"
            let gameMetalHudLayer = config.globalHud ? "1" : "0"
            let gameDXVKAsync = backendUsesDXVKAsync(gameBackend) ? (env["DXVK_ASYNC"] ?? "1") : ""
            let gameDyldPath = gameBackend == .d3dMetal ? buildDyldPath(
                gptkLibPath: gptkLibPath,
                existing: runtimeLibrarySearchPath(
                    runtimeLibPath: runtimeLibPath,
                    existing: env["DYLD_LIBRARY_PATH"]
                )
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
            let gameDllOverrides = wineDllOverrides(for: gameBackend) ?? ""

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
        let launchArgs = [exePath] + ((isSteam && steamSafeMode) ? steamSafeArgs(extraArgs) : extraArgs)
        process.arguments = launchArgs
        process.currentDirectoryURL = URL(fileURLWithPath: exePath).deletingLastPathComponent()
        process.environment = env

        let log = try launchLogHandle()
        let launchSummary = formatLaunchSummary(
            winePath: winePath,
            prefixPath: bottle.prefixPath,
            exePath: exePath,
            isSteam: isSteam,
            launchBackend: launchBackend,
            gameBackend: gameBackend,
            steamSafeMode: isSteam && steamSafeMode,
            args: launchArgs,
            env: env
        )
        if let data = launchSummary.data(using: .utf8) {
            log.write(data)
        }
        process.standardOutput = log
        process.standardError = log
        try process.run()
    }

    nonisolated static func setMetalHudDefaults(_ enabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "-g", "MetalForceHudEnabled", "-bool", enabled ? "YES" : "NO"]
        try process.run()
        process.waitUntilExit()
    }

    nonisolated static func stopWineSession(bottle: BottleEntry, config: AppConfig, profile: RuntimeProfile) throws {
        let wineserverPath = resolvedWineserverPath(profile: profile, config: config)
        guard FileManager.default.fileExists(atPath: wineserverPath) else {
            throw ForgeError.message("wineserver not found next to Wine at \(wineserverPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineserverPath)
        process.arguments = ["-k"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "WINEPREFIX": bottle.prefixPath,
            "WINEDEBUG": "fixme-all"
        ]) { _, new in new }
        let log = try launchLogHandle()
        process.standardOutput = log
        process.standardError = log
        try process.run()
        process.waitUntilExit()
    }

    nonisolated static func resolvedWineserverPath(profile: RuntimeProfile, config: AppConfig) -> String {
        if let wineserverPath = profile.wineserverPath, !wineserverPath.isEmpty {
            return wineserverPath
        }
        let winePath = profile.wine64Path.isEmpty ? config.wine64Path : profile.wine64Path
        return URL(fileURLWithPath: winePath).deletingLastPathComponent().appendingPathComponent("wineserver").path
    }

    nonisolated static func ensurePrefix(prefixPath: String, winePath: String) throws {
        if FileManager.default.fileExists(atPath: prefixPath) { return }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: prefixPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: winePath)
        process.arguments = ["wineboot", "--init"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "WINEPREFIX": prefixPath,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1",
            "WINEDLLOVERRIDES": "mscoree,mshtml="
        ]) { _, new in new }
        let log = try launchLogHandle()
        process.standardOutput = log
        process.standardError = log
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ForgeError.message("wineboot failed for \(prefixPath)")
        }
    }

    nonisolated static func steamSafeArgs(_ extra: [String]) -> [String] {
        ["-no-cef-sandbox", "-cef-disable-sandbox"] + extra
    }

    nonisolated static func isSteamExecutable(_ exePath: String, forceSteamMode: Bool) -> Bool {
        forceSteamMode ||
            URL(fileURLWithPath: exePath)
                .lastPathComponent
                .caseInsensitiveCompare("steam.exe") == .orderedSame
    }

    nonisolated static func clearVulkanBackendEnvironment(_ env: inout [String: String]) {
        env.removeValue(forKey: "VK_ICD_FILENAMES")
        env.removeValue(forKey: "VK_DRIVER_FILES")
        env.removeValue(forKey: "DXVK_ASYNC")
        env.removeValue(forKey: "DXVK_FILTER_DEVICE_NAME")
    }

    nonisolated static func formatLaunchSummary(
        winePath: String,
        prefixPath: String,
        exePath: String,
        isSteam: Bool,
        launchBackend: GraphicsBackend,
        gameBackend: GraphicsBackend,
        steamSafeMode: Bool,
        args: [String],
        env: [String: String]
    ) -> String {
        let headerLines = [
            "Forge Native launch",
            "wine=\(winePath)",
            "prefix=\(prefixPath)",
            "exe=\(exePath)",
            "isSteam=\(isSteam)",
            "backend=\(launchBackend.rawValue)",
            "steamSafeMode=\(steamSafeMode)",
            "steamGameBackend=\(isSteam ? gameBackend.rawValue : "")",
            "args=\(args.joined(separator: " "))"
        ]
        let envLines = launchSummaryEnvironmentKeys.map { key in
            "\(key)=\(env[key] ?? "")"
        }
        return (headerLines + envLines).joined(separator: "\n") + "\n\n"
    }

    nonisolated static func launchLogHandle() throws -> FileHandle {
        let dir = appSupportDir().appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("swiftui-launch-\(stamp).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try FileHandle(forWritingTo: url)
    }

    nonisolated static func downloadSteamInstaller() throws -> URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ForgeNative/installers", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("SteamSetup.exe")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let url = try steamInstallerDownloadURL()
        let data = try Data(contentsOf: url)
        try data.write(to: target, options: .atomic)
        return target
    }

    nonisolated static func steamInstallerDownloadURL() throws -> URL {
        guard let url = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe") else {
            throw ForgeError.message("Steam installer URL is invalid.")
        }
        return url
    }
}
