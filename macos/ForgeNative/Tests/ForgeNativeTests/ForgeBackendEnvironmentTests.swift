import XCTest
@testable import ForgeNative

final class ForgeBackendEnvironmentTests: XCTestCase {
    func testWineDllOverridesMatchBackendDefaults() {
        XCTAssertEqual(
            ForgeStore.wineDllOverrides(for: .d3dMetal),
            "dxgi,d3d9,d3d10core,d3d11,d3d12=b;user32=n,b;mscoree,mshtml="
        )
        XCTAssertEqual(
            ForgeStore.wineDllOverrides(for: .dxvk),
            "dxgi,d3d9,d3d10core,d3d11,user32=n,b;mscoree,mshtml="
        )
        XCTAssertEqual(
            ForgeStore.wineDllOverrides(for: .vkd3d),
            "d3d12,dxgi,user32=n,b;mscoree,mshtml="
        )
        XCTAssertEqual(
            ForgeStore.wineDllOverrides(for: .dxvkVkd3d),
            "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b;mscoree,mshtml="
        )
        XCTAssertEqual(
            ForgeStore.wineDllOverrides(for: .wineBuiltin),
            "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
        )
        XCTAssertEqual(
            ForgeStore.wineDllOverrides(for: .dxmt),
            "dd3d11,d3d11,dxgi,d3d10core=b;user32=n,b;mscoree,mshtml="
        )
        XCTAssertNil(ForgeStore.wineDllOverrides(for: .none))
    }
}
