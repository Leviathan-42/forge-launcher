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

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeRuntimeStagingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
