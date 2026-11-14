import AppKit
import Darwin
import Foundation

enum DeviceStore {
    static let notification = "local.batteriesplus.devicesChanged"
    static let widgetKind = "BatteriesPlusWidget"

    static func directory(create: Bool = false) throws -> URL {
        guard let account = getpwuid(getuid()) else { throw POSIXError(.ENOENT) }
        let home = URL(fileURLWithPath: String(cString: account.pointee.pw_dir))
        let directory = home.appendingPathComponent("Library/Application Support/BatteriesPlus", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func read() throws -> [CustomDevice] {
        let path = try directory().appendingPathComponent("devices.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try JSONDecoder().decode([CustomDevice].self, from: Data(contentsOf: path))
    }

    @discardableResult
    static func update(_ change: (inout [CustomDevice]) throws -> Void) throws -> [CustomDevice] {
        let directory = try directory(create: true)
        let lockPath = directory.appendingPathComponent("devices.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }
        var devices = try read()
        try change(&devices)
        for device in devices { try device.validate() }
        guard Set(devices.map(\.id)).count == devices.count else {
            throw DeviceError.invalid(L10n.text("Duplicate device ID"))
        }
        let data = try JSONEncoder().encode(devices)
        try data.write(to: directory.appendingPathComponent("devices.json"), options: .atomic)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(notification), object: nil, userInfo: nil, deliverImmediately: true
        )
        return devices
    }

    static func importIcon(from url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            throw DeviceError.invalid(L10n.text("Unable to read the image"))
        }
        // Rasterize to a bounded PNG that the widget can read from its shared container.
        let size = NSSize(width: 256, height: 256)
        let output = NSImage(size: size)
        output.lockFocus()
        let scale = min(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
        let rect = NSRect(x: (256 - image.size.width * scale) / 2,
                          y: (256 - image.size.height * scale) / 2,
                          width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: rect)
        output.unlockFocus()
        guard let tiff = output.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw DeviceError.invalid(L10n.text("Image conversion failed"))
        }
        let name = UUID().uuidString + ".png"
        try png.write(to: directory(create: true).appendingPathComponent(name), options: .atomic)
        return name
    }

    static func icon(named name: String?) -> NSImage? {
        guard let name, URL(fileURLWithPath: name).lastPathComponent == name,
              let directory = try? directory() else { return nil }
        return NSImage(contentsOf: directory.appendingPathComponent(name))
    }
}
