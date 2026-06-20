import Foundation

struct AppConfig: Codable {
    var wine64Path: String
    var gptkLibPath: String
    var defaultPrefix: String
    var suppressWineDebug: Bool
    var globalHud: Bool
    var metalfxEnabled: Bool
    var env: [String: String]

    static let defaults = AppConfig(
        wine64Path: "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine",
        gptkLibPath: "",
        defaultPrefix: NSHomeDirectory() + "/Wine/Bottles/default",
        suppressWineDebug: true,
        globalHud: false,
        metalfxEnabled: false,
        env: [:]
    )
}

struct RuntimeProfile: Codable, Identifiable {
    static let defaultId = "forge-cx-wine11-open-wow64"

    var id: String
    var name: String
    var wine64Path: String
    var wineserverPath: String?
    var gptkLibPath: String?
    var dxvkPath: String?
    var vkd3dPath: String?
    var moltenvkPath: String?
    var defaultBackend: GraphicsBackend
    var env: [String: String]

    static func defaultProfile(config: AppConfig) -> RuntimeProfile {
        let gptkLibPath = config.gptkLibPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return RuntimeProfile(
            id: Self.defaultId,
            name: "Forge Wine 11 Open WoW64 + MoltenVK",
            wine64Path: NSHomeDirectory() + "/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wine",
            wineserverPath: NSHomeDirectory() + "/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wineserver",
            gptkLibPath: gptkLibPath.isEmpty ? nil : gptkLibPath,
            dxvkPath: nil,
            vkd3dPath: nil,
            moltenvkPath: defaultMoltenVkIcdPath,
            defaultBackend: .dxvkVkd3d,
            env: ["VK_ICD_FILENAMES": defaultMoltenVkIcdPath]
        )
    }
}

struct BottleEntry: Codable, Identifiable {
    var id: String { prefixPath }
    var name: String
    var prefixPath: String
    var runtimeProfileId: String
    var graphicsBackend: GraphicsBackend?
    var envOverrides: [String: String]
}

struct BottleAppItem: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var kind: String
    var steamAppId: String? = nil

    var isSteamClient: Bool {
        ForgeStore.isSteamExecutable(path, forceSteamMode: false)
    }

    var symbolName: String {
        kind == "launcher" ? "bolt.fill" : "gamecontroller.fill"
    }
}

enum GraphicsBackend: String, Codable, Equatable, CaseIterable {
    case d3dMetal = "d3dmetal"
    case dxvk
    case vkd3d
    case dxvkVkd3d = "dxvk_vkd3d"
    case wineBuiltin = "wine_builtin"
    case dxmt
    case none

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GraphicsBackend(rawValue: raw) ?? .dxvkVkd3d
    }
}

enum ForgeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

extension JSONDecoder {
    static var forge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

extension JSONEncoder {
    static var forge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension String {
    var standardizingPath: String {
        (self as NSString).standardizingPath
    }
}
