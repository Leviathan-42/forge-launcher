import Foundation

struct GameCompatibilityProfile: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var backendOverride: GraphicsBackend?
    var launchArgs: [String]
    var env: [String: String]
    var notes: String?
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
            if profiles[seed.id] == nil {
                profiles[seed.id] = seed
            } else if seed.id == "steam:1336490", profiles[seed.id]?.backendOverride == .d3dMetal {
                // Against the Storm is D3D11-only and now works through DXMT in Forge's
                // own Wine runtime. Migrate the earlier D3DMetal seed automatically.
                profiles[seed.id]?.displayName = seed.displayName
                profiles[seed.id]?.backendOverride = .dxmt
                profiles[seed.id]?.launchArgs = seed.launchArgs
                profiles[seed.id]?.env = seed.env
                profiles[seed.id]?.notes = seed.notes
            } else if seed.id == "steam:945360", profiles[seed.id]?.backendOverride != .wineBuiltin {
                // Among Us is a 32-bit Unity D3D11 build. DXMT's 32-bit builtin PE
                // cannot be loaded by this WoW64 runtime, and DXVK hits feature-level
                // limits. WineD3D's Vulkan renderer reaches D3D11 level 11.1.
                profiles[seed.id] = seed
            } else if seed.id == "steam:2357570", profiles[seed.id]?.backendOverride == .d3dMetal {
                // Overwatch fails D3DMetal initialization in the current runtime.
                profiles[seed.id] = seed
            } else if seed.id == "steam:2357570", profiles[seed.id]?.env["FORGE_STACK_GUARANTEE_BYTES"] == nil {
                profiles[seed.id]?.env["FORGE_STACK_GUARANTEE_BYTES"] = seed.env["FORGE_STACK_GUARANTEE_BYTES"]
                profiles[seed.id]?.notes = seed.notes
            }
        }

        return profiles
    }

    nonisolated static func saveGameProfiles(_ profiles: [String: GameCompatibilityProfile], to support: URL) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let ordered = profiles.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let data = try JSONEncoder.forge.encode(ordered)
        try data.write(to: support.appendingPathComponent("game_compatibility_profiles.json"), options: .atomic)
    }

    nonisolated static func seededGameProfiles() -> [GameCompatibilityProfile] {
        [
            GameCompatibilityProfile(
                id: "steam:1336490",
                displayName: "Against the Storm",
                backendOverride: .dxmt,
                launchArgs: ["-screen-fullscreen", "1"],
                env: [:],
                notes: "D3D11-only Unity build; Vulkan/OpenGL shaders are unavailable and DXVK is blocked by MoltenVK geometryShader support. Uses DXMT's D3D11 -> Metal path."
            ),
            GameCompatibilityProfile(
                id: "steam:945360",
                displayName: "Among Us",
                backendOverride: .wineBuiltin,
                launchArgs: [],
                env: [
                    "WINE_D3D_CONFIG": "renderer=vulkan",
                    "WINEDLLOVERRIDES": "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;vulkan-1,winevulkan=b;mscoree,mshtml=",
                    "VK_ICD_FILENAMES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json",
                    "VK_DRIVER_FILES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
                ],
                notes: "32-bit Unity D3D11 build; DXMT/DXVK are not viable in this WoW64 runtime. WineD3D's Vulkan renderer reaches D3D11 level 11.1."
            ),
            GameCompatibilityProfile(
                id: "steam:2357570",
                displayName: "Overwatch 2",
                backendOverride: .dxvkVkd3d,
                launchArgs: [],
                env: ["FORGE_STACK_GUARANTEE_BYTES": "262144"],
                notes: "Steam build. Use DXVK/VKD3D and reserve a larger stack-overflow handling guarantee for Blizzard's loader/VEH path; do not use D3DMetal for the current Forge runtime."
            ),
            GameCompatibilityProfile(
                id: "name:peak",
                displayName: "PEAK",
                backendOverride: .dxvkVkd3d,
                launchArgs: ["-force-vulkan", "-force-gfx-st", "-disable-gpu-skinning", "-screen-fullscreen", "1"],
                env: [:],
                notes: "Unity Vulkan path works; disable GPU skinning to avoid avatar mesh corruption."
            )
        ]
    }

    nonisolated static func seededGameProfile(forKey key: String) -> GameCompatibilityProfile? {
        seededGameProfiles().first { $0.id == key }
    }

    nonisolated static func gameProfileCanReset(_ profiles: [String: GameCompatibilityProfile], key: String) -> Bool {
        guard let profile = profiles[key] else { return false }
        if let seed = seededGameProfile(forKey: key) {
            return profile != seed
        }
        return true
    }

    nonisolated static func resetGameProfiles(_ profiles: [String: GameCompatibilityProfile], key: String) -> [String: GameCompatibilityProfile] {
        var updated = profiles
        if let seed = seededGameProfile(forKey: key) {
            updated[key] = seed
        } else {
            updated.removeValue(forKey: key)
        }
        return updated
    }

    nonisolated static func parseLaunchArgs(_ text: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var quote: Character?
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                let nextIndex = index + 1
                if nextIndex < characters.count, isEscapableLaunchArgCharacter(characters[nextIndex]) {
                    current.append(characters[nextIndex])
                    index += 2
                } else {
                    current.append(character)
                    index += 1
                }
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
            } else if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }

            index += 1
        }

        if let quote {
            throw ForgeError.message("Unclosed \(quote) quote in launch args.")
        }

        if !current.isEmpty {
            args.append(current)
        }

        return args
    }

    nonisolated private static func isEscapableLaunchArgCharacter(_ character: Character) -> Bool {
        character == "\\"
            || character == "\""
            || character == "'"
            || character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    nonisolated static func formatLaunchArgs(_ args: [String]) -> String {
        args.map { arg in
            if arg.isEmpty { return "\"\"" }
            let needsQuoting = arg.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
                || arg.contains("\"")
                || arg.contains("'")
                || arg.contains("\\")
            guard needsQuoting else { return arg }
            return "\"\(arg.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        .joined(separator: " ")
    }

    nonisolated static func parseEnvOverrides(_ text: String) throws -> [String: String] {
        var env: [String: String] = [:]
        let invalidKeyCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "="))

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw ForgeError.message("Environment line \(index + 1) must use KEY=value.")
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw ForgeError.message("Environment line \(index + 1) is missing a key.")
            }
            guard key.rangeOfCharacter(from: invalidKeyCharacters) == nil else {
                throw ForgeError.message("Environment key \(key) cannot contain spaces or '='.")
            }

            env[key] = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return env
    }

    nonisolated static func formatEnvOverrides(_ env: [String: String]) -> String {
        env.keys.sorted().map { "\($0)=\(env[$0] ?? "")" }.joined(separator: "\n")
    }

    nonisolated static func cleanedProfileNotes(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func gameProfileKey(for app: BottleAppItem) -> String {
        if app.name.caseInsensitiveCompare("PEAK") == .orderedSame { return "name:peak" }
        if let appId = app.steamAppId, !appId.isEmpty { return "steam:\(appId)" }
        return "exe:\(app.path.standardizingPath.lowercased())"
    }
}
