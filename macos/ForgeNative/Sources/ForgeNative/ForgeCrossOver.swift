import Foundation

extension RuntimeProfile {
    static let crossOverRuntimeId = "crossover-no-gui"

    static func crossOverProfile(winePath explicitWinePath: String? = nil) -> RuntimeProfile? {
        let winePath: String?
        if let explicitWinePath = ForgeStore.trimmedNonEmptyPath(explicitWinePath) {
            winePath = explicitWinePath
        } else {
            winePath = ForgeStore.crossOverWineCandidates()
                .first(where: { FileManager.default.fileExists(atPath: $0) })
        }
        guard let winePath else { return nil }

        return RuntimeProfile(
            id: Self.crossOverRuntimeId,
            name: "CrossOver (no GUI)",
            wine64Path: winePath,
            wineserverPath: ForgeStore.crossOverWineserverPath(winePath: winePath),
            gptkLibPath: nil,
            dxvkPath: nil,
            vkd3dPath: nil,
            moltenvkPath: nil,
            defaultBackend: .none,
            env: ["FORGE_CROSSOVER_MODE": "1"]
        )
    }
}

extension ForgeStore {
    nonisolated static func crossOverWineCandidates(homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            "\(homeDirectory)/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wine",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wine",
            "\(homeDirectory)/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
        ]
    }

    nonisolated static func crossOverBottleRoots(homeDirectory: String = NSHomeDirectory()) -> [URL] {
        var roots: [String] = []
        if let configured = ProcessInfo.processInfo.environment["CX_BOTTLE_PATH"] {
            roots += configured.split(separator: ":").map(String.init)
        }
        roots += [
            "\(homeDirectory)/Library/Application Support/CrossOver/Bottles",
            "\(homeDirectory)/Wine/Bottles"
        ]
        return dedupePathParts(roots)
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }

    nonisolated static func discoverCrossOverBottles() -> [BottleEntry] {
        discoverCrossOverBottles(in: crossOverBottleRoots())
    }

    nonisolated static func discoverCrossOverBottles(in roots: [URL]) -> [BottleEntry] {
        var entries: [BottleEntry] = []
        var seen = Set<String>()

        func addBottle(_ url: URL) {
            let standardized = url.standardizedFileURL
            let key = standardized.path.lowercased()
            guard seen.insert(key).inserted, isCrossOverBottle(prefixPath: standardized.path) else { return }
            entries.append(crossOverBottleEntry(prefixURL: standardized))
        }

        for root in roots {
            addBottle(root)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    addBottle(child)
                }
            }
        }

        return entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    nonisolated static func isCrossOverBottle(prefixPath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: prefixPath).appendingPathComponent("cxbottle.conf").path
        )
    }

    nonisolated static func crossOverBottleEntry(prefixURL: URL) -> BottleEntry {
        BottleEntry(
            name: "CrossOver: \(prefixURL.lastPathComponent)",
            prefixPath: prefixURL.standardizedFileURL.path,
            runtimeProfileId: RuntimeProfile.crossOverRuntimeId,
            graphicsBackend: GraphicsBackend.none,
            envOverrides: [:]
        )
    }

    nonisolated static func crossOverRoot(containingWine winePath: String) -> String? {
        let marker = "/Contents/SharedSupport/CrossOver"
        if let range = winePath.range(of: marker, options: [.caseInsensitive]) {
            return String(winePath[..<range.upperBound])
        }

        let url = URL(fileURLWithPath: winePath).standardizedFileURL
        if url.deletingLastPathComponent().lastPathComponent == "bin" {
            let root = url.deletingLastPathComponent().deletingLastPathComponent()
            if root.lastPathComponent.caseInsensitiveCompare("CrossOver") == .orderedSame {
                return root.path
            }
        }
        return nil
    }

    nonisolated static func crossOverWineserverPath(winePath: String) -> String {
        let wineURL = URL(fileURLWithPath: winePath).standardizedFileURL
        var candidates = [
            wineURL.deletingLastPathComponent().appendingPathComponent("wineserver").path
        ]
        if let root = crossOverRoot(containingWine: winePath) {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            candidates += [
                rootURL.appendingPathComponent("CrossOver-Hosted Application/wineserver").path,
                rootURL.appendingPathComponent("bin/wineserver").path
            ]
        }
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? candidates[0]
    }

    nonisolated static func isCrossOverRuntime(profile: RuntimeProfile, winePath: String? = nil) -> Bool {
        if profile.id == RuntimeProfile.crossOverRuntimeId { return true }
        let candidate = winePath ?? profile.wine64Path
        return crossOverRoot(containingWine: candidate) != nil
    }

    nonisolated static func configureCrossOverEnvironment(
        profile: RuntimeProfile,
        winePath: String,
        prefixPath: String,
        env: inout [String: String]
    ) {
        guard isCrossOverRuntime(profile: profile, winePath: winePath) else { return }

        env["FORGE_CROSSOVER_MODE"] = "1"
        // CrossOver's wrapper locates bottles by CX_BOTTLE, not by WINEPREFIX.
        // An absolute CX_BOTTLE keeps Forge on the selected bottle without
        // opening the CrossOver app or relying on CrossOver's default bottle.
        env["CX_BOTTLE"] = prefixPath
        env["WINEPREFIX"] = prefixPath
        if let root = crossOverRoot(containingWine: winePath) {
            env["CX_ROOT"] = root
        }
        if let wineDebug = env["WINEDEBUG"] {
            env["CX_DEBUGMSG"] = wineDebug
        }

        let parent = URL(fileURLWithPath: prefixPath).deletingLastPathComponent().path
        env["CX_BOTTLE_PATH"] = dedupePathParts(
            [parent] + crossOverBottleRoots().map(\.path) + [env["CX_BOTTLE_PATH"] ?? ""]
        ).joined(separator: ":")
    }
}
