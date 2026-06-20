import Foundation

struct GameCompatibilityProfile: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var backendOverride: GraphicsBackend?
    var launchArgs: [String]
    var env: [String: String]
    var notes: String?
}

private enum SeededGameProfileID {
    static let againstTheStorm = "steam:1336490"
    static let amongUs = "steam:945360"
    static let overwatch = "steam:2357570"
    static let peak = "name:peak"
}

private enum GameProfileEnvKey {
    static let overwatchStackGuarantee = "FORGE_STACK_GUARANTEE_BYTES"
}

private enum SeededGameProfileValue {
    static let amongUsWineDllOverrides = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11," +
        "*d3d12,*d3d12core=b;vulkan-1,winevulkan=b;mscoree,mshtml="
    static let peakLaunchArgs = [
        "-force-vulkan",
        "-force-gfx-st",
        "-disable-gpu-skinning",
        "-screen-fullscreen",
        "1"
    ]
}

extension ForgeStore {
    nonisolated static func loadGameProfiles(from support: URL) throws -> [String: GameCompatibilityProfile] {
        let url = support.appendingPathComponent("game_compatibility_profiles.json")
        var profiles: [String: GameCompatibilityProfile]
        if FileManager.default.fileExists(atPath: url.path) {
            let decoded = try JSONDecoder.forge.decode([GameCompatibilityProfile].self, from: Data(contentsOf: url))
            profiles = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        } else {
            profiles = [:]
        }

        for seed in seededGameProfiles() {
            guard let existing = profiles[seed.id] else {
                profiles[seed.id] = seed
                continue
            }

            if shouldReplaceLoadedGameProfile(existing, with: seed) {
                profiles[seed.id] = seed
            } else if shouldBackfillOverwatchStackGuarantee(existing, seed: seed) {
                profiles[seed.id] = addingOverwatchStackGuarantee(to: existing, from: seed)
            }
        }

        return profiles
    }

    nonisolated static func saveGameProfiles(_ profiles: [String: GameCompatibilityProfile], to support: URL) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let ordered = profiles.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let data = try JSONEncoder.forge.encode(ordered)
        try data.write(to: support.appendingPathComponent("game_compatibility_profiles.json"), options: .atomic)
    }

    nonisolated static func seededGameProfiles() -> [GameCompatibilityProfile] {
        [
            GameCompatibilityProfile(
                id: SeededGameProfileID.againstTheStorm,
                displayName: "Against the Storm",
                backendOverride: .dxmt,
                launchArgs: ["-screen-fullscreen", "1"],
                env: [:],
                notes: "D3D11-only Unity build; Vulkan/OpenGL shaders are unavailable " +
                    "and DXVK is blocked by MoltenVK geometryShader support. Uses DXMT's D3D11 -> Metal path."
            ),
            GameCompatibilityProfile(
                id: SeededGameProfileID.amongUs,
                displayName: "Among Us",
                backendOverride: .wineBuiltin,
                launchArgs: [],
                env: [
                    "WINE_D3D_CONFIG": "renderer=vulkan",
                    "WINEDLLOVERRIDES": SeededGameProfileValue.amongUsWineDllOverrides,
                    "VK_ICD_FILENAMES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json",
                    "VK_DRIVER_FILES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
                ],
                notes: "32-bit Unity D3D11 build; DXMT/DXVK are not viable in this WoW64 runtime. " +
                    "WineD3D's Vulkan renderer reaches D3D11 level 11.1."
            ),
            GameCompatibilityProfile(
                id: SeededGameProfileID.overwatch,
                displayName: "Overwatch 2",
                backendOverride: .dxvkVkd3d,
                launchArgs: [],
                env: [GameProfileEnvKey.overwatchStackGuarantee: "262144"],
                notes: "Steam build. Use DXVK/VKD3D and reserve a larger stack-overflow handling guarantee " +
                    "for Blizzard's loader/VEH path; do not use D3DMetal for the current Forge runtime."
            ),
            GameCompatibilityProfile(
                id: SeededGameProfileID.peak,
                displayName: "PEAK",
                backendOverride: .dxvkVkd3d,
                launchArgs: SeededGameProfileValue.peakLaunchArgs,
                env: [:],
                notes: "Unity Vulkan path works; disable GPU skinning to avoid avatar mesh corruption."
            )
        ]
    }

    nonisolated static func seededGameProfile(forKey key: String) -> GameCompatibilityProfile? {
        seededGameProfiles().first { $0.id == key }
    }

    private nonisolated static func shouldReplaceLoadedGameProfile(
        _ profile: GameCompatibilityProfile,
        with seed: GameCompatibilityProfile
    ) -> Bool {
        switch seed.id {
        case SeededGameProfileID.againstTheStorm:
            return profile.backendOverride == .d3dMetal
        case SeededGameProfileID.amongUs:
            return profile.backendOverride != .wineBuiltin
        case SeededGameProfileID.overwatch:
            return profile.backendOverride == .d3dMetal
        default:
            return false
        }
    }

    private nonisolated static func shouldBackfillOverwatchStackGuarantee(
        _ profile: GameCompatibilityProfile,
        seed: GameCompatibilityProfile
    ) -> Bool {
        seed.id == SeededGameProfileID.overwatch && profile.env[GameProfileEnvKey.overwatchStackGuarantee] == nil
    }

    private nonisolated static func addingOverwatchStackGuarantee(
        to profile: GameCompatibilityProfile,
        from seed: GameCompatibilityProfile
    ) -> GameCompatibilityProfile {
        var updated = profile
        if let value = seed.env[GameProfileEnvKey.overwatchStackGuarantee] {
            updated.env[GameProfileEnvKey.overwatchStackGuarantee] = value
        }
        updated.notes = seed.notes
        return updated
    }

    nonisolated static func gameProfileCanReset(_ profiles: [String: GameCompatibilityProfile], key: String) -> Bool {
        guard let profile = profiles[key] else { return false }
        if let seed = seededGameProfile(forKey: key) {
            return profile != seed
        }
        return true
    }

    nonisolated static func resetGameProfiles(
        _ profiles: [String: GameCompatibilityProfile],
        key: String
    ) -> [String: GameCompatibilityProfile] {
        var updated = profiles
        if let seed = seededGameProfile(forKey: key) {
            updated[key] = seed
        } else {
            updated.removeValue(forKey: key)
        }
        return updated
    }

    nonisolated static func gameProfileKey(for app: BottleAppItem) -> String {
        if app.name.caseInsensitiveCompare("PEAK") == .orderedSame { return SeededGameProfileID.peak }
        if let appId = app.steamAppId, !appId.isEmpty { return "steam:\(appId)" }
        return "exe:\(app.path.standardizingPath.lowercased())"
    }

    func gameProfile(for app: BottleAppItem) -> GameCompatibilityProfile {
        let key = Self.gameProfileKey(for: app)
        if let profile = gameProfiles[key] { return profile }
        return GameCompatibilityProfile(
            id: key,
            displayName: app.name,
            backendOverride: nil,
            launchArgs: [],
            env: [:],
            notes: nil
        )
    }

    func gameProfileIsAppSpecific(for app: BottleAppItem) -> Bool {
        let profile = gameProfile(for: app)
        return profile.backendOverride != nil
            || !profile.launchArgs.isEmpty
            || !profile.env.isEmpty
            || profile.notes != nil
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
            alertMessage = "Compatibility profile changed for this session, " +
                "but Forge could not save it: \(error.localizedDescription)"
        }
    }
}
