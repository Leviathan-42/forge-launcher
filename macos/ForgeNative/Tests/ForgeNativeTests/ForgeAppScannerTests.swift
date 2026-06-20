import XCTest
@testable import ForgeNative

final class ForgeAppScannerTests: XCTestCase {
    func testAcfValueParsesQuotedSteamManifestFields() {
        let manifest = """
        "AppState"
        {
            "appid" "2357570"
            "name" "Overwatch 2"
            "installdir" "Overwatch 2"
        }
        """

        XCTAssertEqual(ForgeStore.acfValue("appid", in: manifest), "2357570")
        XCTAssertEqual(ForgeStore.acfValue("name", in: manifest), "Overwatch 2")
        XCTAssertEqual(ForgeStore.acfValue("installdir", in: manifest), "Overwatch 2")
        XCTAssertNil(ForgeStore.acfValue("missing", in: manifest))
    }

    func testPrimaryGameExePrefersExactGameNameAndSkipsHelpers() throws {
        let gameDir = try makeDirectory("Example Game")
        try touch(gameDir.appendingPathComponent("UnityCrashHandler64.exe"))
        try touch(gameDir.appendingPathComponent("unins000.exe"))
        try touch(gameDir.appendingPathComponent("CrashReporter.exe"))
        try touch(gameDir.appendingPathComponent("Bootstrap.exe"))
        try touch(gameDir.appendingPathComponent("Example Game.exe"))
        defer { try? FileManager.default.removeItem(at: gameDir.deletingLastPathComponent()) }

        XCTAssertEqual(
            ForgeStore.primaryGameExe(in: gameDir)?.lastPathComponent,
            "Example Game.exe"
        )
    }

    func testUserVisibleExeFilterRejectsHelpersAndAllowsGames() {
        XCTAssertTrue(ForgeStore.isUserVisibleExe("/tmp/Program Files/Visible Game/Visible Game.exe"))
        XCTAssertFalse(ForgeStore.isUserVisibleExe("/tmp/Program Files/Visible Game/CrashReporter.exe"))
        XCTAssertFalse(ForgeStore.isUserVisibleExe("/tmp/Program Files/Visible Game/vc_redist.x64.exe"))
        XCTAssertFalse(ForgeStore.isUserVisibleExe("/tmp/Program Files/Visible Game/unins999.exe"))
        XCTAssertFalse(ForgeStore.isUserVisibleExe("/tmp/Program Files/Common Files/Runtime/Helper.exe"))
    }

    func testManagedLauncherFilterKeepsLaunchersAndHidesChildren() {
        XCTAssertTrue(ForgeStore.isUserVisibleExe("/tmp/Program Files/Steam/steam.exe"))
        XCTAssertTrue(ForgeStore.isUserVisibleExe("/tmp/Program Files/Epic Games/Launcher/Portal/EpicGamesLauncher.exe"))
        XCTAssertTrue(ForgeStore.isUserVisibleExe("/tmp/Program Files/Rockstar Games/Launcher/Launcher.exe"))

        XCTAssertFalse(ForgeStore.isUserVisibleExe("/tmp/Program Files/Steam/bin/FriendHelper.exe"))
        XCTAssertFalse(ForgeStore.isUserVisibleExe("/tmp/Program Files/Epic Games/Launcher/Portal/PortalWorker.exe"))
        XCTAssertFalse(ForgeStore.isUserVisibleExe("/tmp/Program Files/Rockstar Games/Launcher/LauncherPatcher.exe"))
    }

    func testManagedLauncherContainersAreNotRecursed() {
        XCTAssertFalse(ForgeStore.shouldDescendForUserApps("/tmp/drive_c/Program Files/Steam"))
        XCTAssertFalse(ForgeStore.shouldDescendForUserApps("/tmp/drive_c/Program Files (x86)/Epic Games"))
        XCTAssertFalse(ForgeStore.shouldDescendForUserApps("/tmp/drive_c/Program Files/Battle.net"))
        XCTAssertTrue(ForgeStore.shouldDescendForUserApps("/tmp/drive_c/Program Files/Visible Game"))
    }

    func testScanSteamGamesAddsNamedGameEntryWithAppId() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }

        let steamapps = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        let gameDir = steamapps.appendingPathComponent("common/Example Game", isDirectory: true)
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        try touch(gameDir.appendingPathComponent("Example Game.exe"))
        try """
        "AppState"
        {
            "appid" "123"
            "name" "Example Game"
            "installdir" "Example Game"
        }
        """.write(to: steamapps.appendingPathComponent("appmanifest_123.acf"), atomically: true, encoding: .utf8)

        var apps: [BottleAppItem] = []
        var seen = Set<String>()
        ForgeStore.scanSteamGames(prefixPath: prefix.path, into: &apps, seen: &seen)

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.name, "Example Game")
        XCTAssertEqual(apps.first?.kind, "game")
        XCTAssertEqual(apps.first?.steamAppId, "123")
        XCTAssertEqual(apps.first?.path, gameDir.appendingPathComponent("Example Game.exe").path)
    }

    func testScanAppsKeepsUserVisibleAppsAndFiltersManagedHelpers() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }

        let driveC = prefix.appendingPathComponent("drive_c", isDirectory: true)
        let steamDir = driveC.appendingPathComponent("Program Files/Steam", isDirectory: true)
        let gameDir = driveC.appendingPathComponent("Program Files/Visible Game", isDirectory: true)
        let commonFilesDir = driveC.appendingPathComponent("Program Files/Common Files/Hidden Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: steamDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: commonFilesDir, withIntermediateDirectories: true)

        try touch(steamDir.appendingPathComponent("steam.exe"))
        try touch(steamDir.appendingPathComponent("steamwebhelper.exe"))
        try touch(gameDir.appendingPathComponent("Visible Game.exe"))
        try touch(gameDir.appendingPathComponent("crashhandler.exe"))
        try touch(commonFilesDir.appendingPathComponent("Helper.exe"))

        let apps = ForgeStore.scanApps(prefixPath: prefix.path)

        XCTAssertTrue(apps.contains { $0.name == "Steam" && $0.kind == "launcher" })
        XCTAssertTrue(apps.contains { $0.name == "Visible Game" && $0.kind == "game" })
        XCTAssertFalse(apps.contains { $0.path.localizedCaseInsensitiveContains("steamwebhelper.exe") })
        XCTAssertFalse(apps.contains { $0.path.localizedCaseInsensitiveContains("crashhandler.exe") })
        XCTAssertFalse(apps.contains { $0.path.localizedCaseInsensitiveContains("Common Files") })
    }

    private func makePrefix() throws -> URL {
        try makeDirectory(UUID().uuidString)
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeAppScannerTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }
}
