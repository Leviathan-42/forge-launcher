import SwiftUI

struct DropExeCard: View {
    let isTargeted: Bool
    let isDisabled: Bool
    let isRunning: Bool
    let selectAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RuntimeCardHeader(
                icon: isTargeted ? "arrow.down.doc.fill" : "plus.app.fill",
                title: isTargeted ? "Drop to Run" : "Add EXE",
                subtitle: "Drag a Windows .exe here or select one from Finder.",
                iconFontSize: 22,
                iconFrameSize: 46,
                iconCornerRadius: 17,
                iconBackgroundOpacity: isTargeted ? 0.18 : 0.10,
                iconForegroundOpacity: 0.88
            )

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
    var isDisabled = false
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RuntimeCardHeader(
                icon: icon,
                title: title,
                subtitle: subtitle,
                titleOpacity: 0.92,
                subtitleOpacity: 0.42,
                subtitleTruncationMode: .middle
            )

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

private struct RuntimeCardHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    var titleOpacity = 0.94
    var subtitleOpacity = 0.44
    var subtitleTruncationMode: Text.TruncationMode = .tail
    var iconFontSize: CGFloat = 20
    var iconFrameSize: CGFloat = 42
    var iconCornerRadius: CGFloat = 16
    var iconBackgroundOpacity = 0.10
    var iconForegroundOpacity = 0.84

    var body: some View {
        HStack(spacing: 11) {
            RuntimeCardIcon(
                systemName: icon,
                fontSize: iconFontSize,
                frameSize: iconFrameSize,
                cornerRadius: iconCornerRadius,
                backgroundOpacity: iconBackgroundOpacity,
                foregroundOpacity: iconForegroundOpacity
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(titleOpacity))
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(subtitleOpacity))
                    .lineLimit(2)
                    .truncationMode(subtitleTruncationMode)
            }
        }
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
