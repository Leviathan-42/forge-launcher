import SwiftUI

struct GameProfileEditorSheet: View {
    private static let bottleDefaultBackend = "__bottle_default__"

    let app: BottleAppItem
    let effectiveBackend: GraphicsBackend
    let canReset: Bool
    let save: (GraphicsBackend?, [String], [String: String], String?) -> Void
    let reset: () -> Void
    let cancel: () -> Void

    @State private var backendSelection: String
    @State private var launchArgsText: String
    @State private var envText: String
    @State private var notesText: String
    @State private var validationMessage: String?

    init(
        app: BottleAppItem,
        profile: GameCompatibilityProfile,
        effectiveBackend: GraphicsBackend,
        canReset: Bool,
        save: @escaping (GraphicsBackend?, [String], [String: String], String?) -> Void,
        reset: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.app = app
        self.effectiveBackend = effectiveBackend
        self.canReset = canReset
        self.save = save
        self.reset = reset
        self.cancel = cancel
        _backendSelection = State(initialValue: profile.backendOverride?.rawValue ?? Self.bottleDefaultBackend)
        _launchArgsText = State(initialValue: ForgeStore.formatLaunchArgs(profile.launchArgs))
        _envText = State(initialValue: ForgeStore.formatEnvOverrides(profile.env))
        _notesText = State(initialValue: profile.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.10))
                    Image(systemName: app.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.74))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(app.path)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.08), in: Circle())
                .help("Close")
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Backend")
                Picker("Backend", selection: $backendSelection) {
                    Text("Bottle Default (\(effectiveBackend.displayName))").tag(Self.bottleDefaultBackend)
                    ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Launch Args")
                TextField("Launch arguments", text: $launchArgsText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .profileEditorFieldBackground()
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Environment")
                    TextEditor(text: $envText)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 128)
                        .profileEditorFieldBackground()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Notes")
                    TextEditor(text: $notesText)
                        .font(.system(size: 12, weight: .regular))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 128)
                        .profileEditorFieldBackground()
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.84))
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button {
                    reset()
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(
                    ForgeButtonStyle(
                        tint: .white.opacity(0.09),
                        foreground: resetButtonForeground
                    )
                )
                .disabled(!canReset)

                Spacer()

                Button("Cancel", action: cancel)
                    .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.09), foreground: .white.opacity(0.78)))

                Button {
                    saveProfile()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(ForgeButtonStyle(tint: .white.opacity(0.17), foreground: .white.opacity(0.96)))
            }
        }
        .padding(22)
        .frame(width: 640)
        .background(.black.opacity(0.56))
    }

    private var resetButtonForeground: Color {
        .white.opacity(canReset ? 0.84 : 0.42)
    }

    private var selectedBackendOverride: GraphicsBackend? {
        backendSelection == Self.bottleDefaultBackend
            ? nil
            : GraphicsBackend(rawValue: backendSelection)
    }

    private func saveProfile() {
        do {
            let launchArgs = try ForgeStore.parseLaunchArgs(launchArgsText)
            let env = try ForgeStore.parseEnvOverrides(envText)
            let notes = ForgeStore.cleanedProfileNotes(notesText)
            save(selectedBackendOverride, launchArgs, env, notes)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

private struct ProfileEditorFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        content
            .background(.white.opacity(0.07), in: shape)
            .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

private extension View {
    func profileEditorFieldBackground() -> some View {
        modifier(ProfileEditorFieldBackground())
    }
}
