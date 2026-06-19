import XCTest
@testable import ForgeNative

final class CompatibilityProfileTests: XCTestCase {
    func testSeededAgainstTheStormProfileUsesDXMT() throws {
        let profiles = Dictionary(uniqueKeysWithValues: ForgeStore.seededGameProfiles().map { ($0.id, $0) })
        let profile = try XCTUnwrap(profiles["steam:1336490"])

        XCTAssertEqual(profile.displayName, "Against the Storm")
        XCTAssertEqual(profile.backendOverride, .dxmt)
        XCTAssertEqual(profile.launchArgs, ["-screen-fullscreen", "1"])
        XCTAssertTrue(profile.notes?.localizedCaseInsensitiveContains("D3D11") == true)
    }

    func testSeededPeakProfileKeepsKnownUnityArgs() throws {
        let profiles = Dictionary(uniqueKeysWithValues: ForgeStore.seededGameProfiles().map { ($0.id, $0) })
        let profile = try XCTUnwrap(profiles["name:peak"])

        XCTAssertEqual(profile.backendOverride, .dxvkVkd3d)
        XCTAssertEqual(profile.launchArgs, ["-force-vulkan", "-force-gfx-st", "-disable-gpu-skinning", "-screen-fullscreen", "1"])
    }

    func testGameProfileKeyPrefersSteamAppIdBeforePath() {
        let app = BottleAppItem(
            name: "Against the Storm",
            path: "/tmp/Against the Storm/Against the Storm.exe",
            kind: "game",
            steamAppId: "1336490"
        )

        XCTAssertEqual(ForgeStore.gameProfileKey(for: app), "steam:1336490")
    }

    func testLoadGameProfilesMigratesOldAgainstTheStormD3DMetalOverrideToDXMT() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeNativeTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let staleProfile = GameCompatibilityProfile(
            id: "steam:1336490",
            displayName: "Against the Storm",
            backendOverride: .d3dMetal,
            launchArgs: [],
            env: [:],
            notes: "old stale profile"
        )
        let data = try JSONEncoder.forge.encode([staleProfile])
        try data.write(to: support.appendingPathComponent("game_compatibility_profiles.json"), options: .atomic)

        let profiles = try ForgeStore.loadGameProfiles(from: support)

        XCTAssertEqual(profiles["steam:1336490"]?.backendOverride, .dxmt)
        XCTAssertEqual(profiles["steam:1336490"]?.launchArgs, ["-screen-fullscreen", "1"])
        XCTAssertTrue(profiles["steam:1336490"]?.notes?.localizedCaseInsensitiveContains("DXMT") == true)
    }
}
