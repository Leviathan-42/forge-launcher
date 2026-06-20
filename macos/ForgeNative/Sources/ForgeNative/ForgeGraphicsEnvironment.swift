import Foundation

private let moltenVkIcdRelativePath = "share/vulkan/icd.d/MoltenVK_icd.json"
private let gptkWineDllSearchSubpaths = [
    "wine/x86_64-windows",
    "wine/x86_64-unix",
    "wine/i386-windows",
    "wine/x86_32on64-unix"
]
let defaultMoltenVkIcdPath = "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"

extension ForgeStore {
    nonisolated static func configureMoltenVK(
        profile: RuntimeProfile,
        config: AppConfig,
        env: inout [String: String]
    ) {
        if let existing = env["VK_ICD_FILENAMES"],
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        let configured = profile.moltenvkPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidates = moltenVkIcdCandidates(configuredPath: configured)
        if let icd = candidates.first(where: isExistingRegularFile) {
            env["VK_ICD_FILENAMES"] = icd
            env["VK_DRIVER_FILES"] = icd
        }

        env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] ?? "1"
        env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] = env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] ?? "1"
        env["MOLTENVK_CONFIG_LOG_LEVEL"] = env["MOLTENVK_CONFIG_LOG_LEVEL"] ?? "0"
    }

    nonisolated static func moltenVkIcdCandidates(configuredPath rawConfiguredPath: String) -> [String] {
        let configuredPath = trimmedNonEmptyPath(rawConfiguredPath) ?? ""
        var candidates: [String] = []
        func add(_ path: String) {
            if let path = trimmedNonEmptyPath(path) {
                candidates.append((path as NSString).expandingTildeInPath)
            }
        }

        add(configuredPath)
        if !configuredPath.isEmpty {
            add(URL(fileURLWithPath: configuredPath).appendingPathComponent(moltenVkIcdRelativePath).path)
            add(URL(fileURLWithPath: configuredPath).appendingPathComponent("MoltenVK_icd.json").path)
        }
        add(defaultMoltenVkIcdPath)
        add("/usr/local/share/vulkan/icd.d/MoltenVK_icd.json")
        add("/opt/homebrew/Cellar/molten-vk/share/vulkan/icd.d/MoltenVK_icd.json")
        return dedupePathParts(candidates)
    }

    nonisolated static func buildDyldPath(gptkLibPath: String?, existing: String) -> String {
        var parts: [String] = []
        if let gptkLibPath = trimmedNonEmptyPath(gptkLibPath) {
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

    nonisolated static func runtimeLibrarySearchPath(runtimeLibPath: String, existing: String?) -> String {
        dedupePathParts([runtimeLibPath, existing ?? ""]).joined(separator: ":")
    }

    nonisolated static func runtimeFallbackLibrarySearchPath(runtimeLibPath: String, existing: String?) -> String {
        dedupePathParts([
            runtimeLibPath,
            "/opt/homebrew/lib",
            "/usr/local/lib",
            existing ?? ""
        ]).joined(separator: ":")
    }

    nonisolated static func gptkWineLibBase(gptkLibPath: String?) -> URL? {
        guard let gptkLibPath = trimmedNonEmptyPath(gptkLibPath) else { return nil }
        let configured = URL(fileURLWithPath: gptkLibPath)
        if configured.lastPathComponent.caseInsensitiveCompare("external") == .orderedSame {
            return configured.deletingLastPathComponent()
        }
        if configured.lastPathComponent.caseInsensitiveCompare("lib") == .orderedSame {
            return configured
        }
        return configured
    }

    nonisolated static func gptkWineDllSearchPaths(gptkBase: URL) -> [String] {
        gptkWineDllSearchSubpaths
            .map { gptkBase.appendingPathComponent($0).path }
            .filter { FileManager.default.fileExists(atPath: $0) }
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

    nonisolated static func trimmedNonEmptyPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func isExistingRegularFile(path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
}
