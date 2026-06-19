import SwiftUI

struct ForgeAppsPanel: View {
    @ObservedObject var store: ForgeStore
    let bottle: BottleEntry
    let apps: [BottleAppItem]
    let searchText: String
    let editProfile: (BottleAppItem) -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Apps")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                Text("\(apps.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
                Spacer()
                Text(backendText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }

            if apps.isEmpty {
                emptyAppsCard
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(apps) { app in
                            let profile = store.gameProfile(for: app)
                            LiquidAppRow(
                                app: app,
                                backend: store.effectiveBackend(for: app, bottle: bottle),
                                backendIsAppSpecific: store.gameProfileIsAppSpecific(for: app),
                                profileCanReset: store.gameProfileCanReset(app),
                                launchArgs: profile.launchArgs,
                                envKeys: profile.env.keys.sorted(),
                                notes: profile.notes,
                                hudText: store.config.globalHud ? "Metal HUD" : "Off",
                                isLaunching: store.isLaunching,
                                isRunning: store.runningAppPath == app.path,
                                setBackend: { store.setGameBackend(app, backend: $0) },
                                resetProfile: { store.resetGameProfile(app) },
                                editProfile: { editProfile(app) },
                                launch: {
                                    if app.steamAppId != nil {
                                        store.launchThroughSteam(app)
                                    } else {
                                        store.launch(app)
                                    }
                                },
                                launchThroughSteam: nil,
                                stop: {
                                    store.stopRunningApp()
                                }
                            )
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(cornerRadius: 24, opacity: 0.20)
    }

    private var emptyAppsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.34))
            Text(searchText.isEmpty ? "No apps found yet" : "No apps match your search")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text(searchText.isEmpty ? "Install Steam, then install games or launchers inside this bottle." : "Try another title, path, or launcher type.")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
    }

    private var backendText: String {
        let backend = bottle.graphicsBackend
            ?? store.profiles.first(where: { $0.id == bottle.runtimeProfileId })?.defaultBackend
            ?? .dxvkVkd3d
        return "Default: \(backend.displayName)"
    }
}
