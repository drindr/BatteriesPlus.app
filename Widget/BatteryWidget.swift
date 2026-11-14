import SwiftUI
import WidgetKit

struct BatteryEntry: TimelineEntry {
    let date: Date
    let devices: [BatteryDevice]
    var error: String?
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: .now, devices: [
            BatteryDevice(id: "preview", name: "Mac", level: 82, charging: false,
                          symbol: "laptopcomputer", iconFile: nil, isCustom: false)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(60))))
    }

    private func current() -> BatteryEntry {
        do {
            let custom = try DeviceStore.read()
            return BatteryEntry(date: .now, devices: BatteryDevice.current(custom: custom))
        } catch {
            return BatteryEntry(date: .now, devices: BatteryDevice.current(custom: []), error: error.localizedDescription)
        }
    }
}

struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BatteryEntry

    var body: some View {
        Group {
            if entry.devices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "battery.100percent").font(.largeTitle)
                    Text(entry.error ?? L10n.text("Open Batteries++ to register a device"))
                        .font(.caption).multilineTextAlignment(.center)
                }
            } else if family == .systemLarge {
                VStack(spacing: 14) {
                    ForEach(entry.devices.prefix(6)) { device in BatteryRow(device: device) }
                    Spacer(minLength: 0)
                }
            } else {
                let maximum = family == .systemSmall ? 2 : 4
                HStack(spacing: family == .systemSmall ? 16 : 22) {
                    ForEach(entry.devices.prefix(maximum)) { device in
                        ChargeRing(device: device, compact: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(URL(string: "batteriesplus://devices"))
    }
}

@main
struct BatteriesPlusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DeviceStore.widgetKind, provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("Batteries++")
        .description(Text(L10n.text("Battery levels for system and custom devices, with custom icons.")))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(true)
        .preferredBackgroundStyle(.blur)
    }
}
