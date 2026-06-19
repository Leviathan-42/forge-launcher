import XCTest
@testable import ForgeNative

final class ForgeLaunchSupportTests: XCTestCase {
    func testSteamSafeArgsPrependsCefSandboxFlags() {
        XCTAssertEqual(
            ForgeStore.steamSafeArgs(["-applaunch", "2357570"]),
            ["-no-cef-sandbox", "-cef-disable-sandbox", "-applaunch", "2357570"]
        )
    }

    func testClearVulkanBackendEnvironmentRemovesVulkanAndDXVKKeys() {
        var env = [
            "VK_ICD_FILENAMES": "/tmp/icd.json",
            "VK_DRIVER_FILES": "/tmp/driver.json",
            "DXVK_ASYNC": "1",
            "DXVK_FILTER_DEVICE_NAME": "Impossible",
            "WINEPREFIX": "/tmp/prefix"
        ]

        ForgeStore.clearVulkanBackendEnvironment(&env)

        XCTAssertNil(env["VK_ICD_FILENAMES"])
        XCTAssertNil(env["VK_DRIVER_FILES"])
        XCTAssertNil(env["DXVK_ASYNC"])
        XCTAssertNil(env["DXVK_FILTER_DEVICE_NAME"])
        XCTAssertEqual(env["WINEPREFIX"], "/tmp/prefix")
    }

    func testFormatLaunchSummaryIncludesForwardedSteamGameEnvironment() {
        let summary = ForgeStore.formatLaunchSummary(
            winePath: "/tmp/wine64",
            prefixPath: "/tmp/prefix",
            exePath: "/tmp/Steam/steam.exe",
            isSteam: true,
            launchBackend: .wineBuiltin,
            gameBackend: .dxvkVkd3d,
            steamSafeMode: true,
            args: ["/tmp/Steam/steam.exe", "-no-cef-sandbox", "-applaunch", "2357570"],
            env: [
                "WINEDLLOVERRIDES": "user32=n,b;mscoree,mshtml=",
                "SteamAppId": "2357570",
                "FORGE_STACK_GUARANTEE_BYTES": "262144",
                "FORGE_STEAM_SAFE_MODE": "1",
                "FORGE_GAME_WINEDLLOVERRIDES": "*dxgi,*d3d11=n",
                "FORGE_GAME_VK_ICD_FILENAMES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json",
                "FORGE_GAME_DXVK_ASYNC": "1"
            ]
        )

        XCTAssertTrue(summary.contains("isSteam=true"))
        XCTAssertTrue(summary.contains("backend=\(GraphicsBackend.wineBuiltin.rawValue)"))
        XCTAssertTrue(summary.contains("steamGameBackend=\(GraphicsBackend.dxvkVkd3d.rawValue)"))
        XCTAssertTrue(summary.contains("args=/tmp/Steam/steam.exe -no-cef-sandbox -applaunch 2357570"))
        XCTAssertTrue(summary.contains("SteamAppId=2357570"))
        XCTAssertTrue(summary.contains("FORGE_STACK_GUARANTEE_BYTES=262144"))
        XCTAssertTrue(summary.contains("FORGE_STEAM_SAFE_MODE=1"))
        XCTAssertTrue(summary.contains("FORGE_GAME_WINEDLLOVERRIDES=*dxgi,*d3d11=n"))
        XCTAssertTrue(summary.contains("FORGE_GAME_VK_ICD_FILENAMES=/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"))
        XCTAssertTrue(summary.contains("FORGE_GAME_DXVK_ASYNC=1"))
    }

    func testFormatLaunchSummaryIncludesEmptyTrackedEnvironmentKeys() {
        let summary = ForgeStore.formatLaunchSummary(
            winePath: "/tmp/wine64",
            prefixPath: "/tmp/prefix",
            exePath: "/tmp/Game.exe",
            isSteam: false,
            launchBackend: .dxvk,
            gameBackend: .dxvk,
            steamSafeMode: false,
            args: ["/tmp/Game.exe"],
            env: [:]
        )

        XCTAssertTrue(summary.contains("\nVK_ICD_FILENAMES=\n"))
        XCTAssertTrue(summary.contains("\nFORGE_GAME_WINEDLLOVERRIDES=\n"))
        XCTAssertTrue(summary.hasSuffix("\n\n"))
    }

    func testResolvedWineserverPathPrefersProfileOverride() {
        let config = makeConfig(wine64Path: "/tmp/config/bin/wine")
        let profile = makeRuntimeProfile(
            wine64Path: "/tmp/profile/bin/wine",
            wineserverPath: "/tmp/custom/wineserver"
        )

        XCTAssertEqual(
            ForgeStore.resolvedWineserverPath(profile: profile, config: config),
            "/tmp/custom/wineserver"
        )
    }

    func testResolvedWineserverPathFallsBackNextToSelectedWine() {
        let config = makeConfig(wine64Path: "/tmp/config/bin/wine")
        let profileWine = makeRuntimeProfile(wine64Path: "/tmp/profile/bin/wine", wineserverPath: nil)
        let configWine = makeRuntimeProfile(wine64Path: "", wineserverPath: "")

        XCTAssertEqual(
            ForgeStore.resolvedWineserverPath(profile: profileWine, config: config),
            "/tmp/profile/bin/wineserver"
        )
        XCTAssertEqual(
            ForgeStore.resolvedWineserverPath(profile: configWine, config: config),
            "/tmp/config/bin/wineserver"
        )
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

    private func makeConfig(wine64Path: String) -> AppConfig {
        AppConfig(
            wine64Path: wine64Path,
            gptkLibPath: "",
            defaultPrefix: "/tmp/prefix",
            suppressWineDebug: true,
            globalHud: false,
            metalfxEnabled: false,
            env: [:]
        )
    }

    private func makeRuntimeProfile(wine64Path: String, wineserverPath: String?) -> RuntimeProfile {
        RuntimeProfile(
            id: "test",
            name: "Test",
            wine64Path: wine64Path,
            wineserverPath: wineserverPath,
            gptkLibPath: nil,
            dxvkPath: nil,
            vkd3dPath: nil,
            moltenvkPath: nil,
            defaultBackend: .dxvk,
            env: [:]
        )
    }
}
