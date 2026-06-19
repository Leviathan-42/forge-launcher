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
                ForgeAppsPanel(
                    store: store,
                    bottle: bottle,
                    apps: filteredApps,
                    searchText: searchText,
                    editProfile: { editingApp = $0 }
                )
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

}
