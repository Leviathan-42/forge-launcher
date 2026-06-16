import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private let forgeAppSupportName = "com.forgelauncher.app"

@main
struct ForgeNativeApp: App {
    @NSApplicationDelegateAdaptor(ForgeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(.dark)
                .containerBackground(.clear, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

final class ForgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let icon = NSImage(named: "AppIcon") ?? NSImage(contentsOf: Bundle.module.url(forResource: "AppIcon", withExtension: "png")!) {
            NSApp.applicationIconImage = icon
        }

        for window in NSApp.windows {
            configure(window)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        for window in NSApp.windows {
            configure(window)
        }
    }

    private func configure(_ window: NSWindow) {
        window.title = "Forge"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}

struct ContentView: View {
    @StateObject private var store = ForgeStore()
    @State private var searchText = ""
    @State private var isDropTarget = false

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
        .task { store.reload() }
    }

    private func appShell(_ bottle: BottleEntry) -> some View {
        HStack(spacing: 16) {
            sidebar(bottle)
                .frame(width: 244)

            VStack(spacing: 14) {
                topBar
                runtimePanel(bottle)
                appsPanel(bottle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 34)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func sidebar(_ bottle: BottleEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.20), radius: 10, y: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Forge")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Windows bottles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Bottle")
                if store.bottles.count > 1 {
                    BottlePickerCard(
                        bottles: store.bottles,
                        selection: Binding(
                            get: { bottle.prefixPath },
                            set: { store.selectBottle(prefixPath: $0) }
                        )
                    )
                }
                BottleCard(bottle: bottle, statusText: store.statusText, isReady: store.prefixExists)
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Status")
                StatusLine(icon: "shippingbox.fill", title: store.prefixExists ? "Bottle ready" : "Bottle missing", value: bottle.name)
                StatusLine(icon: "app.badge.fill", title: "Launchable apps", value: "\(store.apps.count)")
                BackendPickerCard(
                    selection: Binding(
                        get: { bottle.graphicsBackend ?? store.profile(for: bottle).defaultBackend },
                        set: { store.setBackend($0) }
                    )
                )
            }

            HudToggleCard(
                isOn: Binding(
                    get: { store.config.globalHud },
                    set: { store.setMetalHud($0) }
                )
            )

            Spacer()

            Button {
                store.reload()
            } label: {
                Label("Refresh Library", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.14)))
        }
        .padding(16)
        .liquidGlass(cornerRadius: 24, opacity: 0.22)
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

    private func runtimePanel(_ bottle: BottleEntry) -> some View {
        HStack(spacing: 14) {
            DropExeCard(
                isTargeted: isDropTarget,
                isDisabled: store.isLaunching,
                isRunning: store.runningAppPath != nil,
                selectAction: { store.selectExe() },
                stopAction: { store.stopRunningApp() }
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
                handleExeDrop(providers)
            }

            RuntimeActionCard(
                icon: "folder.fill",
                title: "Bottle Folder",
                subtitle: bottle.prefixPath,
                primaryTitle: "Reveal",
                isDisabled: false,
                primaryAction: { store.revealBottle() }
            )

            RuntimeActionCard(
                icon: "arrow.clockwise.circle.fill",
                title: "Rescan",
                subtitle: "Refresh installed launchers and EXEs.",
                primaryTitle: "Refresh",
                isDisabled: false,
                primaryAction: { store.reload() }
            )
        }
    }

    private func handleExeDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let raw = item as? URL {
                url = raw
            } else {
                url = nil
            }

            guard let url else { return }
            Task { @MainActor in
                store.runExe(at: url)
            }
        }
        return true
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
                            LiquidAppRow(
                                app: app,
                                backend: store.effectiveBackend(for: app, bottle: bottle),
                                backendIsOverride: store.gameProfile(for: app).backendOverride != nil,
                                hudText: store.config.globalHud ? "Metal HUD" : "Off",
                                isLaunching: store.isLaunching,
                                isRunning: store.runningAppPath == app.path,
                                setBackend: { store.setGameBackend(app, backend: $0) },
                                resetBackend: { store.resetGameBackend(app) },
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

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.38))
            .tracking(0.9)
    }
}

struct BottlePickerCard: View {
    let bottles: [BottleEntry]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Active Bottle", selection: $selection) {
                ForEach(bottles) { bottle in
                    Text(bottle.name).tag(bottle.prefixPath)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 18, opacity: 0.18)
    }
}

struct BottleCard: View {
    let bottle: BottleEntry
    let statusText: String
    let isReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "wineglass.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(bottle.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(statusText)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(isReady ? .green.opacity(0.78) : .orange.opacity(0.78))
                }
            }

            Text(bottle.prefixPath)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

struct StatusLine: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.74))
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }
}

struct DropExeCard: View {
    let isTargeted: Bool
    let isDisabled: Bool
    let isRunning: Bool
    let selectAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "plus.app.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(isTargeted ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(isTargeted ? "Drop to Run" : "Add EXE")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                    Text("Drag a Windows .exe here or select one from Finder.")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button(isRunning ? "Stop" : "Select EXE", action: isRunning ? stopAction : selectAction)
                .buttonStyle(ForgeButtonStyle(tint: isRunning ? .red.opacity(0.26) : .white.opacity(0.15)))
                .disabled(isDisabled && !isRunning)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
        .liquidGlass(cornerRadius: 26, opacity: isTargeted ? 0.42 : 0.26)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(isTargeted ? 0.38 : 0), lineWidth: 1.4)
        )
    }
}

struct BackendPickerCard: View {
    @Binding var selection: GraphicsBackend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Graphics Backend", systemImage: "display")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            Picker("Graphics Backend", selection: $selection) {
                Text("DXVK/VKD3D").tag(GraphicsBackend.dxvkVkd3d)
                Text("D3DMetal").tag(GraphicsBackend.d3dMetal)
                Text("DXVK").tag(GraphicsBackend.dxvk)
                Text("VKD3D").tag(GraphicsBackend.vkd3d)
                Text("WineD3D").tag(GraphicsBackend.wineBuiltin)
                Text("DXMT").tag(GraphicsBackend.dxmt)
                Text("None").tag(GraphicsBackend.none)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 6) {
                Text(selection.consumerGuidance)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(.white.opacity(0.10))

                BackendGuideRow(label: "Vulkan/OpenGL", value: "None or WineD3D only if the game supports it")
                BackendGuideRow(label: "DirectX 9", value: "DXVK first")
                BackendGuideRow(label: "DirectX 10/11", value: "DXVK first; DXMT if Vulkan/DXVK fails")
                BackendGuideRow(label: "DirectX 12", value: "VKD3D or D3DMetal")
                BackendGuideRow(label: "Fallback", value: "WineD3D for older/simple games")
            }
        }
        .padding(13)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

struct BackendGuideRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9.8, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
            Text(value)
                .font(.system(size: 10.2, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HudToggleCard: View {
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 10) {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Metal HUD")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                        Text(isOn ? "Shown on next launch" : "Hidden on next launch")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.40))
                    }
                }
            }
            .toggleStyle(.switch)

            Text("Only appears for Metal-backed rendering. Steam itself may hide it; games launched after toggling should inherit it.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

struct RuntimeActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let primaryTitle: String
    let isDisabled: Bool
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.15)))
                .disabled(isDisabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
        .liquidGlass(cornerRadius: 26, opacity: 0.26)
    }
}

struct LiquidBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.055),
                    Color.cyan.opacity(0.030),
                    Color.black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.white.opacity(0.22))
            Circle().fill(.white.opacity(0.18))
            Circle().fill(.white.opacity(0.14))
        }
        .frame(width: 62, height: 16)
    }
}

struct ToolbarIcon: View {
    let systemName: String
    var isActive = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white.opacity(isActive ? 0.92 : 0.62))
            .frame(width: 34, height: 34)
            .background(.white.opacity(isActive ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    func active() -> ToolbarIcon {
        ToolbarIcon(systemName: systemName, isActive: true)
    }
}

struct ToolbarMenuPill: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
            Text(text)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.75)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.white.opacity(0.075), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

struct GlassSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1))
    }
}

struct LiquidAppRow: View {
    let app: BottleAppItem
    let backend: GraphicsBackend
    let backendIsOverride: Bool
    let hudText: String
    let isLaunching: Bool
    let isRunning: Bool
    let setBackend: (GraphicsBackend) -> Void
    let resetBackend: () -> Void
    let launch: () -> Void
    let launchThroughSteam: (() -> Void)?
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
                Image(systemName: app.kind == "launcher" ? "bolt.fill" : "gamecontroller.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(app.path)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(app.kind.capitalized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            HStack(spacing: 6) {
                Picker("Graphics", selection: Binding(
                    get: { backend },
                    set: { setBackend($0) }
                )) {
                    ForEach(GraphicsBackend.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 118, alignment: .leading)

                Button(action: resetBackend) {
                    Image(systemName: backendIsOverride ? "arrow.uturn.backward.circle.fill" : "checkmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(backendIsOverride ? Color.primary : Color.secondary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(backendIsOverride ? "Reset to bottle default" : "Using bottle default")
                .disabled(!backendIsOverride)
            }
            .frame(width: 150, alignment: .leading)

            Text(hudText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hudText == "Off" ? Color.secondary : Color.primary)
                .frame(width: 92, alignment: .leading)

            HStack(spacing: 8) {
                Button(isRunning ? "Stop" : "Play", action: isRunning ? stop : launch)
                    .buttonStyle(ForgeButtonStyle(
                        tint: isRunning ? .red.opacity(0.24) : .white.opacity(0.11),
                        foreground: .primary
                    ))
                    .disabled(isLaunching && !isRunning)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
    }

}

struct StatusPill: View {
    let text: String
    let isGood: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(isGood ? 0.88 : 0.62))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(isGood ? 0.13 : 0.07), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

struct ForgeButtonStyle: ButtonStyle {
    var tint: Color = .white.opacity(0.10)
    var foreground: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                shape
                    .fill(.thinMaterial)
                    .overlay(shape.fill(tint.opacity(configuration.isPressed ? 0.45 : 0.88)))
            }
            .overlay(shape.stroke(.white.opacity(configuration.isPressed ? 0.08 : 0.16), lineWidth: 1))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.08 : 0.14), radius: configuration.isPressed ? 4 : 10, x: 0, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    var opacity: Double = 0.52

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            }
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.105),
                            .white.opacity(0.035),
                            .black.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 28, opacity: Double = 0.52) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

extension GraphicsBackend {
    var displayName: String {
        switch self {
        case .d3dMetal: return "D3DMetal"
        case .dxvk: return "DXVK"
        case .vkd3d: return "VKD3D"
        case .dxvkVkd3d: return "DXVK/VKD3D"
        case .wineBuiltin: return "WineD3D"
        case .dxmt: return "DXMT"
        case .none: return "None"
        }
    }

    var consumerGuidance: String {
        switch self {
        case .dxvkVkd3d:
            return "Good default: DirectX 9/10/11 via DXVK and DirectX 12 via VKD3D."
        case .dxvk:
            return "Best for many DirectX 9/10/11 games when Vulkan/MoltenVK supports the needed features."
        case .dxmt:
            return "Use for DirectX 10/11 games that fail under DXVK, especially Unity D3D11 titles."
        case .vkd3d:
            return "Use for DirectX 12 games. Not for DirectX 9/10/11-only games."
        case .d3dMetal:
            return "Use for DirectX 11/12 games when Apple/GPTK D3DMetal is available and DXVK/VKD3D fail."
        case .wineBuiltin:
            return "Compatibility fallback for older/simple DirectX or OpenGL games; usually slower."
        case .none:
            return "No DirectX translation override. Use when a game has its own Vulkan/OpenGL renderer."
        }
    }
}

// MARK: - Store

@MainActor
final class ForgeStore: ObservableObject {
    @Published var config = AppConfig.defaults
    @Published var profiles: [RuntimeProfile] = []
    @Published var bottles: [BottleEntry] = []
    @Published var bottle: BottleEntry?
    @Published var gameProfiles: [String: GameCompatibilityProfile] = [:]
    @Published var apps: [BottleAppItem] = []
    @Published var steamPath: String?
    @Published var prefixExists = false
    @Published var isLaunching = false
    @Published var runningAppPath: String?
    @Published var alertMessage: String?

    var statusText: String {
        guard bottle != nil else { return "Missing" }
        if !prefixExists { return "Bottle missing" }
        return "Bottle ready"
    }

    func reload() {
        do {
            let support = Self.appSupportDir()
            config = try Self.loadConfig(from: support)
            profiles = try Self.loadProfiles(from: support, config: config)
            bottles = try Self.loadBottles(from: support, config: config)
            gameProfiles = try Self.loadGameProfiles(from: support)
            bottle = Self.selectBottle(from: bottles, config: config)
            refreshBottleState()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func selectBottle(prefixPath: String) {
        guard let selected = bottles.first(where: { $0.prefixPath == prefixPath }) else { return }
        bottle = selected
        config.defaultPrefix = selected.prefixPath
        do {
            try Self.saveConfig(config, to: Self.appSupportDir())
        } catch {
            alertMessage = "Bottle changed for this session, but Forge could not save config.json: \(error.localizedDescription)"
        }
        refreshBottleState()
    }

    func openSteam() {
        guard let steamPath else {
            alertMessage = "Windows Steam is not installed in this bottle yet."
            return
        }
        launch(BottleAppItem(name: "Steam", path: steamPath, kind: "launcher"))
    }

    func installSteam() {
        guard let bottle else { return }
        isLaunching = true
        Task.detached(priority: .userInitiated) {
            do {
                let installer = try Self.downloadSteamInstaller()
                try await Self.spawn(
                    exePath: installer.path,
                    bottle: bottle,
                    config: await MainActor.run { self.config },
                    profile: await MainActor.run { self.profile(for: bottle) },
                    extraArgs: [],
                    forceSteamMode: false,
                    steamAppId: nil,
                    backendOverride: nil,
                    gameEnvOverrides: [:],
                    steamSafeMode: true
                )
                await MainActor.run {
                    self.isLaunching = false
                    self.alertMessage = "Steam installer launched. Finish the installer, then press Refresh."
                }
            } catch {
                await MainActor.run {
                    self.isLaunching = false
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func selectExe() {
        let panel = NSOpenPanel()
        panel.title = "Select Windows EXE"
        panel.message = "Choose a Windows .exe to run in the selected Forge bottle."
        if let exeType = UTType(filenameExtension: "exe") {
            panel.allowedContentTypes = [exeType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            runExe(at: url)
        }
    }

    func runExe(at url: URL) {
        guard url.pathExtension.caseInsensitiveCompare("exe") == .orderedSame else {
            alertMessage = "Forge can only run Windows .exe files."
            return
        }
        launch(BottleAppItem(name: Self.displayName(for: url.path), path: url.path, kind: "app"))
    }

    func gameProfile(for app: BottleAppItem) -> GameCompatibilityProfile {
        let key = Self.gameProfileKey(for: app)
        if let profile = gameProfiles[key] { return profile }
        return GameCompatibilityProfile(id: key, displayName: app.name, backendOverride: nil, launchArgs: [], env: [:], notes: nil)
    }

    func effectiveBackend(for app: BottleAppItem, bottle: BottleEntry) -> GraphicsBackend {
        gameProfile(for: app).backendOverride ?? bottle.graphicsBackend ?? profile(for: bottle).defaultBackend
    }

    func launchArgs(for app: BottleAppItem) -> [String] {
        let key = Self.gameProfileKey(for: app)
        if let profile = gameProfiles[key] {
            return profile.launchArgs
        }
        return app.steamAppId == nil ? [] : ["-screen-fullscreen", "1"]
    }

    func gameEnv(for app: BottleAppItem) -> [String: String] {
        gameProfile(for: app).env
    }

    func setGameBackend(_ app: BottleAppItem, backend: GraphicsBackend) {
        var profile = gameProfile(for: app)
        profile.backendOverride = backend
        saveGameProfile(profile)
    }

    func resetGameBackend(_ app: BottleAppItem) {
        var profile = gameProfile(for: app)
        profile.backendOverride = nil
        saveGameProfile(profile)
    }

    private func saveGameProfile(_ profile: GameCompatibilityProfile) {
        gameProfiles[profile.id] = profile
        do {
            try Self.saveGameProfiles(gameProfiles, to: Self.appSupportDir())
        } catch {
            alertMessage = "Compatibility profile changed for this session, but Forge could not save it: \(error.localizedDescription)"
        }
    }

    func launch(_ app: BottleAppItem) {
        launch(app, throughSteam: false)
    }

    func launchThroughSteam(_ app: BottleAppItem) {
        launch(app, throughSteam: true)
    }

    private func launch(_ app: BottleAppItem, throughSteam: Bool) {
        guard let bottle else { return }
        isLaunching = true
        Task.detached(priority: .userInitiated) {
            do {
                let launchConfig = await MainActor.run { self.config }
                let launchProfile = await MainActor.run { self.profile(for: bottle) }
                let appBackend = await MainActor.run { self.effectiveBackend(for: app, bottle: bottle) }
                let appLaunchArgs = await MainActor.run { self.launchArgs(for: app) }
                let appEnv = await MainActor.run { self.gameEnv(for: app) }
                let targetPath: String
                let forceSteamMode: Bool
                let steamAppId: String?
                let extraArgs: [String]

                if throughSteam {
                    guard let appId = app.steamAppId else {
                        throw ForgeError.message("This app is not linked to a Steam manifest.")
                    }
                    guard let steamPath = await MainActor.run(body: { self.steamPath }) else {
                        throw ForgeError.message("Windows Steam is not installed in this bottle yet.")
                    }
                    targetPath = steamPath
                    forceSteamMode = true
                    steamAppId = appId
                    extraArgs = ["-applaunch", appId] + appLaunchArgs
                } else {
                    targetPath = app.path
                    forceSteamMode = app.isSteamClient
                    steamAppId = app.steamAppId
                    extraArgs = appLaunchArgs
                }

                if app.name.caseInsensitiveCompare("PEAK") == .orderedSame
                    || app.name.caseInsensitiveCompare("Against the Storm") == .orderedSame {
                    try? Self.stopWineSession(bottle: bottle, config: launchConfig, profile: launchProfile)
                }

                if throughSteam, appBackend == .d3dMetal {
                    // D3DMetal is still launched directly for Steam games so Steam's
                    // Chromium helpers do not interfere with the game's graphics DLLs.
                    // D3DMetal's PE DLLs and Unix modules must come from the same Wine
                    // build, so this path uses GPTK Wine against the Forge bottle.
                    try await Self.spawn(
                        exePath: app.path,
                        bottle: bottle,
                        config: launchConfig,
                        profile: launchProfile,
                        extraArgs: appLaunchArgs,
                        forceSteamMode: false,
                        steamAppId: steamAppId,
                        backendOverride: .d3dMetal,
                        gameEnvOverrides: appEnv,
                        steamSafeMode: false
                    )
                } else {
                    try await Self.spawn(
                        exePath: targetPath,
                        bottle: bottle,
                        config: launchConfig,
                        profile: launchProfile,
                        extraArgs: extraArgs,
                        forceSteamMode: forceSteamMode,
                        steamAppId: steamAppId,
                        backendOverride: appBackend,
                        gameEnvOverrides: appEnv,
                        // Always keep steam.exe itself in safe UI mode. For Steam-owned
                        // game launches, -applaunch is still passed through while Forge's
                        // FORGE_GAME_* env advertises the selected game backend.
                        steamSafeMode: true
                    )
                }
                await MainActor.run {
                    self.isLaunching = false
                    self.runningAppPath = app.path
                }
            } catch {
                await MainActor.run {
                    self.isLaunching = false
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func stopRunningApp() {
        guard let bottle else { return }
        let profile = profile(for: bottle)
        let config = config
        Task.detached(priority: .userInitiated) {
            do {
                try Self.stopWineSession(bottle: bottle, config: config, profile: profile)
                await MainActor.run {
                    self.runningAppPath = nil
                    self.isLaunching = false
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func revealBottle() {
        guard let bottle else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bottle.prefixPath)])
    }

    func setBackend(_ backend: GraphicsBackend) {
        guard var current = bottle else { return }
        current.graphicsBackend = backend
        bottle = current
        do {
            try Self.saveBottle(current, to: Self.appSupportDir(), config: config)
        } catch {
            alertMessage = "Backend changed for this session, but Forge could not save bottles.json: \(error.localizedDescription)"
        }
    }

    func setMetalHud(_ enabled: Bool) {
        config.globalHud = enabled
        do {
            try Self.saveConfig(config, to: Self.appSupportDir())
            try Self.setMetalHudDefaults(enabled)
        } catch {
            alertMessage = "Metal HUD changed for this session, but Forge could not save config: \(error.localizedDescription)"
        }
    }

    private func refreshBottleState() {
        guard let bottle else {
            apps = []
            steamPath = nil
            prefixExists = false
            return
        }
        prefixExists = FileManager.default.fileExists(atPath: bottle.prefixPath)
        steamPath = Self.findSteam(prefixPath: bottle.prefixPath)
        apps = Self.scanApps(prefixPath: bottle.prefixPath)
    }

    func profile(for bottle: BottleEntry) -> RuntimeProfile {
        profiles.first(where: { $0.id == bottle.runtimeProfileId })
            ?? profiles.first
            ?? RuntimeProfile.defaultProfile(config: config)
    }

    // MARK: Load config

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
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [RuntimeProfile.defaultProfile(config: config)]
        }
        let decoded = try JSONDecoder.forge.decode([RuntimeProfile].self, from: Data(contentsOf: url))
        return decoded.isEmpty ? [RuntimeProfile.defaultProfile(config: config)] : decoded
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
        guard FileManager.default.fileExists(atPath: url.path) else { return [defaultBottle(config: config)] }
        let decoded = try JSONDecoder.forge.decode([BottleEntry].self, from: Data(contentsOf: url))
        return decoded.isEmpty ? [defaultBottle(config: config)] : decoded
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

    nonisolated static func loadGameProfiles(from support: URL) throws -> [String: GameCompatibilityProfile] {
        let url = support.appendingPathComponent("game_compatibility_profiles.json")
        var profiles: [String: GameCompatibilityProfile]
        if FileManager.default.fileExists(atPath: url.path) {
            let decoded = try JSONDecoder.forge.decode([GameCompatibilityProfile].self, from: Data(contentsOf: url))
            profiles = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        } else {
            profiles = [:]
        }
        for seed in seededGameProfiles() {
            if profiles[seed.id] == nil {
                profiles[seed.id] = seed
            } else if seed.id == "steam:1336490", profiles[seed.id]?.backendOverride == .d3dMetal {
                // Against the Storm is D3D11-only and now works through DXMT in Forge's
                // own Wine runtime. Migrate the earlier D3DMetal seed automatically.
                profiles[seed.id]?.backendOverride = .dxmt
                profiles[seed.id]?.notes = seed.notes
            } else if seed.id == "steam:945360", profiles[seed.id]?.backendOverride != .wineBuiltin {
                // Among Us is a 32-bit Unity D3D11 build. DXMT's 32-bit builtin PE
                // cannot be loaded by this WoW64 runtime, and DXVK hits feature-level
                // limits. WineD3D's Vulkan renderer reaches D3D11 level 11.1.
                profiles[seed.id] = seed
            } else if seed.id == "steam:2357570", profiles[seed.id]?.backendOverride == .d3dMetal {
                // Overwatch fails D3DMetal initialization in the current runtime.
                profiles[seed.id] = seed
            } else if seed.id == "steam:2357570", profiles[seed.id]?.env["FORGE_STACK_GUARANTEE_BYTES"] == nil {
                profiles[seed.id]?.env["FORGE_STACK_GUARANTEE_BYTES"] = seed.env["FORGE_STACK_GUARANTEE_BYTES"]
                profiles[seed.id]?.notes = seed.notes
            }
        }
        return profiles
    }

    nonisolated static func saveGameProfiles(_ profiles: [String: GameCompatibilityProfile], to support: URL) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let ordered = profiles.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let data = try JSONEncoder.forge.encode(ordered)
        try data.write(to: support.appendingPathComponent("game_compatibility_profiles.json"), options: .atomic)
    }

    nonisolated static func seededGameProfiles() -> [GameCompatibilityProfile] {
        [
            GameCompatibilityProfile(
                id: "steam:1336490",
                displayName: "Against the Storm",
                backendOverride: .dxmt,
                launchArgs: ["-screen-fullscreen", "1"],
                env: [:],
                notes: "D3D11-only Unity build; Vulkan/OpenGL shaders are unavailable and DXVK is blocked by MoltenVK geometryShader support. Uses DXMT's D3D11 -> Metal path."
            ),
            GameCompatibilityProfile(
                id: "steam:945360",
                displayName: "Among Us",
                backendOverride: .wineBuiltin,
                launchArgs: [],
                env: [
                    "WINE_D3D_CONFIG": "renderer=vulkan",
                    "WINEDLLOVERRIDES": "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;vulkan-1,winevulkan=b;mscoree,mshtml=",
                    "VK_ICD_FILENAMES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json",
                    "VK_DRIVER_FILES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
                ],
                notes: "32-bit Unity D3D11 build; DXMT/DXVK are not viable in this WoW64 runtime. WineD3D's Vulkan renderer reaches D3D11 level 11.1."
            ),
            GameCompatibilityProfile(
                id: "steam:2357570",
                displayName: "Overwatch 2",
                backendOverride: .dxvkVkd3d,
                launchArgs: [],
                env: ["FORGE_STACK_GUARANTEE_BYTES": "262144"],
                notes: "Steam build. Use DXVK/VKD3D and reserve a larger stack-overflow handling guarantee for Blizzard's loader/VEH path; do not use D3DMetal for the current Forge runtime."
            ),
            GameCompatibilityProfile(
                id: "name:peak",
                displayName: "PEAK",
                backendOverride: .dxvkVkd3d,
                launchArgs: ["-force-vulkan", "-force-gfx-st", "-disable-gpu-skinning", "-screen-fullscreen", "1"],
                env: [:],
                notes: "Unity Vulkan path works; disable GPU skinning to avoid avatar mesh corruption."
            )
        ]
    }

    nonisolated static func gameProfileKey(for app: BottleAppItem) -> String {
        if app.name.caseInsensitiveCompare("PEAK") == .orderedSame { return "name:peak" }
        if let appId = app.steamAppId, !appId.isEmpty { return "steam:\(appId)" }
        return "exe:\(app.path.standardizingPath.lowercased())"
    }

    nonisolated static func defaultBottle(config: AppConfig) -> BottleEntry {
        BottleEntry(
            name: "Default",
            prefixPath: config.defaultPrefix,
            runtimeProfileId: "wine-vulkan",
            graphicsBackend: .dxvkVkd3d,
            envOverrides: [:]
        )
    }

    // MARK: App scan

    nonisolated static func findSteam(prefixPath: String) -> String? {
        steamCandidates(prefixPath: prefixPath).first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    nonisolated static func scanApps(prefixPath: String) -> [BottleAppItem] {
        var apps: [BottleAppItem] = []
        var seen = Set<String>()

        for path in knownLauncherPaths(prefixPath: prefixPath) where FileManager.default.fileExists(atPath: path) {
            push(path: path, kind: "launcher", into: &apps, seen: &seen)
        }

        scanSteamGames(prefixPath: prefixPath, into: &apps, seen: &seen)

        for root in programRoots(prefixPath: prefixPath) {
            collectExes(URL(fileURLWithPath: root), depth: 0, into: &apps, seen: &seen)
            if apps.count >= 120 { break }
        }

        apps.sort {
            let leftRank = $0.kind == "launcher" ? 0 : 1
            let rightRank = $1.kind == "launcher" ? 0 : 1
            if leftRank != rightRank { return leftRank < rightRank }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if apps.count > 120 { apps.removeSubrange(120..<apps.count) }
        return apps
    }

    nonisolated static func collectExes(_ dir: URL, depth: Int, into apps: inout [BottleAppItem], seen: inout Set<String>) {
        guard depth <= 5, apps.count < 120 else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            if apps.count >= 120 { return }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                if shouldDescendForUserApps(entry.path) {
                    collectExes(entry, depth: depth + 1, into: &apps, seen: &seen)
                }
            } else if entry.pathExtension.caseInsensitiveCompare("exe") == .orderedSame,
                      isUserVisibleExe(entry.path) {
                push(path: entry.path, kind: guessKind(entry.path), into: &apps, seen: &seen)
            }
        }
    }

    nonisolated static func push(path: String, kind: String, into apps: inout [BottleAppItem], seen: inout Set<String>, name: String? = nil, steamAppId: String? = nil) {
        let normalized = path.standardizingPath
        guard seen.insert(normalized.lowercased()).inserted else { return }
        apps.append(BottleAppItem(name: name ?? displayName(for: normalized), path: normalized, kind: kind, steamAppId: steamAppId))
    }

    nonisolated static func scanSteamGames(prefixPath: String, into apps: inout [BottleAppItem], seen: inout Set<String>) {
        let steamApps = URL(fileURLWithPath: prefixPath)
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
        guard let manifests = try? FileManager.default.contentsOfDirectory(
            at: steamApps,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
            guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
            let appId = acfValue("appid", in: text)
            let name = acfValue("name", in: text)
            guard let installDir = acfValue("installdir", in: text), let appId else { continue }
            let gameDir = steamApps.appendingPathComponent("common").appendingPathComponent(installDir)
            guard let exe = primaryGameExe(in: gameDir) else { continue }
            push(path: exe.path, kind: "game", into: &apps, seen: &seen, name: name, steamAppId: appId)
        }
    }

    nonisolated static func acfValue(_ key: String, in text: String) -> String? {
        let pattern = "\\\"\(NSRegularExpression.escapedPattern(for: key))\\\"\\s+\\\"([^\\\"]+)\\\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    nonisolated static func primaryGameExe(in dir: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let exes = entries.filter { entry in
            let file = entry.lastPathComponent.lowercased()
            return entry.pathExtension.caseInsensitiveCompare("exe") == .orderedSame
                && !file.contains("unitycrashhandler")
                && !file.contains("crash")
                && !file.hasPrefix("unins")
                && file != "uninstall.exe"
        }
        if let exact = exes.first(where: { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(dir.lastPathComponent) == .orderedSame }) {
            return exact
        }
        return exes.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }.first
    }

    nonisolated static func shouldDescendForUserApps(_ path: String) -> Bool {
        let raw = normalizedForFilter(path)
        return !raw.contains("/program files/common files")
            && !raw.contains("/program files (x86)/common files")
            && !raw.contains("/internet explorer")
            && !raw.contains("/windows media player")
            && !raw.contains("/windows nt")
            && !isManagedLauncherContainer(raw)
    }

    nonisolated static func isUserVisibleExe(_ path: String) -> Bool {
        let raw = normalizedForFilter(path)
        let file = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if raw.contains("/internet explorer/")
            || raw.contains("/windows media player/")
            || raw.contains("/windows nt/")
            || raw.contains("/common files/")
            || isManagedLauncherChild(raw, file: file) {
            return false
        }

        let hidden: Set<String> = [
            "steamwebhelper.exe", "steamerrorreporter.exe", "gldriverquery.exe", "gldriverquery64.exe",
            "vulkandriverquery.exe", "vulkandriverquery64.exe", "steamservice.exe", "steam_monitor.exe",
            "crashhandler.exe", "crashpad_handler.exe", "uninstall.exe", "unins000.exe", "unins001.exe",
            "dxsetup.exe", "vc_redist.x64.exe", "vc_redist.x86.exe", "installscript.vdf.exe"
        ]
        if hidden.contains(file) { return false }
        if file.hasPrefix("unins") || file.contains("crash") || file.contains("reporter") { return false }
        return true
    }

    nonisolated static func isManagedLauncherContainer(_ raw: String) -> Bool {
        raw.hasSuffix("/program files/steam")
            || raw.hasSuffix("/program files (x86)/steam")
            || raw.hasSuffix("/program files (x86)/epic games")
            || raw.hasSuffix("/program files/epic games")
            || raw.hasSuffix("/program files/battle.net")
            || raw.hasSuffix("/program files (x86)/battle.net")
            || raw.hasSuffix("/program files/electronic arts")
            || raw.hasSuffix("/program files (x86)/ubisoft")
            || raw.hasSuffix("/program files/rockstar games")
    }

    nonisolated static func isManagedLauncherChild(_ raw: String, file: String) -> Bool {
        if file == "steam.exe"
            || file == "epicgameslauncher.exe"
            || file == "battle.net.exe"
            || file == "ealauncher.exe"
            || file == "ubisoftconnect.exe"
            || file == "launcher.exe" && raw.contains("/rockstar games/launcher/") {
            return false
        }

        return raw.contains("/steam/")
            || raw.contains("/epic games/")
            || raw.contains("/battle.net/")
            || raw.contains("/electronic arts/")
            || raw.contains("/ubisoft/")
            || raw.contains("/rockstar games/")
    }

    nonisolated static func guessKind(_ path: String) -> String {
        let raw = normalizedForFilter(path)
        let file = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if file == "steam.exe" || raw.contains("/launcher/") || raw.contains("battle.net") || raw.contains("ubisoft") {
            return "launcher"
        }
        return "game"
    }

    nonisolated static func displayName(for path: String) -> String {
        let file = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if file.caseInsensitiveCompare("steam") == .orderedSame { return "Steam" }
        return file
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizedForFilter(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    nonisolated static func steamCandidates(prefixPath: String) -> [String] {
        let driveC = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c")
        return [
            driveC.appendingPathComponent("Program Files (x86)/Steam/steam.exe").path,
            driveC.appendingPathComponent("Program Files/Steam/steam.exe").path
        ]
    }

    nonisolated static func knownLauncherPaths(prefixPath: String) -> [String] {
        let driveC = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c")
        return steamCandidates(prefixPath: prefixPath) + [
            driveC.appendingPathComponent("Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe").path,
            driveC.appendingPathComponent("Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe").path,
            driveC.appendingPathComponent("Program Files (x86)/Battle.net/Battle.net.exe").path,
            driveC.appendingPathComponent("Program Files/Battle.net/Battle.net.exe").path,
            driveC.appendingPathComponent("Program Files/Electronic Arts/EA Desktop/EA Desktop/EALauncher.exe").path,
            driveC.appendingPathComponent("Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe").path,
            driveC.appendingPathComponent("Program Files/Rockstar Games/Launcher/Launcher.exe").path
        ]
    }

    nonisolated static func programRoots(prefixPath: String) -> [String] {
        let driveC = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c")
        return [
            driveC.appendingPathComponent("Program Files").path,
            driveC.appendingPathComponent("Program Files (x86)").path,
            driveC.appendingPathComponent("users/Public/Desktop").path
        ]
    }

    // MARK: Launch

    nonisolated static func spawn(
        exePath: String,
        bottle: BottleEntry,
        config: AppConfig,
        profile: RuntimeProfile,
        extraArgs: [String],
        forceSteamMode: Bool,
        steamAppId: String?,
        backendOverride: GraphicsBackend?,
        gameEnvOverrides: [String: String],
        steamSafeMode: Bool
    ) async throws {
        let configuredWinePath = profile.wine64Path.isEmpty ? config.wine64Path : profile.wine64Path
        let isSteam = forceSteamMode || URL(fileURLWithPath: exePath).lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame
        let gameBackend = backendOverride ?? bottle.graphicsBackend ?? profile.defaultBackend
        let launchBackend: GraphicsBackend = (isSteam && steamSafeMode) ? .wineBuiltin : gameBackend
        let gptkLibPath = profile.gptkLibPath ?? config.gptkLibPath
        var winePath = configuredWinePath
        if launchBackend == .d3dMetal, let gptkWine = gptkWinePath(gptkLibPath: gptkLibPath) {
            // Do not mix GPTK's D3DMetal modules with Forge Wine: Wine's builtin
            // PE DLLs and Unix-side .so modules are ABI-coupled to their Wine build.
            winePath = gptkWine
        }
        let runtimeLibPath = URL(fileURLWithPath: winePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("lib")
            .path
        guard FileManager.default.fileExists(atPath: winePath) else {
            throw ForgeError.message("wine not found at \(winePath)")
        }

        try ensurePrefix(prefixPath: bottle.prefixPath, winePath: winePath)
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        if launchBackend == .d3dMetal {
            env["DYLD_LIBRARY_PATH"] = buildDyldPath(
                gptkLibPath: gptkLibPath,
                existing: dedupePathParts([runtimeLibPath, env["DYLD_LIBRARY_PATH"] ?? ""]).joined(separator: ":")
            )
            env["DYLD_FALLBACK_LIBRARY_PATH"] = dedupePathParts([
                runtimeLibPath,
                "/opt/homebrew/lib",
                "/usr/local/lib",
                env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
            ]).joined(separator: ":")
            if !gptkLibPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                env["DYLD_FRAMEWORK_PATH"] = URL(fileURLWithPath: gptkLibPath).path
            }
        } else {
            // DXVK/VKD3D should use Forge/Homebrew MoltenVK. Do not let GPTK's
            // older external libMoltenVK shadow the Vulkan 1.3+ ICD needed by DXVK.
            env["DYLD_LIBRARY_PATH"] = dedupePathParts([runtimeLibPath, env["DYLD_LIBRARY_PATH"] ?? ""]).joined(separator: ":")
            env["DYLD_FALLBACK_LIBRARY_PATH"] = dedupePathParts([
                runtimeLibPath,
                "/opt/homebrew/lib",
                "/usr/local/lib",
                env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
            ]).joined(separator: ":")
            env.removeValue(forKey: "DYLD_FRAMEWORK_PATH")
        }
        env["WINEDEBUG"] = config.suppressWineDebug ? "fixme-all" : ""
        env["WINEDBG"] = "-all"
        env["GST_DEBUG"] = "1"
        env["MTL_HUD_ENABLED"] = config.globalHud ? "1" : "0"
        env["MTL_HUD_LAYER"] = config.globalHud ? "1" : "0"
        if config.globalHud {
            try? setMetalHudDefaults(true)
        }
        env["WINE_MOUSE_WARP"] = "1"
        env["WINEESYNC"] = "1"
        env["WINEMSYNC"] = "1"
        if let steamAppId {
            env["SteamAppId"] = steamAppId
            env["SteamGameId"] = steamAppId
        }
        if launchBackend == .dxvk || launchBackend == .vkd3d || launchBackend == .dxvkVkd3d {
            configureMoltenVK(profile: profile, config: config, env: &env)
        }

        switch launchBackend {
        case .d3dMetal:
            if let gptkBase = gptkWineLibBase(gptkLibPath: gptkLibPath) {
                let dllPaths = [
                    gptkBase.appendingPathComponent("wine/x86_64-windows").path,
                    gptkBase.appendingPathComponent("wine/x86_64-unix").path,
                    gptkBase.appendingPathComponent("wine/i386-windows").path,
                    gptkBase.appendingPathComponent("wine/x86_32on64-unix").path
                ].filter { FileManager.default.fileExists(atPath: $0) }
                if !dllPaths.isEmpty {
                    env["WINEDLLPATH"] = dedupePathParts(dllPaths + [env["WINEDLLPATH"] ?? ""]).joined(separator: ":")
                }
            }
            try removeStagedD3DMetalDlls(exePath: exePath)
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,d3d12=b;user32=n,b;mscoree,mshtml="
            if let frameworkPath = d3dMetalFrameworkPath(gptkLibPath: gptkLibPath) {
                env["D3DMETAL_FRAMEWORK_PATH"] = frameworkPath
            }
            env["D3DM_MTL4"] = env["D3DM_MTL4"] ?? "0"
            env["D3DM_SUPPORT_DXR"] = env["D3DM_SUPPORT_DXR"] ?? "0"
            env["D3DM_ENABLE_METALFX"] = env["D3DM_ENABLE_METALFX"] ?? "0"
            env["FORGE_D3DMETAL_RUNTIME"] = "gptk-wine-d3dmetal"
        case .dxvk:
            try ensureDXVKInstalled(exePath: exePath, prefixPath: bottle.prefixPath, steamAppId: steamAppId)
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,user32=n,b;mscoree,mshtml="
            env["DXVK_ASYNC"] = "1"
        case .vkd3d:
            env["WINEDLLOVERRIDES"] = "d3d12,dxgi,user32=n,b;mscoree,mshtml="
        case .dxvkVkd3d:
            try ensureDXVKInstalled(exePath: exePath, prefixPath: bottle.prefixPath, steamAppId: steamAppId)
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b;mscoree,mshtml="
            env["DXVK_ASYNC"] = "1"
        case .wineBuiltin:
            try removeStagedD3DMetalDlls(exePath: exePath)
            env["WINEDLLOVERRIDES"] = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            env["WINE_D3D_CONFIG"] = "renderer=gl"
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        case .dxmt:
            try ensureDXMTInstalled(winePath: winePath, prefixPath: bottle.prefixPath)
            try removeStagedD3DMetalDlls(exePath: exePath)
            env["WINEDLLOVERRIDES"] = "dd3d11,d3d11,dxgi,d3d10core=b;user32=n,b;mscoree,mshtml="
            env["DXMT_LOG_LEVEL"] = env["DXMT_LOG_LEVEL"] ?? "info"
            env["DXMT_LOG_PATH"] = env["DXMT_LOG_PATH"] ?? appSupportDir().appendingPathComponent("Logs", isDirectory: true).path
        case .none:
            break
        }

        for (key, value) in config.env { env[key] = value }
        for (key, value) in profile.env { env[key] = value }
        for (key, value) in bottle.envOverrides { env[key] = value }
        for (key, value) in gameEnvOverrides { env[key] = value }

        if (env["WINE_D3D_CONFIG"] ?? "").localizedCaseInsensitiveContains("renderer=vulkan") {
            // WineD3D's Vulkan renderer must not inherit the GL software fallback
            // used for Steam's Chromium UI / older WineD3D fallback launches.
            env.removeValue(forKey: "LIBGL_ALWAYS_SOFTWARE")
        }

        if !isSteam {
            // Steam safe mode intentionally sets this to an impossible value to keep
            // DXVK out of Steam's Chromium helpers. Direct game launches must always
            // clear it or DXVK reports "No adapters found" and Unity games crash.
            env.removeValue(forKey: "DXVK_FILTER_DEVICE_NAME")
        }

        if launchBackend == .dxmt {
            env.removeValue(forKey: "VK_ICD_FILENAMES")
            env.removeValue(forKey: "VK_DRIVER_FILES")
            env.removeValue(forKey: "DXVK_ASYNC")
            env.removeValue(forKey: "DXVK_FILTER_DEVICE_NAME")
        }

        if launchBackend == .d3dMetal {
            // D3DMetal must not inherit Vulkan/DXVK profile settings. If VK_ICD or
            // DXVK variables survive here, Wine can load DXVK instead of GPTK's
            // builtin D3DMetal DLLs and Unity games crash before rendering.
            env.removeValue(forKey: "VK_ICD_FILENAMES")
            env.removeValue(forKey: "VK_DRIVER_FILES")
            env.removeValue(forKey: "DXVK_ASYNC")
            env.removeValue(forKey: "DXVK_FILTER_DEVICE_NAME")
        }

        // This win32u workaround is only for Steam's Chromium helper. Do not let
        // a shell/profile value leak into direct game launches.
        env.removeValue(forKey: "FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP")

        if isSteam && steamSafeMode {
            if gameBackend == .dxvk || gameBackend == .vkd3d || gameBackend == .dxvkVkd3d {
                configureMoltenVK(profile: profile, config: config, env: &env)
            }
            let gameVkIcd = env["VK_ICD_FILENAMES"] ?? ""
            let gameVkDriverFiles = env["VK_DRIVER_FILES"] ?? gameVkIcd
            let gameWineD3DConfig = env["WINE_D3D_CONFIG"] ?? ""
            let gameLibGLAlwaysSoftware = env["LIBGL_ALWAYS_SOFTWARE"] ?? ""
            let gameMetalHudEnabled = config.globalHud ? "1" : "0"
            let gameMetalHudLayer = config.globalHud ? "1" : "0"
            let gameDXVKAsync = (gameBackend == .dxvk || gameBackend == .dxvkVkd3d) ? (env["DXVK_ASYNC"] ?? "1") : ""
            let gameDyldPath = gameBackend == .d3dMetal ? buildDyldPath(
                gptkLibPath: gptkLibPath,
                existing: dedupePathParts([runtimeLibPath, env["DYLD_LIBRARY_PATH"] ?? ""]).joined(separator: ":")
            ) : ""
            var gameWineDllPath = ""
            if gameBackend == .d3dMetal, let gptkBase = gptkWineLibBase(gptkLibPath: gptkLibPath) {
                gameWineDllPath = [
                    gptkBase.appendingPathComponent("wine/x86_64-windows").path,
                    gptkBase.appendingPathComponent("wine/x86_64-unix").path,
                    gptkBase.appendingPathComponent("wine/i386-windows").path,
                    gptkBase.appendingPathComponent("wine/x86_32on64-unix").path
                ].filter { FileManager.default.fileExists(atPath: $0) }.joined(separator: ":")
            }
            let gameDllOverrides: String
            switch gameBackend {
            case .d3dMetal:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,d3d12=b;user32=n,b;mscoree,mshtml="
            case .dxvk:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,user32=n,b;mscoree,mshtml="
            case .vkd3d:
                gameDllOverrides = "d3d12,dxgi,user32=n,b;mscoree,mshtml="
            case .dxvkVkd3d:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b;mscoree,mshtml="
            case .wineBuiltin:
                gameDllOverrides = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            case .dxmt:
                gameDllOverrides = "dd3d11,d3d11,dxgi,d3d10core=b;user32=n,b;mscoree,mshtml="
            case .none:
                gameDllOverrides = ""
            }

            // Steam's Chromium UI is stable in this safe backend, but games launched
            // from Steam must not inherit these variables. Forge Wine detects this
            // marker and restores the FORGE_GAME_* values for non-Steam child EXEs.
            env["FORGE_STEAM_SAFE_MODE"] = "1"
            env["FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP"] = "steamwebhelper.exe"
            env["FORGE_GAME_WINEDLLOVERRIDES"] = gameDllOverrides
            env["FORGE_GAME_WINE_D3D_CONFIG"] = gameWineD3DConfig
            env["FORGE_GAME_LIBGL_ALWAYS_SOFTWARE"] = gameLibGLAlwaysSoftware
            env["FORGE_GAME_VK_ICD_FILENAMES"] = gameVkIcd
            env["FORGE_GAME_VK_DRIVER_FILES"] = gameVkDriverFiles
            env["FORGE_GAME_MTL_HUD_ENABLED"] = gameMetalHudEnabled
            env["FORGE_GAME_MTL_HUD_LAYER"] = gameMetalHudLayer
            env["FORGE_GAME_DXVK_ASYNC"] = gameDXVKAsync
            env["FORGE_GAME_DYLD_LIBRARY_PATH"] = gameDyldPath
            env["FORGE_GAME_WINEDLLPATH"] = gameWineDllPath
            env["MOLTENVK_CONFIG_LOG_LEVEL"] = env["MOLTENVK_CONFIG_LOG_LEVEL"] ?? "0"

            env["WINEDLLOVERRIDES"] = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            env["WINE_D3D_CONFIG"] = "renderer=gl"
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
            env["VK_ICD_FILENAMES"] = "/dev/null"
            env["VK_DRIVER_FILES"] = "/dev/null"
            env["DXVK_FILTER_DEVICE_NAME"] = "__forge_disable_dxvk_for_steam__"
            env["MTL_HUD_ENABLED"] = "0"
            env["MTL_HUD_LAYER"] = "0"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: winePath)
        // Launch the PE executable directly instead of through `wine start /unix`.
        // `start` detaches through explorer and can lose/flatten macOS-only env like
        // MTL_HUD_ENABLED before the Unix-side Metal module is loaded. Direct launch
        // keeps Forge's environment on the actual Wine process tree.
        process.arguments = [exePath] + ((isSteam && steamSafeMode) ? steamSafeArgs(extraArgs) : extraArgs)
        process.currentDirectoryURL = URL(fileURLWithPath: exePath).deletingLastPathComponent()
        process.environment = env

        let log = try launchLogHandle()
        let launchSummary = """
        Forge Native launch
        wine=\(winePath)
        prefix=\(bottle.prefixPath)
        exe=\(exePath)
        isSteam=\(isSteam)
        backend=\(launchBackend.rawValue)
        steamSafeMode=\(isSteam && steamSafeMode)
        steamGameBackend=\(isSteam ? gameBackend.rawValue : "")
        args=\(process.arguments?.joined(separator: " ") ?? "")
        WINEDLLOVERRIDES=\(env["WINEDLLOVERRIDES"] ?? "")
        WINE_D3D_CONFIG=\(env["WINE_D3D_CONFIG"] ?? "")
        VK_ICD_FILENAMES=\(env["VK_ICD_FILENAMES"] ?? "")
        DYLD_LIBRARY_PATH=\(env["DYLD_LIBRARY_PATH"] ?? "")
        DYLD_FALLBACK_LIBRARY_PATH=\(env["DYLD_FALLBACK_LIBRARY_PATH"] ?? "")
        MTL_HUD_ENABLED=\(env["MTL_HUD_ENABLED"] ?? "")
        MTL_HUD_LAYER=\(env["MTL_HUD_LAYER"] ?? "")
        WINEDLLPATH=\(env["WINEDLLPATH"] ?? "")
        DXVK_FILTER_DEVICE_NAME=\(env["DXVK_FILTER_DEVICE_NAME"] ?? "")
        FORGE_D3DMETAL_RUNTIME=\(env["FORGE_D3DMETAL_RUNTIME"] ?? "")
        D3DMETAL_FRAMEWORK_PATH=\(env["D3DMETAL_FRAMEWORK_PATH"] ?? "")
        SteamAppId=\(env["SteamAppId"] ?? "")
        FORGE_STEAM_SAFE_MODE=\(env["FORGE_STEAM_SAFE_MODE"] ?? "")
        FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP=\(env["FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP"] ?? "")
        FORGE_GAME_WINEDLLOVERRIDES=\(env["FORGE_GAME_WINEDLLOVERRIDES"] ?? "")
        FORGE_GAME_WINE_D3D_CONFIG=\(env["FORGE_GAME_WINE_D3D_CONFIG"] ?? "")
        FORGE_GAME_LIBGL_ALWAYS_SOFTWARE=\(env["FORGE_GAME_LIBGL_ALWAYS_SOFTWARE"] ?? "")
        FORGE_GAME_VK_ICD_FILENAMES=\(env["FORGE_GAME_VK_ICD_FILENAMES"] ?? "")
        FORGE_GAME_VK_DRIVER_FILES=\(env["FORGE_GAME_VK_DRIVER_FILES"] ?? "")
        FORGE_GAME_MTL_HUD_ENABLED=\(env["FORGE_GAME_MTL_HUD_ENABLED"] ?? "")
        FORGE_GAME_MTL_HUD_LAYER=\(env["FORGE_GAME_MTL_HUD_LAYER"] ?? "")
        FORGE_GAME_DXVK_ASYNC=\(env["FORGE_GAME_DXVK_ASYNC"] ?? "")
        FORGE_GAME_DYLD_LIBRARY_PATH=\(env["FORGE_GAME_DYLD_LIBRARY_PATH"] ?? "")
        FORGE_GAME_WINEDLLPATH=\(env["FORGE_GAME_WINEDLLPATH"] ?? "")

        """
        if let data = launchSummary.data(using: .utf8) {
            log.write(data)
        }
        process.standardOutput = log
        process.standardError = log
        try process.run()
    }

    nonisolated static func setMetalHudDefaults(_ enabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "-g", "MetalForceHudEnabled", "-bool", enabled ? "YES" : "NO"]
        try process.run()
        process.waitUntilExit()
    }

    nonisolated static func stopWineSession(bottle: BottleEntry, config: AppConfig, profile: RuntimeProfile) throws {
        let winePath = profile.wine64Path.isEmpty ? config.wine64Path : profile.wine64Path
        let wineserverPath = profile.wineserverPath?.isEmpty == false
            ? profile.wineserverPath!
            : URL(fileURLWithPath: winePath).deletingLastPathComponent().appendingPathComponent("wineserver").path
        guard FileManager.default.fileExists(atPath: wineserverPath) else {
            throw ForgeError.message("wineserver not found next to Wine at \(wineserverPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineserverPath)
        process.arguments = ["-k"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "WINEPREFIX": bottle.prefixPath,
            "WINEDEBUG": "fixme-all"
        ]) { _, new in new }
        let log = try launchLogHandle()
        process.standardOutput = log
        process.standardError = log
        try process.run()
        process.waitUntilExit()
    }

    nonisolated static func ensurePrefix(prefixPath: String, winePath: String) throws {
        if FileManager.default.fileExists(atPath: prefixPath) { return }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: prefixPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: winePath)
        process.arguments = ["wineboot", "--init"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "WINEPREFIX": prefixPath,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1",
            "WINEDLLOVERRIDES": "mscoree,mshtml="
        ]) { _, new in new }
        let log = try launchLogHandle()
        process.standardOutput = log
        process.standardError = log
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ForgeError.message("wineboot failed for \(prefixPath)")
        }
    }

    nonisolated static func steamSafeArgs(_ extra: [String]) -> [String] {
        ["-no-cef-sandbox", "-cef-disable-sandbox"] + extra
    }

    nonisolated static func removeStagedD3DMetalDlls(exePath: String) throws {
        let gameDir = URL(fileURLWithPath: exePath).deletingLastPathComponent()
        for dll in ["dxgi.dll", "d3d9.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll"] {
            let target = gameDir.appendingPathComponent(dll)
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
            if attrs?[.type] as? FileAttributeType == .typeRegular || attrs?[.type] as? FileAttributeType == .typeSymbolicLink {
                try FileManager.default.removeItem(at: target)
            }
        }
    }

    nonisolated static func ensureDXVKInstalled(exePath: String, prefixPath: String, steamAppId: String?) throws {
        let fm = FileManager.default
        let sourceRoots = dxvkSourceRoots()
        guard let sourceRoot = sourceRoots.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("x64/d3d11.dll").path)
                && fm.fileExists(atPath: $0.appendingPathComponent("x64/dxgi.dll").path)
        }) else {
            throw ForgeError.message("DXVK runtime files were not found. Expected ~/Wine/Runtimes/dxvk-*/dxvk-*/x64/d3d11.dll.")
        }

        var targetDirs: [URL] = []
        let exeURL = URL(fileURLWithPath: exePath)
        if exeURL.lastPathComponent.caseInsensitiveCompare("steam.exe") != .orderedSame {
            targetDirs.append(exeURL.deletingLastPathComponent())
        }
        if let steamAppId, let steamGameDir = steamGameDirectory(prefixPath: prefixPath, appId: steamAppId) {
            targetDirs.append(steamGameDir)
        }

        var seen = Set<String>()
        let uniqueDirs = targetDirs.filter { seen.insert($0.path).inserted }
        let x64 = sourceRoot.appendingPathComponent("x64", isDirectory: true)
        for dir in uniqueDirs {
            for dll in ["dxgi.dll", "d3d9.dll", "d3d10core.dll", "d3d10.dll", "d3d10_1.dll", "d3d11.dll"] {
                let source = x64.appendingPathComponent(dll)
                if fm.fileExists(atPath: source.path) {
                    try copyIfDifferent(source, to: dir.appendingPathComponent(dll))
                }
            }
        }
    }

    nonisolated static func dxvkSourceRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runtimes = home.appendingPathComponent("Wine/Runtimes", isDirectory: true)
        var roots: [URL] = []
        if let entries = try? FileManager.default.contentsOfDirectory(at: runtimes, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries where entry.lastPathComponent.lowercased().contains("dxvk") {
                if let children = try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    roots.append(contentsOf: children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending })
                }
                roots.append(entry)
            }
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }

    nonisolated static func steamGameDirectory(prefixPath: String, appId: String) -> URL? {
        let steamapps = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appId).acf")
        guard let text = try? String(contentsOf: manifest) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "\"").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if parts.count >= 2, parts[0].trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("installdir") == .orderedSame {
                return steamapps.appendingPathComponent("common", isDirectory: true).appendingPathComponent(parts[1], isDirectory: true)
            }
        }
        return nil
    }

    nonisolated static func ensureDXMTInstalled(winePath: String, prefixPath: String) throws {
        let fm = FileManager.default
        let wineRoot = URL(fileURLWithPath: winePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimeWin64Dir = wineRoot.appendingPathComponent("lib/wine/x86_64-windows", isDirectory: true)
        let runtimeWin32Dir = wineRoot.appendingPathComponent("lib/wine/i386-windows", isDirectory: true)
        let runtimeUnixDir = wineRoot.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let system32 = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)

        guard fm.fileExists(atPath: runtimeWin64Dir.path), fm.fileExists(atPath: runtimeUnixDir.path) else {
            throw ForgeError.message("DXMT needs a Wine runtime with lib/wine/x86_64-windows and x86_64-unix directories.")
        }
        try fm.createDirectory(at: system32, withIntermediateDirectories: true)
        try fm.createDirectory(at: syswow64, withIntermediateDirectories: true)

        let sourceRoots = dxmtSourceRoots(wineRoot: wineRoot)
        guard let sourceRoot = sourceRoots.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("x86_64-windows/d3d11.dll").path)
                && fm.fileExists(atPath: $0.appendingPathComponent("x86_64-windows/dxgi.dll").path)
                && fm.fileExists(atPath: $0.appendingPathComponent("x86_64-unix/winemetal.so").path)
        }) else {
            throw ForgeError.message("DXMT runtime files were not found. Expected ~/Wine/Runtimes/dxmt-v*/v*/x86_64-windows and x86_64-unix.")
        }

        let windows64Source = sourceRoot.appendingPathComponent("x86_64-windows", isDirectory: true)
        let windows32Source = sourceRoot.appendingPathComponent("i386-windows", isDirectory: true)
        let unixSource = sourceRoot.appendingPathComponent("x86_64-unix", isDirectory: true)
        for dll in ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"] {
            let source64 = windows64Source.appendingPathComponent(dll)
            if fm.fileExists(atPath: source64.path) {
                try copyIfDifferent(source64, to: runtimeWin64Dir.appendingPathComponent(dll))
                // Unity checks for a real file before Wine resolves the builtin module.
                // Keep the PE builtin marker in system32, but use builtin overrides.
                try copyIfDifferent(source64, to: system32.appendingPathComponent(dll))
            }

            let source32 = windows32Source.appendingPathComponent(dll)
            if fm.fileExists(atPath: source32.path), fm.fileExists(atPath: runtimeWin32Dir.path) {
                try copyIfDifferent(source32, to: runtimeWin32Dir.appendingPathComponent(dll))
                // 32-bit Unity games like Among Us load through the 32-bit system DLL view.
                try copyIfDifferent(source32, to: syswow64.appendingPathComponent(dll))
            }
        }
        try copyIfDifferent(windows64Source.appendingPathComponent("d3d11.dll"), to: runtimeWin64Dir.appendingPathComponent("dd3d11.dll"))
        try copyIfDifferent(windows64Source.appendingPathComponent("d3d11.dll"), to: system32.appendingPathComponent("dd3d11.dll"))
        if fm.fileExists(atPath: windows32Source.appendingPathComponent("d3d11.dll").path), fm.fileExists(atPath: runtimeWin32Dir.path) {
            try copyIfDifferent(windows32Source.appendingPathComponent("d3d11.dll"), to: runtimeWin32Dir.appendingPathComponent("dd3d11.dll"))
            try copyIfDifferent(windows32Source.appendingPathComponent("d3d11.dll"), to: syswow64.appendingPathComponent("dd3d11.dll"))
        }
        try copyIfDifferent(unixSource.appendingPathComponent("winemetal.so"), to: runtimeUnixDir.appendingPathComponent("winemetal.so"))
    }

    nonisolated static func dxmtSourceRoots(wineRoot: URL) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runtimes = home.appendingPathComponent("Wine/Runtimes", isDirectory: true)
        var roots: [URL] = []
        if let entries = try? FileManager.default.contentsOfDirectory(at: runtimes, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries where entry.lastPathComponent.lowercased().contains("dxmt") {
                roots.append(entry)
                if let children = try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    roots.append(contentsOf: children)
                }
            }
        }
        roots.append(wineRoot.appendingPathComponent("lib/dxmt", isDirectory: true))
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }

    nonisolated static func copyIfDifferent(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            let sourceAttrs = try? fm.attributesOfItem(atPath: source.path)
            let destAttrs = try? fm.attributesOfItem(atPath: destination.path)
            if (sourceAttrs?[.size] as? NSNumber) == (destAttrs?[.size] as? NSNumber) { return }
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    nonisolated static func configureMoltenVK(profile: RuntimeProfile, config: AppConfig, env: inout [String: String]) {
        if let existing = env["VK_ICD_FILENAMES"], !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        let configured = profile.moltenvkPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidates = moltenVkIcdCandidates(configuredPath: configured)
        if let icd = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            env["VK_ICD_FILENAMES"] = icd
            env["VK_DRIVER_FILES"] = icd
        }

        env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] ?? "1"
        env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] = env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] ?? "1"
        env["MOLTENVK_CONFIG_LOG_LEVEL"] = env["MOLTENVK_CONFIG_LOG_LEVEL"] ?? "0"
    }

    nonisolated static func moltenVkIcdCandidates(configuredPath: String) -> [String] {
        var candidates: [String] = []
        func add(_ path: String) {
            if !path.isEmpty { candidates.append((path as NSString).expandingTildeInPath) }
        }

        add(configuredPath)
        if !configuredPath.isEmpty {
            add(URL(fileURLWithPath: configuredPath).appendingPathComponent("share/vulkan/icd.d/MoltenVK_icd.json").path)
            add(URL(fileURLWithPath: configuredPath).appendingPathComponent("MoltenVK_icd.json").path)
        }
        add("/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json")
        add("/usr/local/share/vulkan/icd.d/MoltenVK_icd.json")
        add("/opt/homebrew/Cellar/molten-vk/share/vulkan/icd.d/MoltenVK_icd.json")
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    nonisolated static func buildDyldPath(gptkLibPath: String?, existing: String) -> String {
        var parts: [String] = []
        if let gptkLibPath, !gptkLibPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let configured = URL(fileURLWithPath: gptkLibPath)
            parts.append(configured.path)
            if configured.lastPathComponent.caseInsensitiveCompare("external") == .orderedSame {
                parts.append(configured.appendingPathComponent("D3DMetal.framework/Versions/A").path)
                parts.append(configured.deletingLastPathComponent().path)
            } else {
                let external = configured.appendingPathComponent("external")
                parts.append(external.path)
                parts.append(external.appendingPathComponent("D3DMetal.framework/Versions/A").path)
            }
        }
        if !existing.isEmpty { parts.append(existing) }
        return dedupePathParts(parts).joined(separator: ":")
    }

    nonisolated static func gptkWineLibBase(gptkLibPath: String?) -> URL? {
        guard let gptkLibPath, !gptkLibPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let configured = URL(fileURLWithPath: gptkLibPath)
        if configured.lastPathComponent.caseInsensitiveCompare("external") == .orderedSame {
            return configured.deletingLastPathComponent()
        }
        if configured.lastPathComponent.caseInsensitiveCompare("lib") == .orderedSame {
            return configured
        }
        return configured
    }

    nonisolated static func d3dMetalFrameworkPath(gptkLibPath: String?) -> String? {
        guard let base = gptkWineLibBase(gptkLibPath: gptkLibPath) else { return nil }
        let candidates = [
            base.appendingPathComponent("external/D3DMetal.framework").path,
            base.appendingPathComponent("D3DMetal.framework").path,
            "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    nonisolated static func gptkWinePath(gptkLibPath: String?) -> String? {
        guard let base = gptkWineLibBase(gptkLibPath: gptkLibPath) else { return nil }
        let candidates = [
            base.appendingPathComponent("bin/wine64").path,
            base.deletingLastPathComponent().appendingPathComponent("bin/wine64").path,
            "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    nonisolated static func dedupePathParts(_ parts: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for part in parts where !part.isEmpty && !seen.contains(part) {
            seen.insert(part)
            output.append(part)
        }
        return output
    }

    nonisolated static func launchLogHandle() throws -> FileHandle {
        let dir = appSupportDir().appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("swiftui-launch-\(stamp).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try FileHandle(forWritingTo: url)
    }

    nonisolated static func downloadSteamInstaller() throws -> URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ForgeNative/installers", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("SteamSetup.exe")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let url = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
        let data = try Data(contentsOf: url)
        try data.write(to: target, options: .atomic)
        return target
    }
}

// MARK: - Models

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
        RuntimeProfile(
            id: "forge-cx-wine11-open-wow64",
            name: "Forge Wine 11 Open WoW64 + MoltenVK",
            wine64Path: NSHomeDirectory() + "/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wine",
            wineserverPath: NSHomeDirectory() + "/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wineserver",
            gptkLibPath: config.gptkLibPath.isEmpty ? nil : config.gptkLibPath,
            dxvkPath: nil,
            vkd3dPath: nil,
            moltenvkPath: "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json",
            defaultBackend: .dxvkVkd3d,
            env: ["VK_ICD_FILENAMES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"]
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
        URL(fileURLWithPath: path).lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame
    }
}

struct GameCompatibilityProfile: Codable, Identifiable {
    var id: String
    var displayName: String
    var backendOverride: GraphicsBackend?
    var launchArgs: [String]
    var env: [String: String]
    var notes: String?
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
