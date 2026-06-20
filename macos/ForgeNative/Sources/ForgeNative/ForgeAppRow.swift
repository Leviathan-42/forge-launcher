import SwiftUI

private struct CompatibilityProfileBadge: View {
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
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
                Image(systemName: app.symbolName)
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

            Text(app.kindDisplayName)
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
                    Image(systemName: resetProfileIconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(resetProfileIconColor)
                }
                .buttonStyle(.plain)
                .help(resetProfileHelp)
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

            Button(launchButtonTitle, action: launchButtonAction)
                .buttonStyle(ForgeButtonStyle(tint: launchButtonTint, foreground: .primary))
                .disabled(launchButtonIsDisabled)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
    }

    private var resetProfileIconName: String {
        if profileCanReset {
            return "arrow.uturn.backward.circle.fill"
        }
        return backendIsAppSpecific ? "checkmark.seal.fill" : "checkmark.circle"
    }

    private var resetProfileIconColor: Color {
        profileCanReset ? Color.primary : Color.secondary.opacity(0.45)
    }

    private var resetProfileHelp: String {
        if profileCanReset {
            return "Reset to recommended profile"
        }
        return backendIsAppSpecific ? "Using recommended profile" : "Using bottle default"
    }

    private var launchButtonTitle: String {
        isRunning ? "Stop" : "Play"
    }

    private var launchButtonAction: () -> Void {
        isRunning ? stop : launch
    }

    private var launchButtonTint: Color {
        isRunning ? .red.opacity(0.24) : .white.opacity(0.11)
    }

    private var launchButtonIsDisabled: Bool {
        isLaunching && !isRunning
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
