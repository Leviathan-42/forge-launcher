import XCTest
@testable import ForgeNative

final class ForgeRuntimeStagingTests: XCTestCase {
    func testCopyIfDifferentCopiesMissingFileAndCreatesParentDirectory() throws {
        let root = try makeTempDirectory()

        let source = root.appendingPathComponent("source/d3d11.dll")
        let destination = root.appendingPathComponent("target/nested/d3d11.dll")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "runtime-dll".write(to: source, atomically: true, encoding: .utf8)

        try ForgeStore.copyIfDifferent(source, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "runtime-dll")
    }

    func testCopyIfDifferentSkipsExistingFileWithMatchingSize() throws {
        let root = try makeTempDirectory()

        let source = root.appendingPathComponent("source.dll")
        let destination = root.appendingPathComponent("destination.dll")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        try ForgeStore.copyIfDifferent(source, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old")
    }

    func testCopyIfDifferentReplacesExistingFileWithDifferentSize() throws {
        let root = try makeTempDirectory()

        let source = root.appendingPathComponent("source.dll")
        let destination = root.appendingPathComponent("destination.dll")
        try "newer-runtime".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        try ForgeStore.copyIfDifferent(source, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "newer-runtime")
    }

    func testRemoveStagedD3DMetalDllsRemovesOnlyStagedDllFiles() throws {
        let root = try makeTempDirectory()

        let gameDir = root.appendingPathComponent("Game", isDirectory: true)
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        let exe = gameDir.appendingPathComponent("Game.exe")
        try Data().write(to: exe)

        let regularDll = gameDir.appendingPathComponent("dxgi.dll")
        try "staged".write(to: regularDll, atomically: true, encoding: .utf8)

        let symlinkTarget = root.appendingPathComponent("runtime-d3d11.dll")
        try "target".write(to: symlinkTarget, atomically: true, encoding: .utf8)
        let symlinkDll = gameDir.appendingPathComponent("d3d11.dll")
        try FileManager.default.createSymbolicLink(at: symlinkDll, withDestinationURL: symlinkTarget)

        let directoryNamedDll = gameDir.appendingPathComponent("d3d12.dll", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryNamedDll, withIntermediateDirectories: true)

        let unrelatedFile = gameDir.appendingPathComponent("readme.txt")
        try "keep".write(to: unrelatedFile, atomically: true, encoding: .utf8)

        try ForgeStore.removeStagedD3DMetalDlls(exePath: exe.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: regularDll.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: symlinkDll.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryNamedDll.path))
        XCTAssertEqual(try String(contentsOf: unrelatedFile, encoding: .utf8), "keep")
    }

    func testDXVKSourceRootsFindsNestedRuntimeVersionsBeforeBundleRoot() throws {
        let root = try makeTempDirectory()

        let runtimes = root.appendingPathComponent("Runtimes", isDirectory: true)
        let dxvkBundle = runtimes.appendingPathComponent("dxvk-runtime", isDirectory: true)
        let older = dxvkBundle.appendingPathComponent("v1.10", isDirectory: true)
        let newer = dxvkBundle.appendingPathComponent("v2.4", isDirectory: true)
        let unrelated = runtimes.appendingPathComponent("vkd3d-runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        XCTAssertEqual(
            standardizedPaths(ForgeStore.dxvkSourceRoots(runtimesDir: runtimes)),
            standardizedPaths([newer, older, dxvkBundle])
        )
    }

    func testDXMTSourceRootsIncludesRuntimeBundlesAndWineBundledFallback() throws {
        let root = try makeTempDirectory()

        let runtimes = root.appendingPathComponent("Runtimes", isDirectory: true)
        let dxmtBundle = runtimes.appendingPathComponent("dxmt-v0.6", isDirectory: true)
        let dxmtVersion = dxmtBundle.appendingPathComponent("v0.6", isDirectory: true)
        let wineRoot = root.appendingPathComponent("wine-runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: dxmtVersion, withIntermediateDirectories: true)

        XCTAssertEqual(
            standardizedPaths(ForgeStore.dxmtSourceRoots(wineRoot: wineRoot, runtimesDir: runtimes)),
            standardizedPaths([
                dxmtBundle.path,
                dxmtVersion.path,
                wineRoot.appendingPathComponent("lib/dxmt", isDirectory: true).path
            ])
        )
    }

    func testEnsureDXMTInstalledStagesD3D11AliasWithoutRealRuntime() throws {
        let root = try makeTempDirectory()

        let wineRoot = root.appendingPathComponent("wine-runtime", isDirectory: true)
        let winePath = wineRoot.appendingPathComponent("bin/wine")
        let runtimeWin64 = wineRoot.appendingPathComponent("lib/wine/x86_64-windows", isDirectory: true)
        let runtimeWin32 = wineRoot.appendingPathComponent("lib/wine/i386-windows", isDirectory: true)
        let runtimeUnix = wineRoot.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        try FileManager.default.createDirectory(at: winePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeWin64, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeWin32, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeUnix, withIntermediateDirectories: true)

        let runtimes = root.appendingPathComponent("Runtimes", isDirectory: true)
        let dxmtRoot = runtimes.appendingPathComponent("dxmt-test/v0.6", isDirectory: true)
        let windows64 = dxmtRoot.appendingPathComponent("x86_64-windows", isDirectory: true)
        let windows32 = dxmtRoot.appendingPathComponent("i386-windows", isDirectory: true)
        let unix64 = dxmtRoot.appendingPathComponent("x86_64-unix", isDirectory: true)
        try FileManager.default.createDirectory(at: windows64, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: windows32, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unix64, withIntermediateDirectories: true)

        try "d3d11-64".write(to: windows64.appendingPathComponent("d3d11.dll"), atomically: true, encoding: .utf8)
        try "dxgi-64".write(to: windows64.appendingPathComponent("dxgi.dll"), atomically: true, encoding: .utf8)
        try "d3d11-32".write(to: windows32.appendingPathComponent("d3d11.dll"), atomically: true, encoding: .utf8)
        try "winemetal".write(to: unix64.appendingPathComponent("winemetal.so"), atomically: true, encoding: .utf8)

        let prefix = root.appendingPathComponent("prefix", isDirectory: true)
        try ForgeStore.ensureDXMTInstalled(winePath: winePath.path, prefixPath: prefix.path, runtimesDir: runtimes)

        XCTAssertEqual(
            try String(contentsOf: runtimeWin64.appendingPathComponent("dd3d11.dll"), encoding: .utf8),
            "d3d11-64"
        )
        XCTAssertEqual(
            try String(contentsOf: prefix.appendingPathComponent("drive_c/windows/system32/dd3d11.dll"), encoding: .utf8),
            "d3d11-64"
        )
        XCTAssertEqual(
            try String(contentsOf: runtimeWin32.appendingPathComponent("dd3d11.dll"), encoding: .utf8),
            "d3d11-32"
        )
        XCTAssertEqual(
            try String(contentsOf: prefix.appendingPathComponent("drive_c/windows/syswow64/dd3d11.dll"), encoding: .utf8),
            "d3d11-32"
        )
    }

    func testUniqueURLsKeepsFirstPathOccurrence() {
        let first = URL(fileURLWithPath: "/tmp/ForgeRuntime/a")
        let second = URL(fileURLWithPath: "/tmp/ForgeRuntime/b")

        XCTAssertEqual(
            ForgeStore.uniqueURLs([first, second, first]).map(\.path),
            [first.path, second.path]
        )
    }

    func testSteamGameDirectoryReadsInstallDirFromCompactManifest() throws {
        let root = try makeTempDirectory()

        let steamapps = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try #""appid" "123" "name" "Example Game" "installdir" "Example Game Folder""#.write(
            to: steamapps.appendingPathComponent("appmanifest_123.acf"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            ForgeStore.steamGameDirectory(prefixPath: root.path, appId: "123")?.path,
            steamapps.appendingPathComponent("common/Example Game Folder", isDirectory: true).path
        )
    }

    private func standardizedPaths(_ urls: [URL]) -> [String] {
        urls.map { $0.standardizedFileURL.path }
    }

    private func standardizedPaths(_ paths: [String]) -> [String] {
        paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }
}
