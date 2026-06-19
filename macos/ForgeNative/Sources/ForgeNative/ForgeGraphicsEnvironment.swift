import Foundation

extension ForgeStore {
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
}
