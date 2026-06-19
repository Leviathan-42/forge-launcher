import XCTest
@testable import ForgeNative

final class ForgeLaunchSupportTests: XCTestCase {
    func testSteamSafeArgsPrependsCefSandboxFlags() {
        XCTAssertEqual(
            ForgeStore.steamSafeArgs(["-applaunch", "2357570"]),
            ["-no-cef-sandbox", "-cef-disable-sandbox", "-applaunch", "2357570"]
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
}
