import XCTest
@testable import ForgeNative

final class ForgeRuntimeStagingTests: XCTestCase {
    func testCopyIfDifferentCopiesMissingFileAndCreatesParentDirectory() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source/d3d11.dll")
        let destination = root.appendingPathComponent("target/nested/d3d11.dll")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "runtime-dll".write(to: source, atomically: true, encoding: .utf8)

        try ForgeStore.copyIfDifferent(source, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "runtime-dll")
    }

    func testCopyIfDifferentSkipsExistingFileWithMatchingSize() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.dll")
        let destination = root.appendingPathComponent("destination.dll")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        try ForgeStore.copyIfDifferent(source, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old")
    }

    func testCopyIfDifferentReplacesExistingFileWithDifferentSize() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.dll")
        let destination = root.appendingPathComponent("destination.dll")
        try "newer-runtime".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        try ForgeStore.copyIfDifferent(source, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "newer-runtime")
    }

    func testRemoveStagedD3DMetalDllsRemovesOnlyStagedDllFiles() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

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
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

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
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

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

    func testSteamGameDirectoryReadsInstallDirFromCompactManifest() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

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

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeRuntimeStagingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
