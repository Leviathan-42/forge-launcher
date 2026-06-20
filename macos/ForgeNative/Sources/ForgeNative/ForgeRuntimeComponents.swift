import SwiftUI

struct DropExeCard: View {
    let isTargeted: Bool
    let isDisabled: Bool
    let isRunning: Bool
    let selectAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                RuntimeCardIcon(
                    systemName: isTargeted ? "arrow.down.doc.fill" : "plus.app.fill",
                    fontSize: 22,
                    frameSize: 46,
                    cornerRadius: 17,
                    backgroundOpacity: isTargeted ? 0.18 : 0.10,
                    foregroundOpacity: 0.88
                )

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
                RuntimeCardIcon(systemName: icon)

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

private struct RuntimeCardIcon: View {
    let systemName: String
    var fontSize: CGFloat = 20
    var frameSize: CGFloat = 42
    var cornerRadius: CGFloat = 16
    var backgroundOpacity = 0.10
    var foregroundOpacity = 0.84

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: fontSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(foregroundOpacity))
            .frame(width: frameSize, height: frameSize)
            .background(
                .white.opacity(backgroundOpacity),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
