import XCTest
@testable import ForgeNative

final class GameProfileTextParsingTests: XCTestCase {
    func testProfileTextHelpersParseLaunchArgsAndEnvOverrides() throws {
        let args = try ForgeStore.parseLaunchArgs("-force-vulkan \"value with spaces\" plain\\ value C:\\Games\\Tool")

        XCTAssertEqual(args, ["-force-vulkan", "value with spaces", "plain value", "C:\\Games\\Tool"])
        XCTAssertEqual(ForgeStore.formatLaunchArgs(args), "-force-vulkan \"value with spaces\" \"plain value\" \"C:\\\\Games\\\\Tool\"")
        XCTAssertEqual(try ForgeStore.parseLaunchArgs(ForgeStore.formatLaunchArgs(args)), args)

        let emptyArgs = try ForgeStore.parseLaunchArgs("\"\" '' --name=\"\"")
        XCTAssertEqual(emptyArgs, ["", "", "--name="])
        XCTAssertEqual(try ForgeStore.parseLaunchArgs(ForgeStore.formatLaunchArgs(emptyArgs)), emptyArgs)

        let env = try ForgeStore.parseEnvOverrides("""
        VK_ICD_FILENAMES=/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json
        # ignored
        FORGE_STACK_GUARANTEE_BYTES=262144
        """)

        XCTAssertEqual(env["FORGE_STACK_GUARANTEE_BYTES"], "262144")
        XCTAssertEqual(env["VK_ICD_FILENAMES"], "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json")
        XCTAssertEqual(
            ForgeStore.formatEnvOverrides(env),
            "FORGE_STACK_GUARANTEE_BYTES=262144\nVK_ICD_FILENAMES=/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
        )
    }

    func testProfileTextHelpersRejectInvalidInput() {
        XCTAssertThrowsError(try ForgeStore.parseLaunchArgs("\"unterminated"))
        XCTAssertThrowsError(try ForgeStore.parseEnvOverrides("BAD LINE"))
        XCTAssertThrowsError(try ForgeStore.parseEnvOverrides("BAD KEY=value"))
        XCTAssertNil(ForgeStore.cleanedProfileNotes(" \n\t "))
        XCTAssertEqual(ForgeStore.cleanedProfileNotes(" note "), "note")
    }
}
