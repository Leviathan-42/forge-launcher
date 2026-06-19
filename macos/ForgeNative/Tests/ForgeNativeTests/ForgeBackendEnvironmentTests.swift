import XCTest
@testable import ForgeNative

final class ForgeBackendEnvironmentTests: XCTestCase {
    func testBackendCapabilityPredicatesMatchBackendFamilies() {
        XCTAssertFalse(ForgeStore.backendUsesMoltenVK(.d3dMetal))
        XCTAssertTrue(ForgeStore.backendUsesMoltenVK(.dxvk))
        XCTAssertTrue(ForgeStore.backendUsesMoltenVK(.vkd3d))
        XCTAssertTrue(ForgeStore.backendUsesMoltenVK(.dxvkVkd3d))
        XCTAssertFalse(ForgeStore.backendUsesMoltenVK(.wineBuiltin))
        XCTAssertFalse(ForgeStore.backendUsesMoltenVK(.dxmt))
        XCTAssertFalse(ForgeStore.backendUsesMoltenVK(.none))

        XCTAssertFalse(ForgeStore.backendUsesDXVKAsync(.d3dMetal))
        XCTAssertTrue(ForgeStore.backendUsesDXVKAsync(.dxvk))
        XCTAssertFalse(ForgeStore.backendUsesDXVKAsync(.vkd3d))
        XCTAssertTrue(ForgeStore.backendUsesDXVKAsync(.dxvkVkd3d))
        XCTAssertFalse(ForgeStore.backendUsesDXVKAsync(.wineBuiltin))
        XCTAssertFalse(ForgeStore.backendUsesDXVKAsync(.dxmt))
        XCTAssertFalse(ForgeStore.backendUsesDXVKAsync(.none))

        XCTAssertFalse(ForgeStore.backendPreservesWineD3DEnvironment(.d3dMetal))
        XCTAssertFalse(ForgeStore.backendPreservesWineD3DEnvironment(.dxvk))
        XCTAssertFalse(ForgeStore.backendPreservesWineD3DEnvironment(.vkd3d))
        XCTAssertFalse(ForgeStore.backendPreservesWineD3DEnvironment(.dxvkVkd3d))
        XCTAssertTrue(ForgeStore.backendPreservesWineD3DEnvironment(.wineBuiltin))
        XCTAssertFalse(ForgeStore.backendPreservesWineD3DEnvironment(.dxmt))
        XCTAssertTrue(ForgeStore.backendPreservesWineD3DEnvironment(.none))
    }

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
