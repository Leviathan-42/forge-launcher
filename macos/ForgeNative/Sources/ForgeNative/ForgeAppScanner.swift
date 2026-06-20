import Foundation

private enum AppScanLimit {
    static let maxApps = 120
    static let maxDepth = 5
}

private let hiddenExecutableFileNames: Set<String> = [
    "steamwebhelper.exe", "steamerrorreporter.exe", "gldriverquery.exe", "gldriverquery64.exe",
    "vulkandriverquery.exe", "vulkandriverquery64.exe", "steamservice.exe", "steam_monitor.exe",
    "crashhandler.exe", "crashpad_handler.exe", "uninstall.exe", "unins000.exe", "unins001.exe",
    "dxsetup.exe", "vc_redist.x64.exe", "vc_redist.x86.exe", "installscript.vdf.exe"
]

private let managedLauncherContainerSuffixes = [
    "/program files/steam",
    "/program files (x86)/steam",
    "/program files (x86)/epic games",
    "/program files/epic games",
    "/program files/battle.net",
    "/program files (x86)/battle.net",
    "/program files/electronic arts",
    "/program files (x86)/ubisoft",
    "/program files/rockstar games"
]

private let managedLauncherPathMarkers = [
    "/steam/",
    "/epic games/",
    "/battle.net/",
    "/electronic arts/",
    "/ubisoft/",
    "/rockstar games/"
]

private let visibleManagedLauncherFileNames: Set<String> = [
    "steam.exe",
    "epicgameslauncher.exe",
    "battle.net.exe",
    "ealauncher.exe",
    "ubisoftconnect.exe"
]

extension ForgeStore {
    nonisolated static func findSteam(prefixPath: String) -> String? {
        steamCandidates(prefixPath: prefixPath).first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    nonisolated static func scanApps(prefixPath: String) -> [BottleAppItem] {
        var apps: [BottleAppItem] = []
        var seen = Set<String>()

        for path in knownLauncherPaths(prefixPath: prefixPath) where FileManager.default.fileExists(atPath: path) {
            push(path: path, kind: "launcher", into: &apps, seen: &seen)
        }

        scanSteamGames(prefixPath: prefixPath, into: &apps, seen: &seen)

        for root in programRoots(prefixPath: prefixPath) {
            collectExes(URL(fileURLWithPath: root), depth: 0, into: &apps, seen: &seen)
            if apps.count >= AppScanLimit.maxApps { break }
        }

        apps.sort {
            let leftRank = $0.kindSortRank
            let rightRank = $1.kindSortRank
            if leftRank != rightRank { return leftRank < rightRank }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if apps.count > AppScanLimit.maxApps {
            apps.removeSubrange(AppScanLimit.maxApps..<apps.count)
        }
        return apps
    }

    nonisolated static func collectExes(
        _ dir: URL,
        depth: Int,
        into apps: inout [BottleAppItem],
        seen: inout Set<String>
    ) {
        guard depth <= AppScanLimit.maxDepth, apps.count < AppScanLimit.maxApps else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            if apps.count >= AppScanLimit.maxApps { return }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                if shouldDescendForUserApps(entry.path) {
                    collectExes(entry, depth: depth + 1, into: &apps, seen: &seen)
                }
            } else if entry.pathExtension.caseInsensitiveCompare("exe") == .orderedSame,
                      isUserVisibleExe(entry.path) {
                push(path: entry.path, kind: guessKind(entry.path), into: &apps, seen: &seen)
            }
        }
    }

    nonisolated static func push(
        path: String,
        kind: String,
        into apps: inout [BottleAppItem],
        seen: inout Set<String>,
        name: String? = nil,
        steamAppId: String? = nil
    ) {
        let normalized = path.standardizingPath
        guard seen.insert(normalized.lowercased()).inserted else { return }
        apps.append(
            BottleAppItem(
                name: name ?? displayName(for: normalized),
                path: normalized,
                kind: kind,
                steamAppId: steamAppId
            )
        )
    }

    nonisolated static func scanSteamGames(
        prefixPath: String,
        into apps: inout [BottleAppItem],
        seen: inout Set<String>
    ) {
        let steamApps = URL(fileURLWithPath: prefixPath)
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
        guard let manifests = try? FileManager.default.contentsOfDirectory(
            at: steamApps,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for manifest in manifests {
            guard manifest.lastPathComponent.hasPrefix("appmanifest_"),
                  manifest.pathExtension == "acf" else { continue }
            guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
            let appId = acfValue("appid", in: text)
            let name = acfValue("name", in: text)
            guard let installDir = acfValue("installdir", in: text), let appId else { continue }
            let gameDir = steamApps.appendingPathComponent("common").appendingPathComponent(installDir)
            guard let exe = primaryGameExe(in: gameDir) else { continue }
            push(path: exe.path, kind: "game", into: &apps, seen: &seen, name: name, steamAppId: appId)
        }
    }

    nonisolated static func acfValue(_ key: String, in text: String) -> String? {
        let pattern = "\\\"\(NSRegularExpression.escapedPattern(for: key))\\\"\\s+\\\"([^\\\"]+)\\\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    nonisolated static func primaryGameExe(in dir: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let exes = entries.filter { entry in
            let file = entry.lastPathComponent.lowercased()
            return entry.pathExtension.caseInsensitiveCompare("exe") == .orderedSame
                && !isHiddenHelperExecutableName(file)
        }
        if let exact = exes.first(where: {
            $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(dir.lastPathComponent) == .orderedSame
        }) {
            return exact
        }
        return exes.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }.first
    }

    nonisolated static func shouldDescendForUserApps(_ path: String) -> Bool {
        let raw = normalizedForFilter(path)
        return !raw.contains("/program files/common files")
            && !raw.contains("/program files (x86)/common files")
            && !raw.contains("/internet explorer")
            && !raw.contains("/windows media player")
            && !raw.contains("/windows nt")
            && !isManagedLauncherContainer(raw)
    }

    nonisolated static func isUserVisibleExe(_ path: String) -> Bool {
        let raw = normalizedForFilter(path)
        let file = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if raw.contains("/internet explorer/")
            || raw.contains("/windows media player/")
            || raw.contains("/windows nt/")
            || raw.contains("/common files/")
            || isManagedLauncherChild(raw, file: file) {
            return false
        }

        return !isHiddenHelperExecutableName(file)
    }

    nonisolated static func isHiddenHelperExecutableName(_ file: String) -> Bool {
        let normalized = file.lowercased()
        return hiddenExecutableFileNames.contains(normalized)
            || normalized.hasPrefix("unins")
            || normalized.contains("crash")
            || normalized.contains("reporter")
    }

    nonisolated static func isManagedLauncherContainer(_ raw: String) -> Bool {
        managedLauncherContainerSuffixes.contains { raw.hasSuffix($0) }
    }

    nonisolated static func isManagedLauncherChild(_ raw: String, file: String) -> Bool {
        if visibleManagedLauncherFileNames.contains(file)
            || (file == "launcher.exe" && raw.contains("/rockstar games/launcher/")) {
            return false
        }

        return managedLauncherPathMarkers.contains { raw.contains($0) }
    }

    nonisolated static func guessKind(_ path: String) -> String {
        let raw = normalizedForFilter(path)
        if isSteamExecutable(path, forceSteamMode: false)
            || raw.contains("/launcher/")
            || raw.contains("battle.net")
            || raw.contains("ubisoft") {
            return "launcher"
        }
        return "game"
    }

    nonisolated static func displayName(for path: String) -> String {
        let file = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if file.caseInsensitiveCompare("steam") == .orderedSame { return "Steam" }
        return file
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizedForFilter(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    nonisolated static func steamCandidates(prefixPath: String) -> [String] {
        let driveC = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c")
        return [
            driveC.appendingPathComponent("Program Files (x86)/Steam/steam.exe").path,
            driveC.appendingPathComponent("Program Files/Steam/steam.exe").path
        ]
    }

    nonisolated static func knownLauncherPaths(prefixPath: String) -> [String] {
        let driveC = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c")
        return steamCandidates(prefixPath: prefixPath) + [
            driveC
                .appendingPathComponent("Program Files (x86)/Epic Games")
                .appendingPathComponent("Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe")
                .path,
            driveC
                .appendingPathComponent("Program Files (x86)/Epic Games")
                .appendingPathComponent("Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe")
                .path,
            driveC.appendingPathComponent("Program Files (x86)/Battle.net/Battle.net.exe").path,
            driveC.appendingPathComponent("Program Files/Battle.net/Battle.net.exe").path,
            driveC.appendingPathComponent("Program Files/Electronic Arts/EA Desktop/EA Desktop/EALauncher.exe").path,
            driveC
                .appendingPathComponent("Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe")
                .path,
            driveC.appendingPathComponent("Program Files/Rockstar Games/Launcher/Launcher.exe").path
        ]
    }

    nonisolated static func programRoots(prefixPath: String) -> [String] {
        let driveC = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c")
        return [
            driveC.appendingPathComponent("Program Files").path,
            driveC.appendingPathComponent("Program Files (x86)").path,
            driveC.appendingPathComponent("users/Public/Desktop").path
        ]
    }
}
