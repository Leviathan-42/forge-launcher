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
