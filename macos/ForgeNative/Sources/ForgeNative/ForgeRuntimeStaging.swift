import Foundation

extension ForgeStore {
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

    nonisolated static func defaultRuntimesDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Wine/Runtimes", isDirectory: true)
    }

    nonisolated static func dxvkSourceRoots(runtimesDir: URL? = nil) -> [URL] {
        let runtimes = runtimesDir ?? defaultRuntimesDirectory()
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

    nonisolated static func dxmtSourceRoots(wineRoot: URL, runtimesDir: URL? = nil) -> [URL] {
        let runtimes = runtimesDir ?? defaultRuntimesDirectory()
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
}
