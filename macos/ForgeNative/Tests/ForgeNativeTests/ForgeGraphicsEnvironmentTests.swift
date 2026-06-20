import XCTest
@testable import ForgeNative

private let gptkLibPath = "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib"
private let homebrewMoltenVkIcdPath = "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"

final class ForgeGraphicsEnvironmentTests: XCTestCase {
    func testDedupePathPartsKeepsFirstNonEmptyOccurrence() {
        XCTAssertEqual(
            ForgeStore.dedupePathParts(["", "/opt/runtime/lib", "/usr/local/lib", "/opt/runtime/lib", ""]),
            ["/opt/runtime/lib", "/usr/local/lib"]
        )
    }

    func testBuildDyldPathAddsGptkExternalSearchPaths() {
        let dyldPath = ForgeStore.buildDyldPath(
            gptkLibPath: "\(gptkLibPath)/external",
            existing: "/opt/forge-wine/lib"
        )

        XCTAssertEqual(
            dyldPath,
            [
                "\(gptkLibPath)/external",
                "\(gptkLibPath)/external/D3DMetal.framework/Versions/A",
                gptkLibPath,
                "/opt/forge-wine/lib"
            ].joined(separator: ":")
        )
    }

    func testBuildDyldPathTrimsConfiguredGptkPath() {
        let dyldPath = ForgeStore.buildDyldPath(
            gptkLibPath: "  \(gptkLibPath)  \n",
            existing: ""
        )

        XCTAssertEqual(
            dyldPath,
            [
                gptkLibPath,
                "\(gptkLibPath)/external",
                "\(gptkLibPath)/external/D3DMetal.framework/Versions/A"
            ].joined(separator: ":")
        )
    }

    func testRuntimeLibrarySearchPathPrependsRuntimePath() {
        XCTAssertEqual(
            ForgeStore.runtimeLibrarySearchPath(runtimeLibPath: "/opt/runtime/lib", existing: "/usr/local/lib"),
            "/opt/runtime/lib:/usr/local/lib"
        )
        XCTAssertEqual(
            ForgeStore.runtimeLibrarySearchPath(runtimeLibPath: "/opt/runtime/lib", existing: "/opt/runtime/lib"),
            "/opt/runtime/lib"
        )
    }

    func testRuntimeFallbackLibrarySearchPathIncludesHomebrewFallbacks() {
        XCTAssertEqual(
            ForgeStore.runtimeFallbackLibrarySearchPath(runtimeLibPath: "/opt/runtime/lib", existing: "/custom/lib"),
            "/opt/runtime/lib:/opt/homebrew/lib:/usr/local/lib:/custom/lib"
        )
        XCTAssertEqual(
            ForgeStore.runtimeFallbackLibrarySearchPath(
                runtimeLibPath: "/opt/runtime/lib",
                existing: "/opt/homebrew/lib"
            ),
            "/opt/runtime/lib:/opt/homebrew/lib:/usr/local/lib"
        )
    }

    func testMoltenVkCandidatesExpandConfiguredTildePath() {
        let configured = "~/Wine/Runtimes/moltenvk"
        let expanded = (configured as NSString).expandingTildeInPath

        let candidates = ForgeStore.moltenVkIcdCandidates(configuredPath: configured)

        XCTAssertTrue(candidates.contains(expanded))
        XCTAssertTrue(
            candidates.contains(URL(fileURLWithPath: expanded).appendingPathComponent("MoltenVK_icd.json").path)
        )
        XCTAssertTrue(candidates.contains(homebrewMoltenVkIcdPath))
    }

    func testMoltenVkCandidatesTrimAndDedupeConfiguredPath() {
        let configured = "  \(homebrewMoltenVkIcdPath)  "

        let candidates = ForgeStore.moltenVkIcdCandidates(configuredPath: configured)

        XCTAssertEqual(
            candidates.filter { $0 == homebrewMoltenVkIcdPath }.count,
            1
        )
    }

    func testGptkWineLibBaseTrimsConfiguredPath() {
        let base = ForgeStore.gptkWineLibBase(
            gptkLibPath: "  \(gptkLibPath)/external  "
        )

        XCTAssertEqual(base?.path, gptkLibPath)
    }

    func testTrimmedNonEmptyPathRejectsBlankValues() {
        XCTAssertNil(ForgeStore.trimmedNonEmptyPath(nil))
        XCTAssertNil(ForgeStore.trimmedNonEmptyPath(" \n\t "))
        XCTAssertEqual(ForgeStore.trimmedNonEmptyPath(" /opt/runtime/lib "), "/opt/runtime/lib")
    }

    func testConfigureMoltenVkUsesConfiguredIcdFile() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let icd = root.appendingPathComponent("MoltenVK_icd.json")
        try "{}".write(to: icd, atomically: true, encoding: .utf8)

        var env: [String: String] = [:]
        ForgeStore.configureMoltenVK(
            profile: makeProfile(moltenvkPath: icd.path),
            config: .defaults,
            env: &env
        )

        XCTAssertEqual(env["VK_ICD_FILENAMES"], icd.path)
        XCTAssertEqual(env["VK_DRIVER_FILES"], icd.path)
        XCTAssertEqual(env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"], "1")
        XCTAssertEqual(env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"], "1")
        XCTAssertEqual(env["MOLTENVK_CONFIG_LOG_LEVEL"], "0")
    }

    func testConfigureMoltenVkSkipsConfiguredDirectoryForNestedIcdFile() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let icd = root.appendingPathComponent("MoltenVK_icd.json")
        try "{}".write(to: icd, atomically: true, encoding: .utf8)

        var env: [String: String] = [:]
        ForgeStore.configureMoltenVK(
            profile: makeProfile(moltenvkPath: root.path),
            config: .defaults,
            env: &env
        )

        XCTAssertEqual(env["VK_ICD_FILENAMES"], icd.path)
        XCTAssertEqual(env["VK_DRIVER_FILES"], icd.path)
    }

    func testConfigureMoltenVkPreservesExistingIcdEnvironment() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let icd = root.appendingPathComponent("MoltenVK_icd.json")
        try "{}".write(to: icd, atomically: true, encoding: .utf8)

        var env = ["VK_ICD_FILENAMES": "/custom/icd.json"]
        ForgeStore.configureMoltenVK(
            profile: makeProfile(moltenvkPath: icd.path),
            config: .defaults,
            env: &env
        )

        XCTAssertEqual(env, ["VK_ICD_FILENAMES": "/custom/icd.json"])
    }

    private func makeProfile(moltenvkPath: String?) -> RuntimeProfile {
        RuntimeProfile(
            id: "test",
            name: "Test",
            wine64Path: "/tmp/wine",
            wineserverPath: nil,
            gptkLibPath: nil,
            dxvkPath: nil,
            vkd3dPath: nil,
            moltenvkPath: moltenvkPath,
            defaultBackend: .dxvk,
            env: [:]
        )
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeGraphicsEnvironmentTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
