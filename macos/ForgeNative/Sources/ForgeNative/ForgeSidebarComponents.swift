import SwiftUI

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
        .sidebarCardBackground(cornerRadius: 22, fillOpacity: 0.06, strokeOpacity: 0.12)
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

struct RuntimeProfilePickerCard: View {
    let profiles: [RuntimeProfile]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Wine Runtime", systemImage: "cpu")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            Picker("Wine Runtime", selection: $selection) {
                ForEach(profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Text(guidance)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .sidebarCardBackground()
    }

    private var selectedProfile: RuntimeProfile? {
        profiles.first(where: { $0.id == selection })
    }

    private var guidance: String {
        guard let selectedProfile else { return "Select the Wine runtime used to start this bottle." }
        if ForgeStore.isCrossOverRuntime(profile: selectedProfile) {
            return "Uses CrossOver's Wine and bottle compatibility directly. The CrossOver app UI is not opened."
        }
        return "Uses Forge's bundled Wine runtime and Forge-managed graphics handoff."
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
        .sidebarCardBackground()
    }
}

private struct BackendGuideRow: View {
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

            Text(
                "Only appears for Metal-backed rendering. " +
                    "Steam itself may hide it; games launched after toggling should inherit it."
            )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .sidebarCardBackground()
    }
}

private struct SidebarCardBackground: ViewModifier {
    var cornerRadius: CGFloat = 20
    var fillOpacity = 0.055
    var strokeOpacity = 0.10

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(.white.opacity(fillOpacity), in: shape)
            .overlay(shape.stroke(.white.opacity(strokeOpacity), lineWidth: 1))
    }
}

private extension View {
    func sidebarCardBackground(
        cornerRadius: CGFloat = 20,
        fillOpacity: Double = 0.055,
        strokeOpacity: Double = 0.10
    ) -> some View {
        modifier(
            SidebarCardBackground(
                cornerRadius: cornerRadius,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity
            )
        )
    }
}
