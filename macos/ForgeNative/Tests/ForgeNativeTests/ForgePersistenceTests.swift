import XCTest
@testable import ForgeNative

final class ForgePersistenceTests: XCTestCase {
    func testLoadConfigReturnsDefaultsWhenMissingAndRoundTripsSavedConfig() throws {
        let support = try makeSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }

        XCTAssertEqual(try ForgeStore.loadConfig(from: support).defaultPrefix, AppConfig.defaults.defaultPrefix)

        let config = AppConfig(
            wine64Path: "/tmp/wine",
            gptkLibPath: "/tmp/gptk",
            defaultPrefix: "/tmp/prefix",
            suppressWineDebug: false,
            globalHud: true,
            metalfxEnabled: true,
            env: ["A": "B"]
        )
        try ForgeStore.saveConfig(config, to: support)

        let loaded = try ForgeStore.loadConfig(from: support)
        XCTAssertEqual(loaded.wine64Path, "/tmp/wine")
        XCTAssertEqual(loaded.gptkLibPath, "/tmp/gptk")
        XCTAssertEqual(loaded.defaultPrefix, "/tmp/prefix")
        XCTAssertFalse(loaded.suppressWineDebug)
        XCTAssertTrue(loaded.globalHud)
        XCTAssertTrue(loaded.metalfxEnabled)
        XCTAssertEqual(loaded.env, ["A": "B"])
    }

    func testLoadProfilesReturnsDefaultForMissingOrEmptyProfileFile() throws {
        let support = try makeSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }
        let config = AppConfig.defaults

        XCTAssertEqual(try ForgeStore.loadProfiles(from: support, config: config).first?.id, RuntimeProfile.defaultId)

        try "[]".write(to: support.appendingPathComponent("runtime_profiles.json"), atomically: true, encoding: .utf8)

        XCTAssertEqual(try ForgeStore.loadProfiles(from: support, config: config).first?.id, RuntimeProfile.defaultId)
    }

    func testSelectBottlePrefersConfiguredPrefixThenFallsBack() {
        let config = AppConfig(
            wine64Path: "/tmp/wine",
            gptkLibPath: "",
            defaultPrefix: "/tmp/selected",
            suppressWineDebug: true,
            globalHud: false,
            metalfxEnabled: false,
            env: [:]
        )
        let first = BottleEntry(
            name: "First",
            prefixPath: "/tmp/first",
            runtimeProfileId: "default",
            graphicsBackend: .dxvk,
            envOverrides: [:]
        )
        let selected = BottleEntry(
            name: "Selected",
            prefixPath: "/tmp/selected",
            runtimeProfileId: "default",
            graphicsBackend: .dxmt,
            envOverrides: [:]
        )

        XCTAssertEqual(ForgeStore.selectBottle(from: [first, selected], config: config).name, "Selected")
        XCTAssertEqual(ForgeStore.selectBottle(from: [first], config: config).name, "First")
        let fallback = ForgeStore.selectBottle(from: [], config: config)
        XCTAssertEqual(fallback.prefixPath, "/tmp/selected")
        XCTAssertEqual(fallback.runtimeProfileId, RuntimeProfile.defaultId)
    }

    func testSaveBottleUpdatesExistingBottleAndInsertsNewBottle() throws {
        let support = try makeSupportDir()
        defer { try? FileManager.default.removeItem(at: support) }
        let config = AppConfig.defaults
        let existing = BottleEntry(
            name: "Default",
            prefixPath: config.defaultPrefix,
            runtimeProfileId: "default",
            graphicsBackend: .dxvk,
            envOverrides: [:]
        )
        try ForgeStore.saveBottle(existing, to: support, config: config)

        var updated = existing
        updated.graphicsBackend = .dxmt
        updated.envOverrides = ["TEST": "1"]
        try ForgeStore.saveBottle(updated, to: support, config: config)

        let extra = BottleEntry(
            name: "Extra",
            prefixPath: "/tmp/extra-prefix",
            runtimeProfileId: "default",
            graphicsBackend: .wineBuiltin,
            envOverrides: [:]
        )
        try ForgeStore.saveBottle(extra, to: support, config: config)

        let bottles = try ForgeStore.loadBottles(from: support, config: config)
        XCTAssertEqual(bottles.count, 2)
        XCTAssertEqual(bottles.first(where: { $0.prefixPath == config.defaultPrefix })?.graphicsBackend, .dxmt)
        XCTAssertEqual(bottles.first(where: { $0.prefixPath == config.defaultPrefix })?.envOverrides, ["TEST": "1"])
        XCTAssertEqual(bottles.first?.prefixPath, "/tmp/extra-prefix")
    }

    private func makeSupportDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgePersistenceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
