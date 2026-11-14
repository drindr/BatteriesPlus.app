import AppKit
import Combine
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var customDevices: [CustomDevice] = []
    @Published var devices: [BatteryDevice] = []
    @Published var errorMessage: String?
    @Published var scriptStatus: [String: String] = [:]
    private var nextScriptRun: [String: Date] = [:]
    private var runningScripts = Set<String>()
    private var scriptConfigurations: [String: BatteryScript] = [:]
    private var publishedIDs = Set<String>()
    private var timer: Timer?
    private var scriptTimer: Timer?
    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(DeviceStore.notification), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        scriptTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshScripts() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSystem() }
        }
    }

    func reload() {
        do {
            let stored = try DeviceStore.read()
            let wanted = Set(stored.filter { $0.syncToSystem && $0.isAvailable }.map(\.systemIdentifier))
            for identifier in publishedIDs.subtracting(wanted) { BPSystemBridge.remove(identifier) }
            publishedIDs.formIntersection(wanted)
            var failures: [String] = []
            for device in stored where device.syncToSystem && device.isAvailable {
                let result = BPSystemBridge.publish(device.powerSourceDetails, identifier: device.systemIdentifier)
                if result == 0 { publishedIDs.insert(device.systemIdentifier) }
                else { failures.append("\(device.name): \(String(format: "0x%08x", UInt32(bitPattern: result)))") }
            }
            customDevices = stored
            errorMessage = failures.isEmpty ? nil : L10n.text("System battery sync failed\n") + failures.joined(separator: "\n")
            refreshSystem()
            refreshScripts()
            WidgetCenter.shared.reloadTimelines(ofKind: DeviceStore.widgetKind)
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshSystem() {
        devices = BatteryDevice.current(custom: customDevices)
    }

    func refreshScripts(force: Bool = false) {
        let configured = Set(customDevices.filter { $0.script != nil }.map(\.id))
        nextScriptRun = nextScriptRun.filter { configured.contains($0.key) }
        scriptStatus = scriptStatus.filter { configured.contains($0.key) }
        scriptConfigurations = scriptConfigurations.filter { configured.contains($0.key) }
        for device in customDevices {
            guard let script = device.script, !runningScripts.contains(device.id) else { continue }
            let changed = scriptConfigurations[device.id] != script
            guard force || changed || (nextScriptRun[device.id] ?? .distantPast) <= Date() else { continue }
            scriptConfigurations[device.id] = script
            nextScriptRun[device.id] = Date().addingTimeInterval(TimeInterval(script.interval))
            runningScripts.insert(device.id)
            scriptStatus[device.id] = L10n.text("Reading battery level…")
            Task {
                let result = await Task.detached(priority: .utility) {
                    Result { try BatteryScriptRunner.run(script, deviceID: device.id) }
                }.value
                self.runningScripts.remove(device.id)
                guard self.customDevices.contains(where: { $0.id == device.id && $0.script == script }) else {
                    self.refreshScripts()
                    return
                }
                do {
                    let reading = try result.get()
                    try DeviceStore.update { stored in
                        guard let index = stored.firstIndex(where: { $0.id == device.id && $0.script == script }) else { return }
                        stored[index].connected = reading.connected
                        if let level = reading.level { stored[index].level = level }
                        if let charging = reading.charging { stored[index].charging = charging }
                    }
                    self.scriptStatus[device.id] = reading.connected
                        ? L10n.text("Updated %@", Date().formatted(date: .omitted, time: .standard))
                        : L10n.text("Device disconnected")
                    self.reload()
                } catch {
                    self.scriptStatus[device.id] = error.localizedDescription
                    do {
                        try DeviceStore.update { stored in
                            guard let index = stored.firstIndex(where: { $0.id == device.id && $0.script == script }) else { return }
                            stored[index].connected = false
                        }
                        self.reload()
                    } catch { self.errorMessage = error.localizedDescription }
                }
            }
        }
    }

    func save(_ device: CustomDevice) throws {
        try DeviceStore.update { devices in
            if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
            else { devices.append(device) }
        }
        reload()
    }

    func delete(_ device: CustomDevice) {
        do {
            try DeviceStore.update { $0.removeAll { $0.id == device.id } }
            reload()
        } catch { errorMessage = error.localizedDescription }
    }
}
