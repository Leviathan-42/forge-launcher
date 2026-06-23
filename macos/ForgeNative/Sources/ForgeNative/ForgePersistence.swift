import Foundation

private let forgeAppSupportName = "com.forgelauncher.app"

extension ForgeStore {
    nonisolated static func appSupportDir() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(forgeAppSupportName, isDirectory: true)
    }

    nonisolated static func loadConfig(from support: URL) throws -> AppConfig {
        let url = support.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        return try JSONDecoder.forge.decode(AppConfig.self, from: Data(contentsOf: url))
    }

    nonisolated static func saveConfig(_ config: AppConfig, to support: URL) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appendingPathComponent("config.json")
        let data = try JSONEncoder.forge.encode(config)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func loadProfiles(from support: URL, config: AppConfig) throws -> [RuntimeProfile] {
        let url = support.appendingPathComponent("runtime_profiles.json")
        var profiles: [RuntimeProfile]
        if FileManager.default.fileExists(atPath: url.path) {
            let decoded = try JSONDecoder.forge.decode([RuntimeProfile].self, from: Data(contentsOf: url))
            profiles = decoded.isEmpty ? [RuntimeProfile.defaultProfile(config: config)] : decoded
        } else {
            profiles = [RuntimeProfile.defaultProfile(config: config)]
        }

        if let crossOver = RuntimeProfile.crossOverProfile(),
           !profiles.contains(where: { $0.id == crossOver.id }) {
            profiles.append(crossOver)
        }
        return profiles
    }

    nonisolated static func selectBottle(from bottles: [BottleEntry], config: AppConfig) -> BottleEntry {
        bottles.first(where: { $0.prefixPath == config.defaultPrefix })
            ?? bottles.first
            ?? defaultBottle(config: config)
    }

    nonisolated static func loadBottle(from support: URL, config: AppConfig) throws -> BottleEntry {
        selectBottle(from: try loadBottles(from: support, config: config), config: config)
    }

    nonisolated static func loadBottles(from support: URL, config: AppConfig) throws -> [BottleEntry] {
        let url = support.appendingPathComponent("bottles.json")
        var bottles: [BottleEntry]
        if FileManager.default.fileExists(atPath: url.path) {
            let decoded = try JSONDecoder.forge.decode([BottleEntry].self, from: Data(contentsOf: url))
            bottles = decoded.isEmpty ? [defaultBottle(config: config)] : decoded
        } else {
            bottles = [defaultBottle(config: config)]
        }

        for discovered in discoverCrossOverBottles()
            where !bottles.contains(where: { $0.prefixPath == discovered.prefixPath }) {
            bottles.append(discovered)
        }
        return bottles
    }

    nonisolated static func saveBottle(_ bottle: BottleEntry, to support: URL, config: AppConfig) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var bottles = try loadBottles(from: support, config: config)
        if let index = bottles.firstIndex(where: { $0.prefixPath == bottle.prefixPath }) {
            bottles[index] = bottle
        } else {
            bottles.insert(bottle, at: 0)
        }
        let data = try JSONEncoder.forge.encode(bottles)
        try data.write(to: support.appendingPathComponent("bottles.json"), options: .atomic)
    }

    nonisolated static func defaultBottle(config: AppConfig) -> BottleEntry {
        BottleEntry(
            name: "Default",
            prefixPath: config.defaultPrefix,
            runtimeProfileId: RuntimeProfile.defaultId,
            graphicsBackend: .dxvkVkd3d,
            envOverrides: [:]
        )
    }
}
