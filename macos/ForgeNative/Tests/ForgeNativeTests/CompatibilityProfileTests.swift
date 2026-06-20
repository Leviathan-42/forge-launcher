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
        XCTAssertEqual(
            profile.launchArgs,
            ["-force-vulkan", "-force-gfx-st", "-disable-gpu-skinning", "-screen-fullscreen", "1"]
        )
    }

    func testSeededAmongUsProfileUsesWineD3DVulkanFallback() throws {
        let profiles = Dictionary(uniqueKeysWithValues: ForgeStore.seededGameProfiles().map { ($0.id, $0) })
        let profile = try XCTUnwrap(profiles["steam:945360"])

        XCTAssertEqual(profile.displayName, "Among Us")
        XCTAssertEqual(profile.backendOverride, .wineBuiltin)
        XCTAssertEqual(profile.env["WINE_D3D_CONFIG"], "renderer=vulkan")
        XCTAssertEqual(profile.env["VK_ICD_FILENAMES"], "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json")
        XCTAssertTrue(profile.notes?.localizedCaseInsensitiveContains("32-bit Unity") == true)
    }

    func testSeededOverwatchProfileUsesDXVKVKD3DAndStackGuarantee() throws {
        let profiles = Dictionary(uniqueKeysWithValues: ForgeStore.seededGameProfiles().map { ($0.id, $0) })
        let profile = try XCTUnwrap(profiles["steam:2357570"])

        XCTAssertEqual(profile.displayName, "Overwatch 2")
        XCTAssertEqual(profile.backendOverride, .dxvkVkd3d)
        XCTAssertEqual(profile.env["FORGE_STACK_GUARANTEE_BYTES"], "262144")
        XCTAssertTrue(profile.notes?.localizedCaseInsensitiveContains("do not use D3DMetal") == true)
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
        let support = try makeSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let staleProfile = GameCompatibilityProfile(
            id: "steam:1336490",
            displayName: "Against the Storm",
            backendOverride: .d3dMetal,
            launchArgs: [],
            env: [:],
            notes: "old stale profile"
        )
        try writeProfiles([staleProfile], to: support)

        let profiles = try ForgeStore.loadGameProfiles(from: support)

        XCTAssertEqual(profiles["steam:1336490"]?.backendOverride, .dxmt)
        XCTAssertEqual(profiles["steam:1336490"]?.launchArgs, ["-screen-fullscreen", "1"])
        XCTAssertTrue(profiles["steam:1336490"]?.notes?.localizedCaseInsensitiveContains("DXMT") == true)
    }

    func testLoadGameProfilesMigratesAmongUsNonWineD3DOverrideToSeed() throws {
        let support = try makeSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let staleProfile = GameCompatibilityProfile(
            id: "steam:945360",
            displayName: "Among Us",
            backendOverride: .dxmt,
            launchArgs: ["-old"],
            env: ["OLD": "1"],
            notes: "stale"
        )
        try writeProfiles([staleProfile], to: support)

        let profiles = try ForgeStore.loadGameProfiles(from: support)
        let seed = try XCTUnwrap(ForgeStore.seededGameProfile(forKey: "steam:945360"))

        XCTAssertEqual(profiles["steam:945360"], seed)
    }

    func testLoadGameProfilesMigratesOverwatchD3DMetalOverrideToSeed() throws {
        let support = try makeSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let staleProfile = GameCompatibilityProfile(
            id: "steam:2357570",
            displayName: "Overwatch 2",
            backendOverride: .d3dMetal,
            launchArgs: ["-old"],
            env: ["OLD": "1"],
            notes: "stale"
        )
        try writeProfiles([staleProfile], to: support)

        let profiles = try ForgeStore.loadGameProfiles(from: support)
        let seed = try XCTUnwrap(ForgeStore.seededGameProfile(forKey: "steam:2357570"))

        XCTAssertEqual(profiles["steam:2357570"], seed)
    }

    func testLoadGameProfilesAddsOverwatchStackGuaranteeToExistingProfile() throws {
        let support = try makeSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        let existingProfile = GameCompatibilityProfile(
            id: "steam:2357570",
            displayName: "Overwatch 2",
            backendOverride: .dxvk,
            launchArgs: ["-custom"],
            env: ["CUSTOM": "1"],
            notes: "custom"
        )
        try writeProfiles([existingProfile], to: support)

        let profiles = try ForgeStore.loadGameProfiles(from: support)
        let profile = try XCTUnwrap(profiles["steam:2357570"])

        XCTAssertEqual(profile.backendOverride, .dxvk)
        XCTAssertEqual(profile.launchArgs, ["-custom"])
        XCTAssertEqual(profile.env["CUSTOM"], "1")
        XCTAssertEqual(profile.env["FORGE_STACK_GUARANTEE_BYTES"], "262144")
        XCTAssertTrue(profile.notes?.localizedCaseInsensitiveContains("larger stack-overflow") == true)
    }

    func testResetGameProfilesRestoresSeededProfile() throws {
        let key = "steam:1336490"
        let seed = try XCTUnwrap(ForgeStore.seededGameProfile(forKey: key))
        let custom = GameCompatibilityProfile(
            id: key,
            displayName: "Against the Storm",
            backendOverride: .wineBuiltin,
            launchArgs: ["-bad-arg"],
            env: ["TEST": "1"],
            notes: "custom"
        )

        XCTAssertTrue(ForgeStore.gameProfileCanReset([key: custom], key: key))

        let reset = ForgeStore.resetGameProfiles([key: custom], key: key)

        XCTAssertEqual(reset[key], seed)
        XCTAssertFalse(ForgeStore.gameProfileCanReset(reset, key: key))
    }

    func testResetGameProfilesRemovesUnseededProfile() {
        let key = "exe:/tmp/custom.exe"
        let custom = GameCompatibilityProfile(
            id: key,
            displayName: "Custom",
            backendOverride: .dxvk,
            launchArgs: [],
            env: [:],
            notes: nil
        )

        XCTAssertTrue(ForgeStore.gameProfileCanReset([key: custom], key: key))

        let reset = ForgeStore.resetGameProfiles([key: custom], key: key)

        XCTAssertNil(reset[key])
        XCTAssertFalse(ForgeStore.gameProfileCanReset(reset, key: key))
    }

    private func makeSupportDir() throws -> URL {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeNativeTests-", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    private func writeProfiles(_ profiles: [GameCompatibilityProfile], to support: URL) throws {
        let data = try JSONEncoder.forge.encode(profiles)
        try data.write(to: support.appendingPathComponent("game_compatibility_profiles.json"), options: .atomic)
    }
}
