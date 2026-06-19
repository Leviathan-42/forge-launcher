import Foundation

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

    nonisolated static func setMetalHudDefaults(_ enabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "-g", "MetalForceHudEnabled", "-bool", enabled ? "YES" : "NO"]
        try process.run()
        process.waitUntilExit()
    }

    nonisolated static func stopWineSession(bottle: BottleEntry, config: AppConfig, profile: RuntimeProfile) throws {
        let winePath = profile.wine64Path.isEmpty ? config.wine64Path : profile.wine64Path
        let wineserverPath = profile.wineserverPath?.isEmpty == false
            ? profile.wineserverPath!
            : URL(fileURLWithPath: winePath).deletingLastPathComponent().appendingPathComponent("wineserver").path
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

    nonisolated static func removeStagedD3DMetalDlls(exePath: String) throws {
        let gameDir = URL(fileURLWithPath: exePath).deletingLastPathComponent()
        for dll in ["dxgi.dll", "d3d9.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll"] {
            let target = gameDir.appendingPathComponent(dll)
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
            if attrs?[.type] as? FileAttributeType == .typeRegular || attrs?[.type] as? FileAttributeType == .typeSymbolicLink {
                try FileManager.default.removeItem(at: target)
            }
        }
    }

    nonisolated static func ensureDXVKInstalled(exePath: String, prefixPath: String, steamAppId: String?) throws {
        let fm = FileManager.default
        let sourceRoots = dxvkSourceRoots()
        guard let sourceRoot = sourceRoots.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("x64/d3d11.dll").path)
                && fm.fileExists(atPath: $0.appendingPathComponent("x64/dxgi.dll").path)
        }) else {
            throw ForgeError.message("DXVK runtime files were not found. Expected ~/Wine/Runtimes/dxvk-*/dxvk-*/x64/d3d11.dll.")
        }

        var targetDirs: [URL] = []
        let exeURL = URL(fileURLWithPath: exePath)
        if exeURL.lastPathComponent.caseInsensitiveCompare("steam.exe") != .orderedSame {
            targetDirs.append(exeURL.deletingLastPathComponent())
        }
        if let steamAppId, let steamGameDir = steamGameDirectory(prefixPath: prefixPath, appId: steamAppId) {
            targetDirs.append(steamGameDir)
        }

        var seen = Set<String>()
        let uniqueDirs = targetDirs.filter { seen.insert($0.path).inserted }
        let x64 = sourceRoot.appendingPathComponent("x64", isDirectory: true)
        for dir in uniqueDirs {
            for dll in ["dxgi.dll", "d3d9.dll", "d3d10core.dll", "d3d10.dll", "d3d10_1.dll", "d3d11.dll"] {
                let source = x64.appendingPathComponent(dll)
                if fm.fileExists(atPath: source.path) {
                    try copyIfDifferent(source, to: dir.appendingPathComponent(dll))
                }
            }
        }
    }

    nonisolated static func dxvkSourceRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runtimes = home.appendingPathComponent("Wine/Runtimes", isDirectory: true)
        var roots: [URL] = []
        if let entries = try? FileManager.default.contentsOfDirectory(at: runtimes, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries where entry.lastPathComponent.lowercased().contains("dxvk") {
                if let children = try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    roots.append(contentsOf: children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending })
                }
                roots.append(entry)
            }
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }

    nonisolated static func steamGameDirectory(prefixPath: String, appId: String) -> URL? {
        let steamapps = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appId).acf")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "\"").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if parts.count >= 2, parts[0].trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("installdir") == .orderedSame {
                return steamapps.appendingPathComponent("common", isDirectory: true).appendingPathComponent(parts[1], isDirectory: true)
            }
        }
        return nil
    }

    nonisolated static func ensureDXMTInstalled(winePath: String, prefixPath: String) throws {
        let fm = FileManager.default
        let wineRoot = URL(fileURLWithPath: winePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimeWin64Dir = wineRoot.appendingPathComponent("lib/wine/x86_64-windows", isDirectory: true)
        let runtimeWin32Dir = wineRoot.appendingPathComponent("lib/wine/i386-windows", isDirectory: true)
        let runtimeUnixDir = wineRoot.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let system32 = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)

        guard fm.fileExists(atPath: runtimeWin64Dir.path), fm.fileExists(atPath: runtimeUnixDir.path) else {
            throw ForgeError.message("DXMT needs a Wine runtime with lib/wine/x86_64-windows and x86_64-unix directories.")
        }
        try fm.createDirectory(at: system32, withIntermediateDirectories: true)
        try fm.createDirectory(at: syswow64, withIntermediateDirectories: true)

        let sourceRoots = dxmtSourceRoots(wineRoot: wineRoot)
        guard let sourceRoot = sourceRoots.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("x86_64-windows/d3d11.dll").path)
                && fm.fileExists(atPath: $0.appendingPathComponent("x86_64-windows/dxgi.dll").path)
                && fm.fileExists(atPath: $0.appendingPathComponent("x86_64-unix/winemetal.so").path)
        }) else {
            throw ForgeError.message("DXMT runtime files were not found. Expected ~/Wine/Runtimes/dxmt-v*/v*/x86_64-windows and x86_64-unix.")
        }

        let windows64Source = sourceRoot.appendingPathComponent("x86_64-windows", isDirectory: true)
        let windows32Source = sourceRoot.appendingPathComponent("i386-windows", isDirectory: true)
        let unixSource = sourceRoot.appendingPathComponent("x86_64-unix", isDirectory: true)
        for dll in ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"] {
            let source64 = windows64Source.appendingPathComponent(dll)
            if fm.fileExists(atPath: source64.path) {
                try copyIfDifferent(source64, to: runtimeWin64Dir.appendingPathComponent(dll))
                // Unity checks for a real file before Wine resolves the builtin module.
                // Keep the PE builtin marker in system32, but use builtin overrides.
                try copyIfDifferent(source64, to: system32.appendingPathComponent(dll))
            }

            let source32 = windows32Source.appendingPathComponent(dll)
            if fm.fileExists(atPath: source32.path), fm.fileExists(atPath: runtimeWin32Dir.path) {
                try copyIfDifferent(source32, to: runtimeWin32Dir.appendingPathComponent(dll))
                // 32-bit Unity games like Among Us load through the 32-bit system DLL view.
                try copyIfDifferent(source32, to: syswow64.appendingPathComponent(dll))
            }
        }
        try copyIfDifferent(windows64Source.appendingPathComponent("d3d11.dll"), to: runtimeWin64Dir.appendingPathComponent("dd3d11.dll"))
        try copyIfDifferent(windows64Source.appendingPathComponent("d3d11.dll"), to: system32.appendingPathComponent("dd3d11.dll"))
        if fm.fileExists(atPath: windows32Source.appendingPathComponent("d3d11.dll").path), fm.fileExists(atPath: runtimeWin32Dir.path) {
            try copyIfDifferent(windows32Source.appendingPathComponent("d3d11.dll"), to: runtimeWin32Dir.appendingPathComponent("dd3d11.dll"))
            try copyIfDifferent(windows32Source.appendingPathComponent("d3d11.dll"), to: syswow64.appendingPathComponent("dd3d11.dll"))
        }
        try copyIfDifferent(unixSource.appendingPathComponent("winemetal.so"), to: runtimeUnixDir.appendingPathComponent("winemetal.so"))
    }

    nonisolated static func dxmtSourceRoots(wineRoot: URL) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runtimes = home.appendingPathComponent("Wine/Runtimes", isDirectory: true)
        var roots: [URL] = []
        if let entries = try? FileManager.default.contentsOfDirectory(at: runtimes, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries where entry.lastPathComponent.lowercased().contains("dxmt") {
                roots.append(entry)
                if let children = try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    roots.append(contentsOf: children)
                }
            }
        }
        roots.append(wineRoot.appendingPathComponent("lib/dxmt", isDirectory: true))
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }

    nonisolated static func copyIfDifferent(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            let sourceAttrs = try? fm.attributesOfItem(atPath: source.path)
            let destAttrs = try? fm.attributesOfItem(atPath: destination.path)
            if (sourceAttrs?[.size] as? NSNumber) == (destAttrs?[.size] as? NSNumber) { return }
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    nonisolated static func configureMoltenVK(profile: RuntimeProfile, config: AppConfig, env: inout [String: String]) {
        if let existing = env["VK_ICD_FILENAMES"], !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        let configured = profile.moltenvkPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidates = moltenVkIcdCandidates(configuredPath: configured)
        if let icd = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            env["VK_ICD_FILENAMES"] = icd
            env["VK_DRIVER_FILES"] = icd
        }

        env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] ?? "1"
        env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] = env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] ?? "1"
        env["MOLTENVK_CONFIG_LOG_LEVEL"] = env["MOLTENVK_CONFIG_LOG_LEVEL"] ?? "0"
    }

    nonisolated static func moltenVkIcdCandidates(configuredPath: String) -> [String] {
        var candidates: [String] = []
        func add(_ path: String) {
            if !path.isEmpty { candidates.append((path as NSString).expandingTildeInPath) }
        }

        add(configuredPath)
        if !configuredPath.isEmpty {
            add(URL(fileURLWithPath: configuredPath).appendingPathComponent("share/vulkan/icd.d/MoltenVK_icd.json").path)
            add(URL(fileURLWithPath: configuredPath).appendingPathComponent("MoltenVK_icd.json").path)
        }
        add("/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json")
        add("/usr/local/share/vulkan/icd.d/MoltenVK_icd.json")
        add("/opt/homebrew/Cellar/molten-vk/share/vulkan/icd.d/MoltenVK_icd.json")
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    nonisolated static func buildDyldPath(gptkLibPath: String?, existing: String) -> String {
        var parts: [String] = []
        if let gptkLibPath, !gptkLibPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let configured = URL(fileURLWithPath: gptkLibPath)
            parts.append(configured.path)
            if configured.lastPathComponent.caseInsensitiveCompare("external") == .orderedSame {
                parts.append(configured.appendingPathComponent("D3DMetal.framework/Versions/A").path)
                parts.append(configured.deletingLastPathComponent().path)
            } else {
                let external = configured.appendingPathComponent("external")
                parts.append(external.path)
                parts.append(external.appendingPathComponent("D3DMetal.framework/Versions/A").path)
            }
        }
        if !existing.isEmpty { parts.append(existing) }
        return dedupePathParts(parts).joined(separator: ":")
    }

    nonisolated static func gptkWineLibBase(gptkLibPath: String?) -> URL? {
        guard let gptkLibPath, !gptkLibPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let configured = URL(fileURLWithPath: gptkLibPath)
        if configured.lastPathComponent.caseInsensitiveCompare("external") == .orderedSame {
            return configured.deletingLastPathComponent()
        }
        if configured.lastPathComponent.caseInsensitiveCompare("lib") == .orderedSame {
            return configured
        }
        return configured
    }

    nonisolated static func d3dMetalFrameworkPath(gptkLibPath: String?) -> String? {
        guard let base = gptkWineLibBase(gptkLibPath: gptkLibPath) else { return nil }
        let candidates = [
            base.appendingPathComponent("external/D3DMetal.framework").path,
            base.appendingPathComponent("D3DMetal.framework").path,
            "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    nonisolated static func gptkWinePath(gptkLibPath: String?) -> String? {
        guard let base = gptkWineLibBase(gptkLibPath: gptkLibPath) else { return nil }
        let candidates = [
            base.appendingPathComponent("bin/wine64").path,
            base.deletingLastPathComponent().appendingPathComponent("bin/wine64").path,
            "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    nonisolated static func dedupePathParts(_ parts: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for part in parts where !part.isEmpty && !seen.contains(part) {
            seen.insert(part)
            output.append(part)
        }
        return output
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
        let url = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
        let data = try Data(contentsOf: url)
        try data.write(to: target, options: .atomic)
        return target
    }
}
