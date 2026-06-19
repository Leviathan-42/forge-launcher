import XCTest
@testable import ForgeNative

final class ForgeGraphicsEnvironmentTests: XCTestCase {
    func testDedupePathPartsKeepsFirstNonEmptyOccurrence() {
        XCTAssertEqual(
            ForgeStore.dedupePathParts(["", "/opt/runtime/lib", "/usr/local/lib", "/opt/runtime/lib", ""]),
            ["/opt/runtime/lib", "/usr/local/lib"]
        )
    }

    func testBuildDyldPathAddsGptkExternalSearchPaths() {
        let dyldPath = ForgeStore.buildDyldPath(
            gptkLibPath: "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external",
            existing: "/opt/forge-wine/lib"
        )

        XCTAssertEqual(
            dyldPath,
            [
                "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external",
                "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework/Versions/A",
                "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib",
                "/opt/forge-wine/lib"
            ].joined(separator: ":")
        )
    }

    func testMoltenVkCandidatesExpandConfiguredTildePath() {
        let configured = "~/Wine/Runtimes/moltenvk"
        let expanded = (configured as NSString).expandingTildeInPath

        let candidates = ForgeStore.moltenVkIcdCandidates(configuredPath: configured)

        XCTAssertTrue(candidates.contains(expanded))
        XCTAssertTrue(candidates.contains(URL(fileURLWithPath: expanded).appendingPathComponent("MoltenVK_icd.json").path))
        XCTAssertTrue(candidates.contains("/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"))
    }
}
