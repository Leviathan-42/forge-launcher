import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var store = ForgeStore()
    @State private var searchText = ""
    @State private var isDropTarget = false
    @State private var editingApp: BottleAppItem?

    private var filteredApps: [BottleAppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.apps }
        return store.apps.filter { app in
            app.name.localizedCaseInsensitiveContains(query)
                || app.path.localizedCaseInsensitiveContains(query)
                || app.kind.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            LiquidBackground()

            if let bottle = store.bottle {
                appShell(bottle)
            } else {
                emptyState
                    .padding(28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Forge", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .sheet(item: $editingApp) { app in
            Group {
                if let bottle = store.bottle {
                    GameProfileEditorSheet(
                        app: app,
                        profile: store.gameProfile(for: app),
                        effectiveBackend: store.effectiveBackend(for: app, bottle: bottle),
                        canReset: store.gameProfileCanReset(app),
                        save: { backend, launchArgs, env, notes in
                            store.updateGameProfile(
                                app,
                                backendOverride: backend,
                                launchArgs: launchArgs,
                                env: env,
                                notes: notes
                            )
                            editingApp = nil
                        },
                        reset: {
                            store.resetGameProfile(app)
                            editingApp = nil
                        },
                        cancel: {
                            editingApp = nil
                        }
                    )
                } else {
                    EmptyView()
                }
            }
            .preferredColorScheme(.dark)
        }
        .task { store.reload() }
    }

    private func appShell(_ bottle: BottleEntry) -> some View {
        HStack(spacing: 16) {
            ForgeSidebar(store: store, bottle: bottle)
                .frame(width: 244)

            VStack(spacing: 14) {
                topBar
                ForgeRuntimePanel(store: store, bottle: bottle, isDropTarget: $isDropTarget)
                appsPanel(bottle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 34)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Library")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Launch Windows apps from your Forge bottle.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isLaunching {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Launching…")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.68))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .liquidGlass(cornerRadius: 20, opacity: 0.24)
            }

            GlassSearchField(text: $searchText)
                .frame(width: 285)
        }
    }

    private func appsPanel(_ bottle: BottleEntry) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Apps")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                Text("\(filteredApps.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
                Spacer()
                Text(backendText(for: bottle))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }

            if filteredApps.isEmpty {
                emptyAppsCard
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredApps) { app in
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
                                editProfile: { editingApp = app },
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white.opacity(0.36))
            Text("No Forge bottle configured")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Forge will look in Application Support for config.json and bottles.json.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            Button("Reload") { store.reload() }
                .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.18), foreground: .white.opacity(0.94)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .liquidGlass(cornerRadius: 34, opacity: 0.30)
    }

    private func backendText(for bottle: BottleEntry) -> String {
        let backend = bottle.graphicsBackend
            ?? store.profiles.first(where: { $0.id == bottle.runtimeProfileId })?.defaultBackend
            ?? .dxvkVkd3d
        return "Default: \(backend.displayName)"
    }
}
