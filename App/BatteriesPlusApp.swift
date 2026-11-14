import SwiftUI

@main
struct BatteriesPlusApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Batteries++", id: "devices") {
            DevicesView().environmentObject(model)
                .frame(minWidth: 660, minHeight: 520)
        }
        .defaultSize(width: 760, height: 640)

        MenuBarExtra("Batteries++", systemImage: "battery.100percent") {
            MenuContent().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(spacing: 14) {
            ForEach(model.devices.prefix(8)) { device in BatteryRow(device: device) }
            if model.devices.isEmpty { Text(L10n.text("No battery devices")).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Button(L10n.text("Manage Devices")) {
                    openWindow(id: "devices")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button(L10n.text("Quit")) { NSApp.terminate(nil) }
            }
        }
        .padding(18)
        .frame(width: 330)
    }
}
