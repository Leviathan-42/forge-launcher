import Foundation

private let stagedD3DMetalDllNames = ["dxgi.dll", "d3d9.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll"]
private let dxvkDllNames = ["dxgi.dll", "d3d9.dll", "d3d10core.dll", "d3d10.dll", "d3d10_1.dll", "d3d11.dll"]
private let dxmtD3D11DllName = "d3d11.dll"
private let dxmtD3D11AliasName = "dd3d11.dll"
private let dxmtDllNames = [dxmtD3D11DllName, "dxgi.dll", "d3d10core.dll", "winemetal.dll"]
private let wineD3D12ImportDllNames = ["d3d12.dll", "d3d12core.dll"]

extension ForgeStore {
    nonisolated static func removeStagedD3DMetalDlls(exePath: String) throws {
        let gameDir = URL(fileURLWithPath: exePath).deletingLastPathComponent()
        for dll in stagedD3DMetalDllNames {
            let target = gameDir.appendingPathComponent(dll)
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
            if isRegularFileOrSymlink(attrs) {
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
            throw ForgeError.message(
                "DXVK runtime files were not found. " +
                    "Expected ~/Wine/Runtimes/dxvk-*/dxvk-*/x64/d3d11.dll."
            )
        }

        var targetDirs: [URL] = []
        let exeURL = URL(fileURLWithPath: exePath)
        if !isSteamExecutable(exePath, forceSteamMode: false) {
            targetDirs.append(exeURL.deletingLastPathComponent())
        }
        if let steamAppId, let steamGameDir = steamGameDirectory(prefixPath: prefixPath, appId: steamAppId) {
            targetDirs.append(steamGameDir)
        }

        let uniqueDirs = uniqueURLs(targetDirs)
        let x64 = sourceRoot.appendingPathComponent("x64", isDirectory: true)
        for dir in uniqueDirs {
            for dll in dxvkDllNames {
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
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: runtimes,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries where entry.lastPathComponent.lowercased().contains("dxvk") {
                if let children = try? FileManager.default.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    roots.append(contentsOf: children.sorted {
                        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
                    })
                }
                roots.append(entry)
            }
        }
        return uniqueURLs(roots)
    }

    nonisolated static func steamGameDirectory(prefixPath: String, appId: String) -> URL? {
        let steamapps = URL(fileURLWithPath: prefixPath)
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appId).acf")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8),
              let installDir = acfValue("installdir", in: text) else { return nil }
        return steamapps
            .appendingPathComponent("common", isDirectory: true)
            .appendingPathComponent(installDir, isDirectory: true)
    }

    nonisolated static func ensureDXMTInstalled(winePath: String, prefixPath: String, runtimesDir: URL? = nil) throws {
        let fm = FileManager.default
        let wineRoot = URL(fileURLWithPath: winePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimeWin64Dir = wineRoot.appendingPathComponent("lib/wine/x86_64-windows", isDirectory: true)
        let runtimeWin32Dir = wineRoot.appendingPathComponent("lib/wine/i386-windows", isDirectory: true)
        let runtimeUnixDir = wineRoot.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let system32 = URL(fileURLWithPath: prefixPath)
            .appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = URL(fileURLWithPath: prefixPath)
            .appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)

        guard fm.fileExists(atPath: runtimeWin64Dir.path), fm.fileExists(atPath: runtimeUnixDir.path) else {
            throw ForgeError.message(
                "DXMT needs a Wine runtime with lib/wine/x86_64-windows " +
                    "and x86_64-unix directories."
            )
        }
        try fm.createDirectory(at: system32, withIntermediateDirectories: true)
        try fm.createDirectory(at: syswow64, withIntermediateDirectories: true)

        let sourceRoots = dxmtSourceRoots(wineRoot: wineRoot, runtimesDir: runtimesDir)
        guard let sourceRoot = sourceRoots.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("x86_64-windows/\(dxmtD3D11DllName)").path)
                && fm.fileExists(atPath: $0.appendingPathComponent("x86_64-windows/dxgi.dll").path)
                && fm.fileExists(atPath: $0.appendingPathComponent("x86_64-unix/winemetal.so").path)
        }) else {
            throw ForgeError.message(
                "DXMT runtime files were not found. " +
                    "Expected ~/Wine/Runtimes/dxmt-v*/v*/x86_64-windows and x86_64-unix."
            )
        }

        let windows64Source = sourceRoot.appendingPathComponent("x86_64-windows", isDirectory: true)
        let windows32Source = sourceRoot.appendingPathComponent("i386-windows", isDirectory: true)
        let unixSource = sourceRoot.appendingPathComponent("x86_64-unix", isDirectory: true)
        for dll in dxmtDllNames {
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
        try copyIfDifferent(
            windows64Source.appendingPathComponent(dxmtD3D11DllName),
            to: runtimeWin64Dir.appendingPathComponent(dxmtD3D11AliasName)
        )
        try copyIfDifferent(
            windows64Source.appendingPathComponent(dxmtD3D11DllName),
            to: system32.appendingPathComponent(dxmtD3D11AliasName)
        )
        if fm.fileExists(atPath: windows32Source.appendingPathComponent(dxmtD3D11DllName).path),
           fm.fileExists(atPath: runtimeWin32Dir.path) {
            try copyIfDifferent(
                windows32Source.appendingPathComponent(dxmtD3D11DllName),
                to: runtimeWin32Dir.appendingPathComponent(dxmtD3D11AliasName)
            )
            try copyIfDifferent(
                windows32Source.appendingPathComponent(dxmtD3D11DllName),
                to: syswow64.appendingPathComponent(dxmtD3D11AliasName)
            )
        }
        // Some UE5 games ship native DirectML next to the D3D11 executable. DirectML
        // imports d3d12.dll even when the game is forced to the D3D11 RHI, so keep
        // Wine's D3D12 PE stubs physically present in the prefix for native import
        // resolution while DXMT handles d3d11/dxgi.
        for dll in wineD3D12ImportDllNames {
            let source64 = runtimeWin64Dir.appendingPathComponent(dll)
            if fm.fileExists(atPath: source64.path) {
                try copyIfDifferent(source64, to: system32.appendingPathComponent(dll))
            }
            let source32 = runtimeWin32Dir.appendingPathComponent(dll)
            if fm.fileExists(atPath: source32.path), fm.fileExists(atPath: runtimeWin32Dir.path) {
                try copyIfDifferent(source32, to: syswow64.appendingPathComponent(dll))
            }
        }
        try copyIfDifferent(
            unixSource.appendingPathComponent("winemetal.so"),
            to: runtimeUnixDir.appendingPathComponent("winemetal.so")
        )
    }

    nonisolated static func dxmtSourceRoots(wineRoot: URL, runtimesDir: URL? = nil) -> [URL] {
        let runtimes = runtimesDir ?? defaultRuntimesDirectory()
        var roots: [URL] = []
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: runtimes,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries where entry.lastPathComponent.lowercased().contains("dxmt") {
                roots.append(entry)
                if let children = try? FileManager.default.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    roots.append(contentsOf: children)
                }
            }
        }
        roots.append(wineRoot.appendingPathComponent("lib/dxmt", isDirectory: true))
        return uniqueURLs(roots)
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

    nonisolated static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}

private func isRegularFileOrSymlink(_ attributes: [FileAttributeKey: Any]?) -> Bool {
    let type = attributes?[.type] as? FileAttributeType
    return type == .typeRegular || type == .typeSymbolicLink
}
