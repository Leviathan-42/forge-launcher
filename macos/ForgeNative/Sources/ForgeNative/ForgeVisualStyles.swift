import SwiftUI

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
