import XCTest
@testable import ForgeNative

final class ForgeCrossOverTests: XCTestCase {
    func testCrossOverProfileUsesNoGuiRuntimeDefaults() throws {
        let wine = "/tmp/CrossOver.app/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wine"
        let profile = try XCTUnwrap(RuntimeProfile.crossOverProfile(winePath: wine))

        XCTAssertEqual(profile.id, RuntimeProfile.crossOverRuntimeId)
        XCTAssertEqual(profile.name, "CrossOver (no GUI)")
        XCTAssertEqual(profile.wine64Path, wine)
        XCTAssertEqual(profile.defaultBackend, .none)
        XCTAssertEqual(profile.env["FORGE_CROSSOVER_MODE"], "1")
        XCTAssertTrue(ForgeStore.isCrossOverRuntime(profile: profile))
    }

    func testDiscoverCrossOverBottlesFindsCxbottlePrefixes() throws {
        let root = try makeTempDirectory()
        let bottlesRoot = root.appendingPathComponent("Bottles", isDirectory: true)
        let bottle = bottlesRoot.appendingPathComponent("Daily Games", isDirectory: true)
        let notBottle = bottlesRoot.appendingPathComponent("Plain Wine", isDirectory: true)
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notBottle, withIntermediateDirectories: true)
        try Data().write(to: bottle.appendingPathComponent("cxbottle.conf"))

        let discovered = ForgeStore.discoverCrossOverBottles(in: [bottlesRoot])

        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered.first?.name, "CrossOver: Daily Games")
        XCTAssertEqual(discovered.first?.prefixPath, bottle.standardizedFileURL.path)
        XCTAssertEqual(discovered.first?.runtimeProfileId, RuntimeProfile.crossOverRuntimeId)
        XCTAssertEqual(discovered.first?.graphicsBackend, GraphicsBackend.none)
    }

    func testConfigureCrossOverEnvironmentPinsSelectedBottleWithoutGui() {
        let wine = "/Users/me/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wine"
        let profile = RuntimeProfile.crossOverProfile(winePath: wine)!
        var env = ["WINEDEBUG": "fixme-all"]

        ForgeStore.configureCrossOverEnvironment(
            profile: profile,
            winePath: wine,
            prefixPath: "/Users/me/Library/Application Support/CrossOver/Bottles/Daily Games",
            env: &env
        )

        XCTAssertEqual(env["FORGE_CROSSOVER_MODE"], "1")
        XCTAssertEqual(env["CX_BOTTLE"], "/Users/me/Library/Application Support/CrossOver/Bottles/Daily Games")
        XCTAssertEqual(env["WINEPREFIX"], "/Users/me/Library/Application Support/CrossOver/Bottles/Daily Games")
        XCTAssertEqual(env["CX_ROOT"], "/Users/me/Applications/CrossOver.app/Contents/SharedSupport/CrossOver")
        XCTAssertEqual(env["CX_DEBUGMSG"], "fixme-all")
        XCTAssertTrue(env["CX_BOTTLE_PATH"]?.contains("/Users/me/Library/Application Support/CrossOver/Bottles") == true)
    }
}
