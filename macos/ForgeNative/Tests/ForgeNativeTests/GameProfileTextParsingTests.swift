import XCTest
@testable import ForgeNative

final class GameProfileTextParsingTests: XCTestCase {
    func testProfileTextHelpersParseLaunchArgsAndEnvOverrides() throws {
        let args = try ForgeStore.parseLaunchArgs("-force-vulkan \"value with spaces\" plain\\ value C:\\Games\\Tool")

        XCTAssertEqual(args, ["-force-vulkan", "value with spaces", "plain value", "C:\\Games\\Tool"])
        let formattedArgs = ForgeStore.formatLaunchArgs(args)
        XCTAssertEqual(
            formattedArgs,
            "-force-vulkan \"value with spaces\" \"plain value\" \"C:\\\\Games\\\\Tool\""
        )
        XCTAssertEqual(try ForgeStore.parseLaunchArgs(formattedArgs), args)

        let emptyArgs = try ForgeStore.parseLaunchArgs("\"\" '' --name=\"\"")
        XCTAssertEqual(emptyArgs, ["", "", "--name="])
        XCTAssertEqual(try ForgeStore.parseLaunchArgs(ForgeStore.formatLaunchArgs(emptyArgs)), emptyArgs)

        let env = try ForgeStore.parseEnvOverrides("""
        VK_ICD_FILENAMES=\(defaultMoltenVkIcdPath)
        # ignored
        FORGE_STACK_GUARANTEE_BYTES=262144
        """)

        XCTAssertEqual(env["FORGE_STACK_GUARANTEE_BYTES"], "262144")
        XCTAssertEqual(env["VK_ICD_FILENAMES"], defaultMoltenVkIcdPath)
        XCTAssertEqual(
            ForgeStore.formatEnvOverrides(env),
            "FORGE_STACK_GUARANTEE_BYTES=262144\nVK_ICD_FILENAMES=\(defaultMoltenVkIcdPath)"
        )
    }

    func testEnvOverridesAllowEqualsInValues() throws {
        let env = try ForgeStore.parseEnvOverrides("""
        WINEDLLOVERRIDES=dxgi=n,b;mscoree,mshtml=
        QUERY=a=b=c
        """)

        XCTAssertEqual(env["WINEDLLOVERRIDES"], "dxgi=n,b;mscoree,mshtml=")
        XCTAssertEqual(env["QUERY"], "a=b=c")
    }

    func testProfileTextHelpersRejectInvalidInput() {
        XCTAssertThrowsError(try ForgeStore.parseLaunchArgs("\"unterminated"))
        XCTAssertThrowsError(try ForgeStore.parseEnvOverrides("BAD LINE"))
        XCTAssertThrowsError(try ForgeStore.parseEnvOverrides("BAD KEY=value"))
        XCTAssertNil(ForgeStore.cleanedProfileNotes(" \n\t "))
        XCTAssertEqual(ForgeStore.cleanedProfileNotes(" note "), "note")
    }
}
