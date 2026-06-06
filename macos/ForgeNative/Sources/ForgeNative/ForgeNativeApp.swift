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
        HStack(spacing: 18) {
            sidebar(bottle)
                .frame(width: 260)

            VStack(spacing: 18) {
                topBar
                runtimePanel(bottle)
                appsPanel(bottle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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
                BottleCard(bottle: bottle, statusText: store.statusText, isReady: store.prefixExists)
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Status")
                StatusLine(icon: "shippingbox.fill", title: store.prefixExists ? "Bottle ready" : "Bottle missing", value: bottle.name)
                StatusLine(icon: "app.badge.fill", title: "Launchable apps", value: "\(store.apps.count)")
                StatusLine(icon: "display", title: "Backend", value: backendText(for: bottle))
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
        .padding(18)
        .liquidGlass(cornerRadius: 30, opacity: 0.34)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Library")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Drop a Windows EXE, select one manually, or launch the main app in your bottle.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
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
                selectAction: { store.selectExe() }
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
                                backendText: backendText(for: bottle),
                                hudText: store.config.globalHud ? "Metal HUD" : "Off",
                                isLaunching: store.isLaunching
                            ) {
                                store.launch(app)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(cornerRadius: 30, opacity: 0.28)
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
        return backend.displayName
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
    let selectAction: () -> Void

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

            Button("Select EXE", action: selectAction)
                .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.15)))
                .disabled(isDisabled)
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
                .fill(.ultraThinMaterial.opacity(0.48))
                .ignoresSafeArea()

            Rectangle()
                .fill(.black.opacity(0.08))
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
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
            TextField("Search Library", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(.black.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

struct LiquidAppRow: View {
    let app: BottleAppItem
    let backendText: String
    let hudText: String
    let isLaunching: Bool
    let launch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 14) {
                    ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                    Image(systemName: app.kind == "launcher" ? "bolt.fill" : "gamecontroller.fill")
                        .font(.system(size: 20, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.78))
                }
                .frame(width: 54, height: 54)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))

                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    Text(app.path)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.36))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(app.kind.capitalized)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 92, alignment: .leading)

            Text(backendText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 132, alignment: .leading)

            Text(hudText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(hudText == "Off" ? Color.white.opacity(0.38) : Color.white.opacity(0.70))
                .frame(width: 112, alignment: .leading)

            Button("Play", action: launch)
                .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.18), foreground: .white.opacity(0.94)))
                .disabled(isLaunching)
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .liquidGlass(cornerRadius: 22, opacity: 0.32)
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
    var tint: Color = .white.opacity(0.12)
    var foreground: Color = .white.opacity(0.92)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 15)
            .padding(.vertical, 9.5)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(configuration.isPressed ? 0.40 : 0.92),
                                        .white.opacity(configuration.isPressed ? 0.035 : 0.11),
                                        .cyan.opacity(configuration.isPressed ? 0.02 : 0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.46), .white.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.10 : 0.20), radius: configuration.isPressed ? 8 : 16, x: 0, y: configuration.isPressed ? 4 : 10)
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
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
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.20),
                                .white.opacity(0.055),
                                .cyan.opacity(0.055),
                                .black.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.58),
                                .white.opacity(0.16),
                                .white.opacity(0.045),
                                .cyan.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.15
                    )
                    .blendMode(.screen)
            }
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(.white.opacity(0.30))
                    .frame(width: 86, height: 2)
                    .blur(radius: 1.4)
                    .offset(x: 24, y: 13)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 18)
            .shadow(color: .white.opacity(0.035), radius: 1, x: 0, y: -1)
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
        case .none: return "None"
        }
    }
}

// MARK: - Store

@MainActor
final class ForgeStore: ObservableObject {
    @Published var config = AppConfig.defaults
    @Published var profiles: [RuntimeProfile] = []
    @Published var bottle: BottleEntry?
    @Published var apps: [BottleAppItem] = []
    @Published var steamPath: String?
    @Published var prefixExists = false
    @Published var isLaunching = false
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
            bottle = try Self.loadBottle(from: support, config: config)
            refreshBottleState()
        } catch {
            alertMessage = error.localizedDescription
        }
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
                    forceSteamMode: false
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

    func launch(_ app: BottleAppItem) {
        guard let bottle else { return }
        isLaunching = true
        Task.detached(priority: .userInitiated) {
            do {
                try await Self.spawn(
                    exePath: app.path,
                    bottle: bottle,
                    config: await MainActor.run { self.config },
                    profile: await MainActor.run { self.profile(for: bottle) },
                    extraArgs: [],
                    forceSteamMode: app.isSteamClient
                )
                await MainActor.run {
                    self.isLaunching = false
                }
            } catch {
                await MainActor.run {
                    self.isLaunching = false
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func revealBottle() {
        guard let bottle else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bottle.prefixPath)])
    }

    func setMetalHud(_ enabled: Bool) {
        config.globalHud = enabled
        do {
            try Self.saveConfig(config, to: Self.appSupportDir())
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

    private func profile(for bottle: BottleEntry) -> RuntimeProfile {
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

    nonisolated static func loadBottle(from support: URL, config: AppConfig) throws -> BottleEntry {
        let url = support.appendingPathComponent("bottles.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BottleEntry(
                name: "Default",
                prefixPath: config.defaultPrefix,
                runtimeProfileId: "wine-vulkan",
                graphicsBackend: nil,
                envOverrides: [:]
            )
        }

        let decoded = try JSONDecoder.forge.decode([BottleEntry].self, from: Data(contentsOf: url))
        return decoded.first(where: { $0.prefixPath == config.defaultPrefix })
            ?? decoded.first
            ?? BottleEntry(
                name: "Default",
                prefixPath: config.defaultPrefix,
                runtimeProfileId: "wine-vulkan",
                graphicsBackend: nil,
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

    nonisolated static func push(path: String, kind: String, into apps: inout [BottleAppItem], seen: inout Set<String>) {
        let normalized = path.standardizingPath
        guard seen.insert(normalized.lowercased()).inserted else { return }
        apps.append(BottleAppItem(name: displayName(for: normalized), path: normalized, kind: kind))
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
        forceSteamMode: Bool
    ) async throws {
        let winePath = profile.wine64Path.isEmpty ? config.wine64Path : profile.wine64Path
        guard FileManager.default.fileExists(atPath: winePath) else {
            throw ForgeError.message("wine not found at \(winePath)")
        }

        try ensurePrefix(prefixPath: bottle.prefixPath, winePath: winePath)

        let isSteam = forceSteamMode || URL(fileURLWithPath: exePath).lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame
        let gameBackend = bottle.graphicsBackend ?? profile.defaultBackend
        let launchBackend: GraphicsBackend = gameBackend

        let gptkLibPath = profile.gptkLibPath ?? config.gptkLibPath
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        if launchBackend == .d3dMetal {
            env["DYLD_LIBRARY_PATH"] = buildDyldPath(gptkLibPath: gptkLibPath, existing: env["DYLD_LIBRARY_PATH"] ?? "")
        } else {
            // DXVK/VKD3D should use Forge/Homebrew MoltenVK. Do not let GPTK's
            // older external libMoltenVK shadow the Vulkan 1.3+ ICD needed by DXVK.
            env.removeValue(forKey: "DYLD_LIBRARY_PATH")
        }
        env["WINEDEBUG"] = config.suppressWineDebug ? "fixme-all" : ""
        env["GST_DEBUG"] = "1"
        env["MTL_HUD_ENABLED"] = config.globalHud ? "1" : "0"
        env["WINE_MOUSE_WARP"] = "1"
        env["WINEESYNC"] = "1"
        env["WINEMSYNC"] = "1"
        if launchBackend == .dxvk || launchBackend == .vkd3d || launchBackend == .dxvkVkd3d {
            configureMoltenVK(profile: profile, config: config, env: &env)
        }

        switch launchBackend {
        case .d3dMetal:
            if let gptkBase = gptkWineLibBase(gptkLibPath: gptkLibPath) {
                let dllPath = gptkBase.appendingPathComponent("wine/x86_64-windows").path
                if FileManager.default.fileExists(atPath: dllPath) {
                    if let existing = env["WINEDLLPATH"], !existing.isEmpty {
                        env["WINEDLLPATH"] = dllPath + ":" + existing
                    } else {
                        env["WINEDLLPATH"] = dllPath
                    }
                }
            }
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,d3d12=n,b;user32=n,b"
        case .dxvk:
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,user32=n,b"
            env["DXVK_ASYNC"] = "1"
        case .vkd3d:
            env["WINEDLLOVERRIDES"] = "d3d12,dxgi,user32=n,b"
        case .dxvkVkd3d:
            env["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b"
            env["DXVK_ASYNC"] = "1"
        case .wineBuiltin:
            env["WINEDLLOVERRIDES"] = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            env["WINE_D3D_CONFIG"] = "renderer=gl"
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        case .none:
            break
        }

        for (key, value) in config.env { env[key] = value }
        for (key, value) in profile.env { env[key] = value }
        for (key, value) in bottle.envOverrides { env[key] = value }

        if false && isSteam {
            let gameVkIcd = env["VK_ICD_FILENAMES"] ?? ""
            let gameDyldPath = gameBackend == .d3dMetal ? buildDyldPath(gptkLibPath: gptkLibPath, existing: env["DYLD_LIBRARY_PATH"] ?? "") : ""
            var gameWineDllPath = ""
            if gameBackend == .d3dMetal, let gptkBase = gptkWineLibBase(gptkLibPath: gptkLibPath) {
                let dllPath = gptkBase.appendingPathComponent("wine/x86_64-windows").path
                if FileManager.default.fileExists(atPath: dllPath) {
                    gameWineDllPath = dllPath
                }
            }
            let gameDllOverrides: String
            switch gameBackend {
            case .d3dMetal:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,d3d12=n,b;user32=n,b"
            case .dxvk:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,user32=n,b"
            case .vkd3d:
                gameDllOverrides = "d3d12,dxgi,user32=n,b"
            case .dxvkVkd3d:
                gameDllOverrides = "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b"
            case .wineBuiltin:
                gameDllOverrides = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            case .none:
                gameDllOverrides = ""
            }

            // Steam's Chromium UI is stable in this safe backend, but games launched
            // from Steam must not inherit these variables. Forge Wine detects this
            // marker and restores the FORGE_GAME_* values for non-Steam child EXEs.
            env["FORGE_STEAM_SAFE_MODE"] = "1"
            env["FORGE_GAME_WINEDLLOVERRIDES"] = gameDllOverrides
            env["FORGE_GAME_VK_ICD_FILENAMES"] = gameVkIcd
            env["FORGE_GAME_MTL_HUD_ENABLED"] = config.globalHud ? "1" : "0"
            env["FORGE_GAME_DYLD_LIBRARY_PATH"] = gameDyldPath
            env["FORGE_GAME_WINEDLLPATH"] = gameWineDllPath
            env["MOLTENVK_CONFIG_LOG_LEVEL"] = env["MOLTENVK_CONFIG_LOG_LEVEL"] ?? "0"

            env["WINEDLLOVERRIDES"] = "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            env["WINE_D3D_CONFIG"] = "renderer=gl"
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
            env["VK_ICD_FILENAMES"] = "/dev/null"
            env["VK_DRIVER_FILES"] = "/dev/null"
            env["DXVK_FILTER_DEVICE_NAME"] = "__forge_disable_dxvk_for_steam__"
            env["MTL_HUD_ENABLED"] = config.globalHud ? "1" : "0"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: winePath)
        process.arguments = ["start", "/unix", exePath] + (isSteam ? steamSafeArgs(extraArgs) : extraArgs)
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
        steamGameBackend=\(isSteam ? gameBackend.rawValue : "")
        args=\(process.arguments?.joined(separator: " ") ?? "")
        WINEDLLOVERRIDES=\(env["WINEDLLOVERRIDES"] ?? "")
        WINE_D3D_CONFIG=\(env["WINE_D3D_CONFIG"] ?? "")
        VK_ICD_FILENAMES=\(env["VK_ICD_FILENAMES"] ?? "")
        DYLD_LIBRARY_PATH=\(env["DYLD_LIBRARY_PATH"] ?? "")
        MTL_HUD_ENABLED=\(env["MTL_HUD_ENABLED"] ?? "")

        """
        if let data = launchSummary.data(using: .utf8) {
            log.write(data)
        }
        process.standardOutput = log
        process.standardError = log
        try process.run()
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
                parts.append(configured.deletingLastPathComponent().path)
            } else {
                parts.append(configured.appendingPathComponent("external").path)
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
        return configured
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
            id: "wine-vulkan",
            name: "Wine 11 + MoltenVK",
            wine64Path: config.wine64Path,
            wineserverPath: nil,
            gptkLibPath: nil,
            dxvkPath: nil,
            vkd3dPath: nil,
            moltenvkPath: nil,
            defaultBackend: .dxvkVkd3d,
            env: [:]
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

    var isSteamClient: Bool {
        URL(fileURLWithPath: path).lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame
    }
}

enum GraphicsBackend: String, Codable, Equatable {
    case d3dMetal = "d3dmetal"
    case dxvk
    case vkd3d
    case dxvkVkd3d = "dxvk_vkd3d"
    case wineBuiltin = "wine_builtin"
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
