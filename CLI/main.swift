import AppKit
import Foundation
import WidgetKit

let help = """
batteryctl register --id ID --name NAME --level 75 [--category Keyboard]
                    [--symbol keyboard.fill | --icon /path/to/image.png]
                    [--charging true|false] [--system-sync true|false]
                    [--script COMMAND] [--interval 60]
batteryctl update --id ID [--level 50] [--name NAME] [--icon /path/to/image.png]
batteryctl remove --id ID
batteryctl list
batteryctl diagnose

Built-in icons: --symbol elytra.left | --symbol elytra.right
Remove script: --script ""
Supported categories: Keyboard, Mouse, Trackpad, Headset, Speaker, Unknown
"""

func boolean(_ value: String) throws -> Bool {
    switch value {
    case "true": return true
    case "false": return false
    default: throw DeviceError.invalid(L10n.text("Boolean values must be true or false"))
    }
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first, command != "--help", command != "help" else {
        print(help)
        return
    }
    var options: [String: String] = [:]
    var index = 1
    let allowed = Set(["--id", "--name", "--level", "--category", "--symbol", "--icon", "--charging", "--system-sync", "--script", "--interval"])
    while index < arguments.count {
        let flag = arguments[index]
        guard allowed.contains(flag), index + 1 < arguments.count, options[flag] == nil else {
            throw DeviceError.invalid(L10n.text("Invalid or duplicate option: %@", flag))
        }
        options[flag] = arguments[index + 1]
        index += 2
    }
    if command == "list" {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(DeviceStore.read()), as: UTF8.self))
        return
    }
    if command == "diagnose" {
        print("Shared container: \(try DeviceStore.directory().path)")
        print("Registered devices: \(try DeviceStore.read().count)")
        print("Visible battery devices: \(BatteryDevice.current(custom: try DeviceStore.read()).count)")
        return
    }
    guard ["register", "update", "remove"].contains(command) else {
        throw DeviceError.invalid(L10n.text("Unknown command: %@\n%@", command, help))
    }
    guard let id = options["--id"], !id.isEmpty else { throw DeviceError.invalid(L10n.text("--id is required")) }
    guard !(options["--icon"] != nil && options["--symbol"] != nil) else {
        throw DeviceError.invalid(L10n.text("Choose either --icon or --symbol"))
    }
    let icon = try options["--icon"].map { try DeviceStore.importIcon(from: URL(fileURLWithPath: $0)) }
    let result = try DeviceStore.update { devices in
        let position = devices.firstIndex { $0.id == id }
        if command == "remove" {
            guard let position else { throw DeviceError.invalid(L10n.text("Device not found: %@", id)) }
            devices.remove(at: position)
            return
        }
        if command == "update", position == nil { throw DeviceError.invalid(L10n.text("Device not found: %@", id)) }
        var device = position.map { devices[$0] } ?? CustomDevice(id: id, name: "")
        if let name = options["--name"] { device.name = name }
        if let level = options["--level"] {
            guard let level = Int(level) else { throw DeviceError.invalid(L10n.text("--level must be an integer")) }
            device.level = level
        }
        if let category = options["--category"] {
            device.category = category
            if options["--symbol"] == nil, device.iconFile == nil { device.symbol = CustomDevice.symbol(for: category) }
        }
        if let symbol = options["--symbol"] { device.symbol = symbol; device.iconFile = nil }
        if let icon { device.iconFile = icon }
        if let value = options["--charging"] { device.charging = try boolean(value) }
        if let value = options["--system-sync"] { device.syncToSystem = try boolean(value) }
        if let command = options["--script"] {
            device.script = command.isEmpty ? nil : BatteryScript(command: command, interval: device.script?.interval ?? 60)
        }
        if let interval = options["--interval"] {
            guard let seconds = Int(interval), device.script != nil else {
                throw DeviceError.invalid(L10n.text("--interval requires an integer and a configured script"))
            }
            device.script?.interval = seconds
        }
        try device.validate()
        if let position { devices[position] = device }
        else { devices.append(device) }
    }
    WidgetCenter.shared.reloadTimelines(ofKind: DeviceStore.widgetKind)
    print("\(command): \(id) (\(result.count) devices)")

    // Start the companion application so it can publish the updated system power sources.
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    if app.pathExtension == "app" {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { fputs("App launch: \(error.localizedDescription)\n", stderr) }
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    }
}

do { try run() }
catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
