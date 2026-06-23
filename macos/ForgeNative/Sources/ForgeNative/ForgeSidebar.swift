import AppKit
import SwiftUI

struct ForgeSidebar: View {
    @ObservedObject var store: ForgeStore
    let bottle: BottleEntry

    var body: some View {
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
                StatusLine(
                    icon: "shippingbox.fill",
                    title: store.prefixExists ? "Bottle ready" : "Bottle missing",
                    value: bottle.name
                )
                StatusLine(icon: "app.badge.fill", title: "Launchable apps", value: "\(store.apps.count)")
                RuntimeProfilePickerCard(
                    profiles: store.profiles,
                    selection: Binding(
                        get: { store.bottle?.runtimeProfileId ?? bottle.runtimeProfileId },
                        set: { store.setRuntimeProfile($0) }
                    )
                )
                BackendPickerCard(
                    selection: Binding(
                        get: { store.defaultBackend(for: bottle) },
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
}
