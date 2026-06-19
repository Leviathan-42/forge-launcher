extension ForgeStore {
    nonisolated static func backendUsesMoltenVK(_ backend: GraphicsBackend) -> Bool {
        switch backend {
        case .dxvk, .vkd3d, .dxvkVkd3d:
            true
        case .d3dMetal, .wineBuiltin, .dxmt, .none:
            false
        }
    }

    nonisolated static func backendUsesDXVKAsync(_ backend: GraphicsBackend) -> Bool {
        switch backend {
        case .dxvk, .dxvkVkd3d:
            true
        case .d3dMetal, .vkd3d, .wineBuiltin, .dxmt, .none:
            false
        }
    }

    nonisolated static func backendPreservesWineD3DEnvironment(_ backend: GraphicsBackend) -> Bool {
        switch backend {
        case .wineBuiltin, .none:
            true
        case .d3dMetal, .dxvk, .vkd3d, .dxvkVkd3d, .dxmt:
            false
        }
    }

    nonisolated static func wineDllOverrides(for backend: GraphicsBackend) -> String? {
        switch backend {
        case .d3dMetal:
            "dxgi,d3d9,d3d10core,d3d11,d3d12=b;user32=n,b;mscoree,mshtml="
        case .dxvk:
            "dxgi,d3d9,d3d10core,d3d11,user32=n,b;mscoree,mshtml="
        case .vkd3d:
            "d3d12,dxgi,user32=n,b;mscoree,mshtml="
        case .dxvkVkd3d:
            "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b;mscoree,mshtml="
        case .wineBuiltin:
            "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
        case .dxmt:
            "dd3d11,d3d11,dxgi,d3d10core=b;user32=n,b;mscoree,mshtml="
        case .none:
            nil
        }
    }
}
