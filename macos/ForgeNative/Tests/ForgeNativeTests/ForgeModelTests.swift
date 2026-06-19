import XCTest
@testable import ForgeNative

final class ForgeModelTests: XCTestCase {
    func testGraphicsBackendDecoderFallsBackToDefaultBackend() throws {
        let decoded = try JSONDecoder.forge.decode(GraphicsBackend.self, from: Data("\"unexpected_backend\"".utf8))

        XCTAssertEqual(decoded, .dxvkVkd3d)
    }

    func testBottleAppItemDetectsSteamClientCaseInsensitively() {
        let steam = BottleAppItem(
            name: "Steam",
            path: "/tmp/prefix/drive_c/Program Files (x86)/Steam/STEAM.EXE",
            kind: "launcher"
        )
        let game = BottleAppItem(
            name: "Example",
            path: "/tmp/prefix/drive_c/Games/Example.exe",
            kind: "game"
        )

        XCTAssertTrue(steam.isSteamClient)
        XCTAssertFalse(game.isSteamClient)
    }

    func testDisplayNameNormalizesSeparatorsAndSteamName() {
        XCTAssertEqual(ForgeStore.displayName(for: "/tmp/Steam.exe"), "Steam")
        XCTAssertEqual(ForgeStore.displayName(for: "/tmp/Example_Game-Launcher.exe"), "Example Game Launcher")
    }

    func testGuessKindClassifiesKnownLaunchers() {
        XCTAssertEqual(ForgeStore.guessKind("/tmp/Battle.net/Battle.net.exe"), "launcher")
        XCTAssertEqual(ForgeStore.guessKind("/tmp/Games/Example.exe"), "game")
    }

    func testRuntimeProfileDefaultUsesConfiguredGptkPathWhenPresent() {
        let config = AppConfig(
            wine64Path: "/tmp/wine",
            gptkLibPath: "/tmp/gptk",
            defaultPrefix: "/tmp/prefix",
            suppressWineDebug: true,
            globalHud: false,
            metalfxEnabled: false,
            env: [:]
        )

        let profile = RuntimeProfile.defaultProfile(config: config)

        XCTAssertEqual(profile.gptkLibPath, "/tmp/gptk")
        XCTAssertEqual(profile.defaultBackend, .dxvkVkd3d)
        XCTAssertEqual(profile.env["VK_ICD_FILENAMES"], "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json")
    }
}
