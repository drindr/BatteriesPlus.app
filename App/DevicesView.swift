import SwiftUI
import UniformTypeIdentifiers

struct DevicesView: View {
    @EnvironmentObject var model: AppModel
    @State private var editingDevice: CustomDevice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Batteries++").font(.largeTitle.weight(.semibold))
                        Text(L10n.text("Battery levels for system and custom devices")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editingDevice = CustomDevice(id: UUID().uuidString.lowercased(), name: "")
                    } label: {
                        Label(L10n.text("Register Device"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n")
                }

                if !model.devices.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 28) {
                            ForEach(model.devices) { device in
                                VStack(spacing: 10) {
                                    ChargeRing(device: device)
                                    Text(device.name)
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(2).multilineTextAlignment(.center)
                                        .frame(width: 100)
                                }
                            }
                        }
                        .padding(.vertical, 14)
                    }
                    .padding(.horizontal, 18)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
                }

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("Custom Devices")).font(.title3.weight(.semibold))
                    if model.customDevices.isEmpty {
                        Text(L10n.text("Register a device to update its battery level, assign an icon, and sync it to the system battery list."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.customDevices) { custom in
                        HStack(spacing: 12) {
                            if let display = model.devices.first(where: { $0.id == custom.id }) {
                                BatteryRow(device: display)
                            } else {
                                Text(custom.name)
                                Text(L10n.text("Disconnected")).foregroundStyle(.secondary)
                                Spacer()
                            }
                            Button(L10n.text("Edit")) { editingDevice = custom }
                            Button(role: .destructive) { model.delete(custom) } label: {
                                Image(systemName: "trash")
                            }
                            .help(L10n.text("Remove Device"))
                        }
                        if let status = model.scriptStatus[custom.id] {
                            Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if custom.id != model.customDevices.last?.id { Divider() }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("System Devices")).font(.title3.weight(.semibold))
                    ForEach(model.devices.filter { !$0.isCustom }) { device in BatteryRow(device: device) }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.text("Add a Desktop Widget"), systemImage: "square.grid.2x2")
                        .font(.headline)
                    Text(L10n.text("Right-click the desktop, choose Edit Widgets, and search for Batteries++. Small, medium, and large sizes are supported."))
                    Text(L10n.text("Custom icons appear in Batteries++. System battery entries use the system icon for their device category."))
                    Text(L10n.text("System battery entries are published while the app is running and released when it quits."))
                }
                .font(.callout).foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            .padding(28)
        }
        .toolbar { Button(L10n.text("Refresh"), systemImage: "arrow.clockwise") { model.reload(); model.refreshScripts(force: true) } }
        .sheet(item: $editingDevice) { device in
            DeviceEditor(device: device).environmentObject(model)
        }
    }
}

struct DeviceEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State var device: CustomDevice
    @State private var error: String?
    @State private var testing = false
    @State private var testResult: String?

    private var preview: BatteryDevice {
        BatteryDevice(id: device.id, name: device.name, level: device.level, charging: device.charging,
                      symbol: device.symbol, iconFile: device.iconFile, isCustom: true)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(device.name.isEmpty ? L10n.text("Register Device") : L10n.text("Edit Device")).font(.title2.weight(.semibold))
                Spacer()
                ChargeRing(device: preview, compact: true)
            }
            Form {
                TextField(L10n.text("Name"), text: $device.name)
                LabeledContent(L10n.text("Device ID")) {
                    Text(device.id).font(.caption.monospaced()).textSelection(.enabled)
                }
                Picker(L10n.text("Category"), selection: $device.category) {
                    ForEach(CustomDevice.categories, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: device.category) { old, new in
                    if device.symbol == CustomDevice.symbol(for: old) { device.symbol = CustomDevice.symbol(for: new) }
                }
                LabeledContent(L10n.text("Battery Level")) {
                    Slider(value: Binding(get: { Double(device.level) }, set: { device.level = Int($0.rounded()) }), in: 0...100, step: 1)
                    Text("\(device.level)%").monospacedDigit().frame(width: 44)
                }
                Toggle(L10n.text("Charging"), isOn: $device.charging)
                Picker(L10n.text("Built-in Icon"), selection: Binding(
                    get: { device.iconFile == nil && ["elytra.left", "elytra.right"].contains(device.symbol) ? device.symbol : "custom" },
                    set: { value in
                        device.iconFile = nil
                        device.symbol = value == "custom" ? CustomDevice.symbol(for: device.category) : value
                    }
                )) {
                    Text(L10n.text("SF Symbol / Custom Image")).tag("custom")
                    Text(L10n.text("Elim Elytra Left")).tag("elytra.left")
                    Text(L10n.text("Elim Elytra Right")).tag("elytra.right")
                }
                if !["elytra.left", "elytra.right"].contains(device.symbol) {
                    TextField(L10n.text("SF Symbol Name"), text: $device.symbol)
                }
                LabeledContent(L10n.text("Custom Image")) {
                    Button(L10n.text("Choose Image…"), action: selectImage)
                    if device.iconFile != nil { Button(L10n.text("Use Symbol Icon")) { device.iconFile = nil } }
                }
                Toggle(L10n.text("Read Battery Level with a Script"), isOn: Binding(
                    get: { device.script != nil },
                    set: { device.script = $0 ? BatteryScript() : nil }
                ))
                if device.script != nil {
                    TextField(L10n.text("Script Command"), text: Binding(
                        get: { device.script?.command ?? "" },
                        set: { device.script?.command = $0; testResult = nil }
                    ), axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)
                    LabeledContent(L10n.text("Update Interval (seconds)")) {
                        TextField("60", value: Binding(
                            get: { device.script?.interval ?? 60 },
                            set: { device.script?.interval = $0 }
                        ), format: .number.grouping(.never))
                        .frame(width: 90)
                    }
                    Text(L10n.text("Runs with /bin/zsh. Output an integer from 0 to 100 or JSON {\"level\":75,\"charging\":false}. Output {\"connected\":false} when disconnected. Updates while the app is running, with a 10-second timeout."))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(testing ? L10n.text("Testing…") : L10n.text("Test Now"), action: testScript).disabled(testing)
                        if let testResult { Text(testResult).font(.caption).textSelection(.enabled) }
                    }
                }
                Toggle(L10n.text("Sync to the System Battery List"), isOn: $device.syncToSystem)
            }
            .formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("Save")) {
                    do {
                        device.name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        try device.validate()
                        try model.save(device)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600, height: 760)
    }

    private func testScript() {
        guard let script = device.script else { return }
        testing = true
        testResult = nil
        let deviceID = device.id
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try BatteryScriptRunner.run(script, deviceID: deviceID) }
            }.value
            testing = false
            guard device.script == script else { return }
            do {
                let reading = try result.get()
                device.connected = reading.connected
                if let level = reading.level { device.level = level }
                if let charging = reading.charging { device.charging = charging }
                testResult = reading.level.map { L10n.text("Success, battery %d%%", $0) } ?? L10n.text("Device disconnected")
            } catch { testResult = error.localizedDescription }
        }
    }

    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { device.iconFile = try DeviceStore.importIcon(from: url) }
        catch { self.error = error.localizedDescription }
    }
}
