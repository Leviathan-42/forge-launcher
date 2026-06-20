import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ForgeRuntimePanel: View {
    @ObservedObject var store: ForgeStore
    let bottle: BottleEntry
    @Binding var isDropTarget: Bool

    var body: some View {
        HStack(spacing: 14) {
            DropExeCard(
                isTargeted: isDropTarget,
                isDisabled: store.isLaunching,
                isRunning: store.runningAppPath != nil,
                selectAction: { store.selectExe() },
                stopAction: { store.stopRunningApp() }
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
                handleExeDrop(providers)
            }

            RuntimeActionCard(
                icon: steamInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill",
                title: "Windows Steam",
                subtitle: steamInstalled
                    ? "Open the Steam client inside this bottle."
                    : "Download and run the Steam installer.",
                primaryTitle: steamInstalled ? "Open" : "Install",
                isDisabled: store.isLaunching,
                primaryAction: {
                    if steamInstalled {
                        store.openSteam()
                    } else {
                        store.installSteam()
                    }
                }
            )

            RuntimeActionCard(
                icon: "folder.fill",
                title: "Bottle Folder",
                subtitle: bottle.prefixPath,
                primaryTitle: "Reveal",
                primaryAction: { store.revealBottle() }
            )

            RuntimeActionCard(
                icon: "arrow.clockwise.circle.fill",
                title: "Rescan",
                subtitle: "Refresh installed launchers and EXEs.",
                primaryTitle: "Refresh",
                primaryAction: { store.reload() }
            )
        }
    }

    private var steamInstalled: Bool {
        store.steamPath != nil
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
}
