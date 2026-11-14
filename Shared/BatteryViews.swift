import SwiftUI
import WidgetKit

struct DeviceIcon: View {
    let device: BatteryDevice

    var body: some View {
        Group {
            if let image = DeviceStore.icon(named: device.iconFile) {
                if #available(macOS 15.0, *) {
                    Image(nsImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.accentedDesaturated)
                        .scaledToFit()
                } else {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            } else if device.symbol == "elytra.left" || device.symbol == "elytra.right" {
                Image(device.symbol == "elytra.right" ? "ElytraRight" : "ElytraLeft")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                let symbol = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil) == nil
                    ? "battery.100percent" : device.symbol
                Image(systemName: symbol).resizable().scaledToFit().padding(2)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ChargeRing: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let device: BatteryDevice
    var compact = false

    private var color: Color {
        guard renderingMode == .fullColor else { return .primary }
        return device.charging ? .green : (device.level <= 20 ? .red : .green)
    }

    var body: some View {
        VStack(spacing: compact ? 5 : 8) {
            ZStack {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.14), lineWidth: compact ? 5 : 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(device.level) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: compact ? 5 : 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
                }
                .mask {
                    Rectangle().padding(-6).overlay {
                        if device.charging {
                            Circle()
                                .frame(width: 18, height: 18)
                                .offset(x: compact ? 19 : 25, y: compact ? 19 : 25)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }
                DeviceIcon(device: device)
                    .frame(width: compact ? 25 : 34, height: compact ? 25 : 34)
                if device.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                        .padding(3)
                        .widgetAccentable()
                        .offset(x: compact ? 19 : 25, y: compact ? 19 : 25)
                }
            }
            .frame(width: compact ? 58 : 78, height: compact ? 58 : 78)
            Text("\(device.level)%")
                .font(.system(compact ? .caption : .body, design: .rounded, weight: .medium))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.charging
            ? L10n.text("%@, battery %d%%, charging", device.name, device.level)
            : L10n.text("%@, battery %d%%", device.name, device.level))
    }
}

struct BatteryRow: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let device: BatteryDevice

    private var color: Color {
        guard renderingMode == .fullColor else { return .primary }
        return device.level <= 20 && !device.charging ? .red : .green
    }

    var body: some View {
        HStack(spacing: 12) {
            DeviceIcon(device: device).frame(width: 28, height: 28)
            Text(device.name).lineLimit(1)
            Spacer(minLength: 8)
            if device.charging {
                Image(systemName: "bolt.fill").foregroundStyle(color).widgetAccentable()
            }
            Text("\(device.level)%").monospacedDigit()
            Image(systemName: batterySymbol)
                .foregroundStyle(color)
                .widgetAccentable()
        }
        .font(.system(.body, design: .rounded))
        .accessibilityElement(children: .combine)
    }

    private var batterySymbol: String {
        switch device.level {
        case 0...10: return "battery.0percent"
        case 11...35: return "battery.25percent"
        case 36...60: return "battery.50percent"
        case 61...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
