import XCTest
@testable import ForgeNative

final class ForgeLaunchSupportTests: XCTestCase {
    func testSteamSafeArgsPrependsCefSandboxFlags() {
        XCTAssertEqual(
            ForgeStore.steamSafeArgs(["-applaunch", "2357570"]),
            ["-no-cef-sandbox", "-cef-disable-sandbox", "-applaunch", "2357570"]
        )
    }

    func testDedupePathPartsKeepsFirstNonEmptyOccurrence() {
        XCTAssertEqual(
            ForgeStore.dedupePathParts(["", "/opt/runtime/lib", "/usr/local/lib", "/opt/runtime/lib", ""]),
            ["/opt/runtime/lib", "/usr/local/lib"]
        )
    }

    func testBuildDyldPathAddsGptkExternalSearchPaths() {
        let dyldPath = ForgeStore.buildDyldPath(
            gptkLibPath: "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external",
            existing: "/opt/forge-wine/lib"
        )

        XCTAssertEqual(
            dyldPath,
            [
                "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external",
                "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework/Versions/A",
                "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib",
                "/opt/forge-wine/lib"
            ].joined(separator: ":")
        )
    }

    func testMoltenVkCandidatesExpandConfiguredTildePath() {
        let configured = "~/Wine/Runtimes/moltenvk"
        let expanded = (configured as NSString).expandingTildeInPath

        let candidates = ForgeStore.moltenVkIcdCandidates(configuredPath: configured)

        XCTAssertTrue(candidates.contains(expanded))
        XCTAssertTrue(candidates.contains(URL(fileURLWithPath: expanded).appendingPathComponent("MoltenVK_icd.json").path))
        XCTAssertTrue(candidates.contains("/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"))
    }

    func testSteamGameDirectoryReadsInstallDirFromManifest() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeLaunchSupportTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: prefix) }

        let steamapps = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try """
        "AppState"
        {
            "appid" "123"
            "installdir" "Example Game"
        }
        """.write(to: steamapps.appendingPathComponent("appmanifest_123.acf"), atomically: true, encoding: .utf8)

        XCTAssertEqual(
            ForgeStore.steamGameDirectory(prefixPath: prefix.path, appId: "123")?.path,
            steamapps.appendingPathComponent("common/Example Game", isDirectory: true).path
        )
    }
}
