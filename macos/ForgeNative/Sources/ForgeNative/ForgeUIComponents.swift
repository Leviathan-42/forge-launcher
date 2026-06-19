import SwiftUI

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

struct CompatibilityProfileBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .imageScale(.small)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.secondary.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

struct LiquidAppRow: View {
    let app: BottleAppItem
    let backend: GraphicsBackend
    let backendIsAppSpecific: Bool
    let profileCanReset: Bool
    let launchArgs: [String]
    let envKeys: [String]
    let notes: String?
    let hudText: String
    let isLaunching: Bool
    let isRunning: Bool
    let setBackend: (GraphicsBackend) -> Void
    let resetProfile: () -> Void
    let editProfile: () -> Void
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

            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(app.path)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                profileDetails
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

                Button(action: resetProfile) {
                    Image(systemName: profileCanReset
                          ? "arrow.uturn.backward.circle.fill"
                          : (backendIsAppSpecific ? "checkmark.seal.fill" : "checkmark.circle"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(profileCanReset ? Color.primary : Color.secondary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(profileCanReset
                      ? "Reset to recommended profile"
                      : (backendIsAppSpecific ? "Using recommended profile" : "Using bottle default"))
                .disabled(!profileCanReset)

                Button(action: editProfile) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit compatibility profile")
            }
            .frame(width: 176, alignment: .leading)

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

    @ViewBuilder
    private var profileDetails: some View {
        if !launchArgs.isEmpty || !envKeys.isEmpty || firstNoteLine != nil {
            HStack(spacing: 6) {
                if !launchArgs.isEmpty {
                    CompatibilityProfileBadge(icon: "terminal", text: launchArgs.joined(separator: " "))
                        .frame(maxWidth: 220, alignment: .leading)
                }

                if !envKeys.isEmpty {
                    CompatibilityProfileBadge(icon: "slider.horizontal.3", text: envSummary)
                        .frame(maxWidth: 170, alignment: .leading)
                }

                if let firstNoteLine {
                    CompatibilityProfileBadge(icon: "note.text", text: firstNoteLine)
                        .frame(maxWidth: 240, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var firstNoteLine: String? {
        notes?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var envSummary: String {
        if envKeys.count <= 2 {
            return envKeys.joined(separator: ", ")
        }
        return "\(envKeys.count) env vars"
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
