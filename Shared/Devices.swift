import AppKit
import Foundation

struct CustomDevice: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String = "Keyboard"
    var level: Int = 75
    var charging: Bool = false
    var symbol: String = "keyboard.fill"
    var iconFile: String?
    var syncToSystem: Bool = true
    var script: BatteryScript?
    var connected: Bool?

    var isAvailable: Bool { script == nil || connected == true }

    var systemIdentifier: String { "local.batteriesplus.\(id)" }

    var powerSourceDetails: [String: Any] {
        [
            "Type": "Accessory Source",
            "Accessory Category": category,
            "Accessory Identifier": systemIdentifier,
            "Name": name,
            "Transport Type": "Bluetooth",
            "Power Source State": charging ? "AC Power" : "Battery Power",
            "Current Capacity": level,
            "Max Capacity": 100,
            "Is Present": isAvailable,
            "Is Charging": charging
        ]
    }

    func validate() throws {
        guard !id.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeviceError.invalid(L10n.text("Device ID and name must not be empty"))
        }
        guard (0...100).contains(level) else { throw DeviceError.invalid(L10n.text("Battery level must be between 0 and 100")) }
        guard Self.categories.contains(category) else { throw DeviceError.invalid(L10n.text("Unsupported device category")) }
        try script?.validate()
        if let iconFile, URL(fileURLWithPath: iconFile).lastPathComponent != iconFile {
            throw DeviceError.invalid(L10n.text("Invalid icon filename"))
        }
    }

    static let categories = ["Keyboard", "Mouse", "Trackpad", "Headset", "Speaker", "Unknown"]

    static func symbol(for category: String, part: String? = nil) -> String {
        switch category {
        case "Keyboard": return "keyboard.fill"
        case "Mouse": return "computermouse.fill"
        case "Trackpad": return "rectangle.filled.and.hand.point.up.left"
        case "Speaker": return "hifispeaker.fill"
        case "Headset", "Headphone":
            switch part {
            case "Left": return "earbud.left"
            case "Right": return "earbud.right"
            case "Case": return "earbuds.case.fill"
            default: return "headphones"
            }
        default: return "battery.100percent"
        }
    }
}

enum DeviceError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct BatteryDevice: Identifiable {
    let id: String
    let name: String
    let level: Int
    let charging: Bool
    let symbol: String
    let iconFile: String?
    let isCustom: Bool

    static func current(custom: [CustomDevice]) -> [BatteryDevice] {
        let customIdentifiers = Set(custom.map(\.systemIdentifier))
        let system = BPSystemBridge.systemDevices().compactMap { raw -> BatteryDevice? in
            guard (raw["Is Present"] as? NSNumber)?.boolValue != false,
                  let capacity = raw["Current Capacity"] as? NSNumber,
                  let maximum = raw["Max Capacity"] as? NSNumber,
                  maximum.doubleValue > 0 else { return nil }
            let identifier = raw["Accessory Identifier"] as? String ?? ""
            guard !customIdentifiers.contains(identifier) else { return nil }
            let internalBattery = raw["Type"] as? String == "InternalBattery"
            let category = raw["Accessory Category"] as? String ?? "Unknown"
            let part = raw["Part Identifier"] as? String
            let name = internalBattery ? (Host.current().localizedName ?? "Mac") : (raw["Name"] as? String ?? L10n.text("Device"))
            let suffix = part.flatMap { ["Left": L10n.text("Left earbud"), "Right": L10n.text("Right earbud"), "Case": L10n.text("Charging case")][$0] }
            let sourceID = (raw["Power Source ID"] as? NSNumber)?.stringValue ?? name
            return BatteryDevice(
                id: "system-\(sourceID)",
                name: suffix.map { "\(name) · \($0)" } ?? name,
                level: min(100, max(0, Int((capacity.doubleValue / maximum.doubleValue * 100).rounded()))),
                charging: (raw["Is Charging"] as? NSNumber)?.boolValue ?? false,
                symbol: internalBattery ? "laptopcomputer" : CustomDevice.symbol(for: category, part: part),
                iconFile: nil,
                isCustom: false
            )
        }
        return system + custom.filter(\.isAvailable).map {
            BatteryDevice(id: $0.id, name: $0.name, level: $0.level, charging: $0.charging,
                          symbol: $0.symbol, iconFile: $0.iconFile, isCustom: true)
        }
    }
}

struct BatteryScript: Codable, Equatable {
    var command: String = ""
    var interval: Int = 60

    func validate() throws {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeviceError.invalid(L10n.text("Enter a command to read the battery level"))
        }
        guard (15...86400).contains(interval) else {
            throw DeviceError.invalid(L10n.text("The update interval must be between 15 and 86400 seconds"))
        }
    }
}
